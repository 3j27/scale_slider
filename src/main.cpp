#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <cstdio>
#include "backend.h"
#include "theme.h"
#include "translator.h"

int main(int argc, char **argv) {
    QStringList args;
    for (int i = 1; i < argc; ++i) args << QString::fromLocal8Bit(argv[i]);
    bool cli = args.contains("set") || args.contains("check") || args.contains("skill");
    if (cli || args.contains("--screenshot")) qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    app.setApplicationName("scale-slider");
    app.setApplicationVersion("0.1.0");
    app.setDesktopFileName("scale-slider");
    auto option = [&](const QString &name, const QString &fallback = QString()) {
        int index = args.indexOf(name);
        return index >= 0 && index + 1 < args.size() ? args[index + 1] : fallback;
    };
    QString path = option("--config");
    Backend backend(path, option("--hyprctl", "hyprctl"));
    if (cli) {
        bool ok = true;
        QString message;
        if (args.contains("skill")) {
            if (!args.contains("install")) return 1;
            QString folder = QDir::homePath() + "/.codex/skills/scale-slider";
            QDir().mkpath(folder);
            QFile file(folder + "/SKILL.md");
            ok = file.open(QIODevice::WriteOnly);
            if (ok) file.write("---\nname: scale-slider\ndescription: Adjust Omarchy display scale using Scale Slider.\n---\nRun `scale-slider check --json` to inspect the saved scale.\nRun `scale-slider set VALUE --json` for a scale from 1.0 to 2.0.\nWrites ~/.config/hypr/monitors.lua atomically, enables fractional scaling, backs up and validates with Hyprland.\nRun `scale-slider open` for the GUI.\n");
            message = folder;
        } else if (args.contains("set")) {
            int index = args.indexOf("set");
            bool number = false;
            double scale = index + 1 < args.size() ? args[index + 1].toDouble(&number) : 0;
            ok = number && backend.apply(scale);
            message = number ? backend.status() : "Expected a scale between 1.0 and 2.0.";
        } else {
            QFile file(backend.path());
            QString error;
            ok = file.open(QIODevice::ReadOnly);
            if (ok) Backend::rewrite(QString::fromUtf8(file.readAll()), backend.scale(), &error);
            ok = ok && error.isEmpty();
            message = ok ? "Configuration is editable." : (error.isEmpty() ? file.errorString() : error);
        }
        QJsonObject result{{"ok", ok}, {"scale", backend.scale()}, {"config", backend.path()}, {"message", message}};
        QByteArray output = args.contains("--json") ? QJsonDocument(result).toJson(QJsonDocument::Compact) : message.toUtf8();
        fprintf(ok ? stdout : stderr, "%s\n", output.constData());
        return ok ? 0 : 1;
    }
    QQuickStyle::setStyle("Material");
    Translator translator;
    app.installTranslator(&translator);
    Theme theme;
    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty()) return 1;
    QString screenshot = option("--screenshot");
    if (!screenshot.isEmpty()) QTimer::singleShot(700, &app, [&] {
        auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        app.exit(window && window->grabWindow().save(screenshot) ? 0 : 1);
    });
    return app.exec();
}
