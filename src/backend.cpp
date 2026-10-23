#include "backend.h"
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <cmath>

static QRegularExpression assignment(R"re(^([ \t]*)(?:local[ \t]+)?omarchy_monitor_scale[ \t]*=[ \t]*("auto"|'auto'|"[0-9.]+"|'[0-9.]+'|[0-9.]+)[ \t]*;?[ \t]*(--[^\n]*)?$)re", QRegularExpression::MultilineOption);
static bool save(const QString &path, const QByteArray &data) {
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(data) == data.size() && file.commit();
}
static QByteArray read(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

Backend::Backend(QString path, QString command, QObject *parent)
    : QObject(parent), m_path(path.isEmpty() ? QDir::homePath() + "/.config/hypr/monitors.lua" : path), m_command(command) {
    if (qEnvironmentVariableIsEmpty("HYPRLAND_INSTANCE_SIGNATURE")) {
        bool ok;
        auto instances = QJsonDocument::fromJson(run({"instances", "-j"}, &ok).toUtf8()).array();
        if (ok && instances.size() == 1)
            m_instance = {"-i", instances.first().toObject().value("instance").toString()};
    }
    bool numeric = false;
    auto matches = assignment.globalMatch(QString::fromUtf8(read(m_path)));
    while (matches.hasNext()) {
        QString v = matches.next().captured(2);
        v.remove('"'); v.remove('\'');
        m_scale = v.toDouble(&numeric);
    }
    if (!numeric) {
        bool ok;
        const auto monitors = QJsonDocument::fromJson(run({"monitors", "-j"}, &ok).toUtf8()).array();
        m_scale = 1.5;
        for (const auto &monitor : monitors) {
            auto obj = monitor.toObject();
            if (obj.value("focused").toBool() || monitors.size() == 1) {
                m_scale = obj.value("scale").toDouble(1.5); break;
            }
        }
    }
    m_scale = qBound(1.0, m_scale, 2.0);
    m_pending = m_scale;
    m_history.append(m_scale);
    m_status = tr("Changes apply as you move the slider.");
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(120);
    connect(&m_debounce, &QTimer::timeout, this, &Backend::flush);
}

void Backend::report(const QString &text, bool failed) {
    m_status = text; m_failed = failed; emit changed();
}

QString Backend::run(const QStringList &arguments, bool *ok) {
    QProcess process;
    process.start(m_command, m_instance + arguments);
    if (!process.waitForStarted(1500) || !process.waitForFinished(3000)) {
        process.kill(); process.waitForFinished(500);
        *ok = false;
        return tr("Could not run hyprctl: %1").arg(process.errorString());
    }
    *ok = process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
    return QString::fromUtf8(process.readAllStandardOutput()) + QString::fromUtf8(process.readAllStandardError());
}

QString Backend::rewrite(const QString &source, double value, QString *error) {
    if (!std::isfinite(value) || value < 1 || value > 2) {
        *error = tr("Scale must be between 1.0 and 2.0."); return {};
    }
    // Only accept simple top-level assignments, never guess at arbitrary Lua.
    if (source.contains("--[[") || source.contains("[=[")) {
        *error = tr("Block comments or long strings need manual review before editing."); return {};
    }
    QList<QRegularExpressionMatch> matches;
    auto iterator = assignment.globalMatch(source);
    while (iterator.hasNext()) matches.append(iterator.next());
    if (matches.isEmpty()) {
        *error = tr("No simple omarchy_monitor_scale assignment found in monitors.lua."); return {};
    }
    for (const auto &match : matches) {
        if (!match.captured(1).isEmpty()) {
            *error = tr("Scale assignments must be at the top level of monitors.lua."); return {};
        }
    }
    QString result = source;
    // The last declaration is effective; earlier duplicates are commented out.
    for (int i = matches.size() - 1; i >= 0; --i) {
        const auto &match = matches[i];
        QString replacement = i == matches.size() - 1
            ? "local omarchy_monitor_scale = " + QString::number(value, 'f', 2) + (match.captured(3).isEmpty() ? "" : " " + match.captured(3))
            : "-- " + match.captured();
        result.replace(match.capturedStart(), match.capturedLength(), replacement);
    }
    const QString setting = "hl.config({ debug = { disable_scale_checks = true } })";
    // Keep one final override, after any existing settings that could disable it.
    const QString marker = "-- Scale Slider: allow fractional desktop dimensions.\n";
    result.replace(marker + setting + "\n", "");
    if (!result.endsWith('\n')) result += '\n';
    result += "\n" + marker + setting + "\n";
    // Avoid adding a blank line on each slider tick.
    result.replace("\n\n\n" + marker, "\n\n" + marker);
    return result;
}

bool Backend::apply(double value) {
    QLockFile lock(m_path + ".scale-slider.lock");
    if (!lock.tryLock(0)) { report(tr("Another Scale Slider is updating this file."), true); return false; }
    QFile original(m_path);
    if (!original.open(QIODevice::ReadOnly)) { report(tr("Cannot read %1: %2").arg(m_path, original.errorString()), true); return false; }
    const QByteArray before = original.readAll(); original.close();
    QString error;
    const auto after = rewrite(QString::fromUtf8(before), value, &error).toUtf8();
    if (!error.isEmpty()) { report(error, true); return false; }
    bool ok;
    const QString existingErrors = run({"configerrors"}, &ok).trimmed();
    if (!ok || !existingErrors.isEmpty()) { report(tr("Fix existing Hyprland errors first: %1").arg(existingErrors), true); return false; }
    if (m_backup.isEmpty()) {
        m_backup = m_path + ".bak.scale-slider." + QDateTime::currentDateTimeUtc().toString("yyyyMMdd-HHmmss-zzz");
        if (!QFile::copy(m_path, m_backup)) { m_backup.clear(); report(tr("Cannot create a backup beside monitors.lua."), true); return false; }
    }
    if (read(m_path) != before) { report(tr("The file changed during the update. Move the slider again."), true); return false; }
    if (!save(m_path, after)) { report(tr("Cannot save monitors.lua."), true); return false; }
    QString output = run({"reload"}, &ok);
    if (ok) {
        output = run({"configerrors"}, &ok).trimmed();
        ok = ok && output.isEmpty();
    }
    if (!ok) {
        // Do not overwrite an editor's newer contents during rollback.
        if (read(m_path) == after && save(m_path, before)) {
            bool restored;
            run({"reload"}, &restored);
            run({"configerrors"}, &restored);
            report(tr("Hyprland rejected the change; restored the previous file. %1").arg(output), true);
        } else report(tr("Update failed. Restore the backup at %1. %2").arg(m_backup, output), true);
        return false;
    }
    m_scale = value;
    report(tr("Saved and applied. You can close this window."), false);
    return true;
}

void Backend::requestScale(double value) {
    if (!std::isfinite(value)) return;
    m_dirty = true;
    m_pending = std::round(qBound(1.0, value, 2.0) * 100) / 100;
    // Throttle rather than restart on every event, so dragging previews live.
    if (!m_debounce.isActive()) m_debounce.start();
}
bool Backend::flush() {
    m_debounce.stop();
    if (!m_dirty) return true;
    m_dirty = false;
    if (apply(m_pending)) {
        if (m_history[m_position] != m_scale) {
            m_history = m_history.mid(0, m_position + 1);
            m_history.append(m_scale); ++m_position;
        }
        return true;
    }
    return false;
}
void Backend::undo() {
    m_debounce.stop();
    if (m_position > 0 && apply(m_history[m_position - 1])) { --m_position; m_pending = m_scale; }
}
void Backend::redo() {
    m_debounce.stop();
    if (m_position + 1 < m_history.size() && apply(m_history[m_position + 1])) { ++m_position; m_pending = m_scale; }
}
