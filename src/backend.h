#pragma once
#include <QObject>
#include <QTimer>

class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(double scale READ scale NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(bool failed READ failed NOTIFY changed)
public:
    explicit Backend(QString path = {}, QString command = "hyprctl", QObject *parent = nullptr);
    double scale() const { return m_scale; }
    QString status() const { return m_status; }
    bool failed() const { return m_failed; }
    Q_INVOKABLE void requestScale(double value);
    Q_INVOKABLE bool flush();
    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();
    bool apply(double value);
    static QString rewrite(const QString &source, double value, QString *error);
    QString path() const { return m_path; }
    QString run(const QStringList &arguments, bool *ok);
signals:
    void changed();
private:
    QString m_path, m_command, m_status, m_backup;
    QStringList m_instance;
    double m_scale = 1.5, m_pending = 1.5;
    bool m_failed = false, m_dirty = false;
    QTimer m_debounce;
    QList<double> m_history;
    int m_position = 0;
    void report(const QString &text, bool failed);
};
