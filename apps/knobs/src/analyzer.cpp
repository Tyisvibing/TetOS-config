#include "analyzer.h"

#include "configdocument.h"

#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocale>
#include <QStandardPaths>
#include <QUrl>

Analyzer::Analyzer(QObject *parent) : QObject(parent) {
    m_process.setProcessChannelMode(QProcess::SeparateChannels);
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &Analyzer::readOutput);
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        m_errorText += QString::fromUtf8(m_process.readAllStandardError());
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            emit failed(tr("Couldn't start Claude Code: %1").arg(m_process.errorString()));
    });
    connect(&m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus) {
        readOutput();
        if (!m_buffer.trimmed().isEmpty())
            handleLine(m_buffer);
        m_buffer.clear();
        if (m_cancelled)
            return;
        const auto structured = m_result.value("structured_output").toObject();
        if (m_result.value("is_error").toBool() || structured.isEmpty()) {
            QString why = m_result.value("result").toString().trimmed();
            if (why.isEmpty()) why = m_errorText.trimmed().section('\n', -3);
            if (why.isEmpty()) why = tr("Claude Code exited with code %1.").arg(code);
            emit failed(why);
            return;
        }
        emit finished(structured);
    });
}

Analyzer::~Analyzer() { cancel(); }

QString Analyzer::findClaude() {
    const QString overridden = qEnvironmentVariable("KNOBS_CLAUDE");
    if (!overridden.isEmpty())
        return overridden;
    const QString found = QStandardPaths::findExecutable("claude");
    if (!found.isEmpty())
        return found;
    const QString home = QDir::homePath();
    return QStandardPaths::findExecutable("claude", {
        home + "/.local/bin", home + "/.claude/local", home + "/.local/share/mise/command-wrappers/bin",
        home + "/.local/share/mise/shims", home + "/.npm-global/bin", home + "/.bun/bin", "/usr/local/bin",
    });
}

QStringList Analyzer::arguments() {
    const QString model = qEnvironmentVariable("KNOBS_MODEL", "sonnet");
    return {
        "-p", "--output-format", "stream-json", "--verbose", "--no-session-persistence",
        "--model", model,
        "--json-schema", QString::fromUtf8(QJsonDocument(ConfigDocument::schema()).toJson(QJsonDocument::Compact)),
        // Read-only tools only: Claude can look things up but never touch files.
        "--tools", "Read,Grep,Glob,Bash,WebSearch,WebFetch",
        "--allowedTools", "Read,Grep,Glob,WebSearch,WebFetch,Bash(man:*),Bash(ls:*),Bash(pacman -Qo:*),Bash(pacman -Ql:*),Bash(pacman -Qi:*)",
    };
}

QString Analyzer::prompt(const QString &path, const QString &text, const QString &language) {
    QString numbered;
    const QStringList lines = text.split('\n');
    for (int i = 0; i < lines.size(); ++i)
        numbered += QString("%1| %2\n").arg(i + 1, 5).arg(lines.at(i));

    QString languageName = QLocale(language).nativeLanguageName();
    if (language == "en" || languageName.isEmpty()) languageName = "English";

    return QString(R"(You are powering a settings editor. A person opened the config file below and wants
every setting it can hold shown as a menu, each explained in plain words.

1. Work out which program reads this file and which version is installed (`pacman -Qo <path>`
   and `pacman -Qi` help). Find its official documentation: the man page (`man -P cat <page>`),
   files under /usr/share/doc, the package's own example config (`pacman -Ql <pkg>`), and the
   official website or wiki. Prefer the docs for the installed version.
2. List EVERY option the program accepts in this file, not only the ones already set. Include the
   ones the file sets. Leave out things that are not single settings (key bindings, rules, blocks
   repeated per item, `source` includes) unless the file is mostly made of them.
3. For an option the file sets, give its exact line number and the value exactly as written on that
   line. Use the numbered listing; the numbers are not part of the file.
4. For an option the file does not set, give a full line that would set it and the line it belongs
   after, inside the correct section or block that already exists. If its section doesn't exist,
   use the end of the file and write the line so it is valid there (e.g. hyprlang's
   `general:gaps_in = {value}` or TOML's dotted keys).
5. Write the description, section names and summary in %1. Keep option names as they are.

File: %2

%3)").arg(languageName, path, numbered);
}

void Analyzer::start(const QString &path, const QString &text, const QString &language) {
    cancel();
    m_cancelled = false;
    m_result = {};
    m_errorText.clear();
    m_buffer.clear();

    const QString claude = findClaude();
    if (claude.isEmpty()) {
        emit failed(tr("Claude Code isn't installed. knobs uses it to read the documentation; "
                       "install it with: curl -fsSL https://claude.ai/install.sh | bash"));
        return;
    }

    // A scratch directory as the working directory, so nothing Claude does
    // starts out next to the user's files.
    const QString work = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/work";
    QDir().mkpath(work);
    m_process.setWorkingDirectory(work);
    m_process.start(claude, arguments());
    m_process.write(prompt(path, text, language).toUtf8());
    m_process.closeWriteChannel();
    emit status(tr("Looking for the documentation…"));
}

void Analyzer::cancel() {
    if (m_process.state() == QProcess::NotRunning)
        return;
    m_cancelled = true;
    m_process.terminate();
    if (!m_process.waitForFinished(1500))
        m_process.kill();
    m_process.waitForFinished(500);
}

void Analyzer::readOutput() {
    m_buffer += m_process.readAllStandardOutput();
    int newline;
    while ((newline = m_buffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_buffer.left(newline);
        m_buffer.remove(0, newline + 1);
        if (!line.trimmed().isEmpty())
            handleLine(line);
    }
}

void Analyzer::handleLine(const QByteArray &line) {
    const QJsonObject event = QJsonDocument::fromJson(line).object();
    if (event.value("type").toString() == "result") {
        m_result = event;
        return;
    }
    const QString text = describe(event);
    if (!text.isEmpty())
        emit status(text);
}

QString Analyzer::describe(const QJsonObject &event) {
    if (event.value("type").toString() != "assistant")
        return {};
    QString last;
    for (const auto &value : event.value("message").toObject().value("content").toArray()) {
        const auto block = value.toObject();
        if (block.value("type").toString() != "tool_use")
            continue;
        const QString name = block.value("name").toString();
        const auto input = block.value("input").toObject();
        if (name == "WebSearch")
            last = tr("Searching the web for “%1”").arg(input.value("query").toString());
        else if (name == "WebFetch")
            last = tr("Reading %1").arg(QUrl(input.value("url").toString()).host());
        else if (name == "Bash")
            last = tr("Running %1").arg(input.value("command").toString().left(60));
        else if (name == "Read")
            last = tr("Reading %1").arg(QFileInfo(input.value("file_path").toString()).fileName());
        else if (name == "Grep" || name == "Glob")
            last = tr("Searching local files");
        else if (name == "StructuredOutput")
            last = tr("Writing up %n settings", "", input.value("options").toArray().size());
    }
    return last;
}
