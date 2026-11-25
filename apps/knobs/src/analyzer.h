#pragma once

#include <QJsonObject>
#include <QObject>
#include <QProcess>

// Asks Claude Code (`claude -p`) to find the documentation for a config file
// and describe every option it supports. Claude does the looking itself, with
// read-only tools: man pages, /usr/share/doc, the package's files, and the web.
class Analyzer : public QObject {
    Q_OBJECT

public:
    explicit Analyzer(QObject *parent = nullptr);
    ~Analyzer() override;

    bool isRunning() const { return m_process.state() != QProcess::NotRunning; }
    void start(const QString &path, const QString &text, const QString &language);
    void cancel();

    // The claude binary: $KNOBS_CLAUDE, then $PATH, then where installers put
    // it, since apps started from the launcher don't get a shell's PATH.
    static QString findClaude();
    static QString prompt(const QString &path, const QString &text, const QString &language);
    static QStringList arguments();

    // Turns one line of Claude's stream-json output into a short status, or
    // an empty string when the line isn't worth showing.
    static QString describe(const QJsonObject &event);

signals:
    void status(const QString &text);
    void finished(const QJsonObject &analysis);
    void failed(const QString &error);

private:
    void readOutput();
    void handleLine(const QByteArray &line);

    QProcess m_process;
    QByteArray m_buffer;
    QJsonObject m_result;
    QString m_errorText;
    bool m_cancelled = false;
};
