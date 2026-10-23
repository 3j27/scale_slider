#include <QtTest>
#include <QTemporaryDir>
#include <QFile>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QQuickItem>
#include "backend.h"
#include "theme.h"
#include "translator.h"

class SliderTests : public QObject {
    Q_OBJECT
    static void write(const QString &path, const QByteArray &data) { QFile f(path); QVERIFY(f.open(QIODevice::WriteOnly)); QCOMPARE(f.write(data), data.size()); }
    static QByteArray read(const QString &path) { QFile f(path); if (!f.open(QIODevice::ReadOnly)) return {}; return f.readAll(); }
    static QString fake(QTemporaryDir &dir, bool reject = false) {
        QString path = dir.filePath("hyprctl");
        QByteArray script = "#!/bin/sh\ncase \"$1\" in\ninstances) echo '[]';;\nmonitors) echo '[{\"focused\":true,\"scale\":1.6}]';;\nreload) ";
        script += reject ? "touch \"$0.reloaded\"; echo ok;;\nconfigerrors) if test -f \"$0.reloaded\"; then echo 'invalid config'; fi;;\n" : "echo ok;;\nconfigerrors) :;;\n";
        script += "esac\n";
        write(path, script); QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner); return path;
    }
private slots:
    void duplicateAssignmentsAndComments() {
        QString error;
        QString source = "-- local omarchy_monitor_scale = 2\nlocal omarchy_monitor_scale = \"auto\"\nlocal omarchy_monitor_scale = \"1.6\" -- keep this\nhl.monitor({scale = omarchy_monitor_scale})\nlocal unrelated = 42\n";
        auto result = Backend::rewrite(source, 1.25, &error);
        QVERIFY(error.isEmpty()); QVERIFY(result.contains("local omarchy_monitor_scale = 1.25 -- keep this"));
        QVERIFY(result.contains("-- local omarchy_monitor_scale = \"auto\""));
        QVERIFY(result.contains("local unrelated = 42"));
        QVERIFY(result.contains("disable_scale_checks = true"));
        QCOMPARE(Backend::rewrite(result, 1.25, &error), result);
    }
    void rejectsUnsafeInputs() {
        QString error;
        QVERIFY(Backend::rewrite("local omarchy_monitor_scale = 1\n", 2.1, &error).isEmpty());
        QVERIFY(!error.isEmpty()); error.clear();
        QVERIFY(Backend::rewrite("--[[\nlocal omarchy_monitor_scale = 1\n]]", 1.5, &error).isEmpty());
        error.clear(); QVERIFY(Backend::rewrite("some_function()", 1.5, &error).isEmpty());
    }
    void writesBacksUpAndPreservesExternalEdits() {
        QTemporaryDir dir; auto path = dir.filePath("monitors.lua");
        QByteArray original = "local omarchy_monitor_scale = 1.6\n"; write(path, original);
        Backend backend(path, fake(dir));
        QVERIFY(backend.apply(1.45)); QVERIFY(read(path).contains("1.45"));
        auto backups = QDir(dir.path()).entryList({"*.bak.*"}); QCOMPARE(backups.size(), 1);
        QCOMPARE(read(dir.filePath(backups.first())), original);
        write(path, read(path) + "-- external edit\n");
        QVERIFY(backend.apply(1.7)); QVERIFY(read(path).contains("-- external edit"));
    }
    void rollsBackRejectedConfig() {
        QTemporaryDir dir; auto path = dir.filePath("monitors.lua");
        QByteArray original = "local omarchy_monitor_scale = 1.6\n"; write(path, original);
        Backend backend(path, fake(dir, true));
        QVERIFY(!backend.apply(1.25)); QCOMPARE(read(path), original); QVERIFY(backend.failed());
    }
    void sliderKeyboardAndScrollUpdateFile() {
        QTemporaryDir dir; auto path = dir.filePath("monitors.lua");
        write(path, "local omarchy_monitor_scale = 1.6\n");
        Backend backend(path, fake(dir)); Theme theme(dir.path()); Translator translator(dir.filePath("language"), dir.path());
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.rootContext()->setContextProperty("theme", &theme);
        engine.rootContext()->setContextProperty("translator", &translator);
        engine.load(QUrl("qrc:/Main.qml")); QVERIFY(!engine.rootObjects().isEmpty());
        auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first()); QVERIFY(window);
        auto slider = window->findChild<QQuickItem *>("scaleSlider"); QVERIFY(slider);
        slider->forceActiveFocus();
        QTest::keyClick(window, Qt::Key_Right);
        QTRY_VERIFY(read(path).contains("1.61"));
        QPointF position = slider->mapToScene(QPointF(slider->width() / 2, slider->height() / 2));
        QWheelEvent event(position, position, QPoint(), QPoint(0, 120), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
        QGuiApplication::sendEvent(window, &event);
        QTRY_VERIFY(read(path).contains("1.62"));
        backend.undo(); QCOMPARE(backend.scale(), 1.61); backend.redo(); QCOMPARE(backend.scale(), 1.62);
        auto input = window->findChild<QQuickItem *>("scaleInput"); QVERIFY(input);
        input->forceActiveFocus();
        QTest::keyClick(window, Qt::Key_A, Qt::ControlModifier);
        for (auto key : {Qt::Key_1, Qt::Key_Period, Qt::Key_3, Qt::Key_7})
            QTest::keyClick(window, key);
        // Typing is a draft; only Enter or leaving the field applies it.
        QCOMPARE(backend.scale(), 1.62);
        QTest::keyClick(window, Qt::Key_Return);
        QTRY_COMPARE(backend.scale(), 1.37);
        QVERIFY(read(path).contains("omarchy_monitor_scale = 1.37"));
        QCOMPARE(slider->property("value").toDouble(), 1.37);
        input->setProperty("text", "2.50");
        QVERIFY(!input->property("acceptableInput").toBool());
        QTest::keyClick(window, Qt::Key_Return);
        QCOMPARE(backend.scale(), 1.37);
        QTest::keyClick(window, Qt::Key_Escape);
        QCOMPARE(input->property("text").toString(), QString("1.37"));
        // Tiling can force the app below its requested size as scale increases.
        for (const auto &size : {QSize(282, 168), QSize(240, 140), QSize(520, 320)}) {
            window->resize(size); QTest::qWait(30);
            auto heading = window->findChild<QQuickItem *>("scaleHeading"); QVERIFY(heading);
            const QRectF headingRect(heading->mapToScene(QPointF()), heading->size());
            const QRectF inputRect(input->mapToScene(QPointF()), input->size());
            const QRectF sliderRect(slider->mapToScene(QPointF()), slider->size());
            QVERIFY2(!headingRect.intersects(inputRect), "Heading overlaps the scale field");
            QVERIFY2(sliderRect.top() >= inputRect.bottom(), "Slider overlaps the scale field");
            QVERIFY(sliderRect.width() > 100);
            QVERIFY(inputRect.right() <= window->width());
        }
    }
};
int main(int argc, char **argv) {
    QGuiApplication app(argc, argv); QQuickStyle::setStyle("Material"); SliderTests tests; return QTest::qExec(&tests, argc, argv);
}
#include "scale-slider_tests.moc"
