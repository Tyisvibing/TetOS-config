#include "cli.h"

#include "backend.h"
#include "store.h"

#include <QCoreApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTextStream>

namespace {

const char *Usage = R"(Usage: knobs [file]                      Open the settings window
       knobs explain <file> [--refresh]     List every setting, explained
       knobs get <file> <key>               Print one setting's value
       knobs set <file> <key> <value>       Change a setting and save
       knobs unset <file> <key>             Remove a setting's line and save
       knobs skill install                  Teach Claude Code to use knobs

Add --json for machine-readable output. The first look at a file asks Claude
Code to read its documentation; later runs use the cached explanation.
)";

const char *Skill = R"(---
name: knobs
description: Read, explain, and change settings in any config file through the knobs CLI. Use when asked what a config option does, what options a config file supports, or to change a setting without hand-editing the file.
---

# knobs

`knobs` explains config files from their own documentation and edits them one
setting at a time, touching only the line it changes.

- `knobs explain <file> --json` lists every option the program supports for
  that file: key, section, type, choices, default, description, and whether
  and where the file sets it (`line` > 0). The first run reads the docs and can
  take a minute or two; later runs are cached. `--refresh` re-reads them.
- `knobs get <file> <key> --json` gives one option.
- `knobs set <file> <key> <value> --json` validates the value against the
  option's type and choices, writes it in place (or adds the line where it
  belongs), and saves atomically. The first save backs the file up under
  ~/.local/state/knobs/backups.
- `knobs unset <file> <key> --json` removes the option's line so the program
  default applies.

Every command exits 0 on success and 1 with the error on stderr. Values are
written without quotes; knobs adds the quoting the format needs.
)";

QTextStream &out() { static QTextStream s(stdout); return s; }
QTextStream &err() { static QTextStream s(stderr); return s; }

int fail(const QString &message, bool json) {
    if (json)
        err() << QJsonDocument(QJsonObject{{"ok", false}, {"error", message}}).toJson(QJsonDocument::Compact) << "\n";
    else
        err() << "knobs: " << message << "\n";
    return 1;
}

QJsonObject optionJson(const Option &o) {
    return {
        {"key", o.key}, {"name", o.name}, {"section", o.section}, {"type", o.type},
        {"description", o.description}, {"default", o.defaultValue},
        {"choices", QJsonArray::fromStringList(o.choices)}, {"min", o.minimum}, {"max", o.maximum},
        {"set", o.isSet()}, {"value", o.isSet() ? o.value() : QString()}, {"line", o.line},
    };
}

// Opens the file and waits for its explanation, from the cache or Claude.
bool load(Backend &backend, const QString &path, bool refresh, bool json, int *code) {
    if (!backend.openFile(path)) {
        *code = fail(backend.error(), json);
        return false;
    }
    if (refresh && !backend.busy())
        backend.reanalyze();
    if (backend.busy()) {
        if (!json)
            QObject::connect(&backend, &Backend::statusChanged, [&backend] {
                if (!backend.status().isEmpty()) err() << "… " << backend.status() << "\n" << Qt::flush;
            });
        QEventLoop loop;
        QObject::connect(&backend, &Backend::analyzed, &loop, &QEventLoop::quit);
        QObject::connect(&backend, &Backend::errorChanged, &loop, [&] { if (!backend.error().isEmpty()) loop.quit(); });
        loop.exec();
    }
    if (!backend.error().isEmpty() || !backend.hasOptions()) {
        *code = fail(backend.error().isEmpty() ? QStringLiteral("No settings found.") : backend.error(), json);
        return false;
    }
    return true;
}

int explain(Backend &backend, bool json) {
    const ConfigDocument &doc = backend.document();
    if (json) {
        QJsonArray options, docs;
        for (const auto &o : doc.options) options.append(optionJson(o));
        for (const auto &d : doc.docs) docs.append(QJsonObject{{"title", d.title}, {"url", d.url}});
        out() << QJsonDocument(QJsonObject{
                     {"ok", true}, {"path", backend.path()}, {"program", doc.program}, {"format", doc.format},
                     {"summary", doc.summary}, {"docs", docs}, {"options", options}})
                     .toJson(QJsonDocument::Indented);
        return 0;
    }
    out() << doc.program << " — " << doc.summary << "\n";
    for (const auto &d : doc.docs) out() << "  " << d.url << "\n";
    for (const auto &section : doc.sections()) {
        out() << "\n" << section << "\n";
        for (const auto &o : doc.options) {
            if (o.section != section) continue;
            out() << (o.isSet() ? "  * " : "    ") << o.key << " = "
                  << (o.isSet() ? o.value() : o.defaultValue);
            if (o.isSet()) out() << "   (line " << o.line << ", default " << o.defaultValue << ")";
            if (!o.choices.isEmpty()) out() << "   [" << o.choices.join(" | ") << "]";
            out() << "\n      " << o.description << "\n";
        }
    }
    out() << "\n* set in the file\n";
    return 0;
}

int installSkill(bool json) {
    const QString directory = QDir::homePath() + "/.claude/skills/knobs";
    QDir().mkpath(directory);
    QString problem;
    if (!Store::writeFile(directory + "/SKILL.md", Skill, &problem))
        return fail(problem, json);
    if (json)
        out() << QJsonDocument(QJsonObject{{"ok", true}, {"path", directory + "/SKILL.md"}}).toJson(QJsonDocument::Compact) << "\n";
    else
        out() << "Installed " << directory << "/SKILL.md\n";
    return 0;
}

} // namespace

namespace Cli {

bool isCommand(const QStringList &arguments) {
    if (arguments.size() < 2) return false;
    static const QStringList commands{"explain", "get", "set", "unset", "skill", "help", "--help", "-h", "--version"};
    return commands.contains(arguments.at(1));
}

int run(const QStringList &all, const QString &language) {
    QStringList args = all.mid(1);
    const bool json = args.removeAll("--json") > 0;
    const bool refresh = args.removeAll("--refresh") > 0;
    const QString command = args.value(0);

    if (command == "help" || command == "--help" || command == "-h") {
        out() << Usage;
        return 0;
    }
    if (command == "--version") {
        out() << "knobs " << QCoreApplication::applicationVersion() << "\n";
        return 0;
    }
    if (command == "skill")
        return args.value(1) == "install" ? installSkill(json) : fail("Usage: knobs skill install", json);

    const int needed = command == "explain" ? 2 : command == "set" ? 4 : 3;
    if (args.size() != needed) {
        err() << Usage;
        return 1;
    }

    Backend backend;
    backend.setLanguage(language);
    int code = 0;
    if (!load(backend, args.at(1), refresh, json, &code))
        return code;
    if (command == "explain")
        return explain(backend, json);

    const int index = backend.document().indexOf(args.at(2));
    if (index < 0)
        return fail(QString("%1 has no setting called %2. `knobs explain %3` lists them.")
                        .arg(backend.program(), args.at(2), args.at(1)), json);

    if (command == "get") {
        const Option &o = backend.document().options.at(index);
        if (json) out() << QJsonDocument(optionJson(o)).toJson(QJsonDocument::Compact) << "\n";
        else out() << (o.isSet() ? o.value() : o.defaultValue) << "\n";
        return 0;
    }

    const QString problem = command == "set" ? backend.setValue(index, args.at(3)) : backend.unset(index);
    if (!problem.isEmpty())
        return fail(problem, json);
    QString saved;
    QObject::connect(&backend, &Backend::message, [&saved](const QString &text) { saved = text; });
    if (!backend.save())
        return fail(backend.error(), json);
    if (json)
        out() << QJsonDocument(QJsonObject{{"ok", true}, {"option", optionJson(backend.document().options.at(index))},
                                           {"message", saved}}).toJson(QJsonDocument::Compact) << "\n";
    else
        out() << saved << "\n";
    return 0;
}

} // namespace Cli
