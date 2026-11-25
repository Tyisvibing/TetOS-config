#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QtTest>

#include "analyzer.h"
#include "backend.h"
#include "configdocument.h"
#include "store.h"
#include "theme.h"
#include "translator.h"

namespace {

void write(const QString &path, const QByteArray &contents) {
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(contents);
}

QByteArray read(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

const char *Conf = "general {\n"
                   "    gaps_in = 5 # inner\n"
                   "    border_size = 2\n"
                   "}\n"
                   "\n"
                   "decoration {\n"
                   "    rounding = 0\n"
                   "}\n";

QJsonObject option(const QString &key, const QString &name, const QString &type, const QString &value, int line,
                   const QString &insert = {}, int insertAfter = 0) {
    return {{"key", key}, {"name", name}, {"section", key.section(':', 0, 0)}, {"type", type},
            {"description", "About " + name}, {"default", "1"}, {"value", value}, {"line", line},
            {"insert", insert}, {"insertAfter", insertAfter}};
}

QJsonObject analysis() {
    QJsonObject layout = option("general:layout", "layout", "enum", "", 0, "    layout = {value}", 3);
    layout.insert("choices", QJsonArray{"dwindle", "master"});
    QJsonObject gaps = option("general:gaps_in", "gaps_in", "int", "5", 2);
    gaps.insert("min", "0");
    return {
        {"program", "Hyprland"}, {"format", "hyprlang"}, {"summary", "Window manager"},
        {"boolTrue", "true"}, {"boolFalse", "false"},
        {"docs", QJsonArray{QJsonObject{{"title", "Wiki"}, {"url", "https://wiki.hypr.land"}}}},
        {"options", QJsonArray{
            gaps,
            option("general:border_size", "border_size", "int", "2", 9), // Wrong line on purpose.
            layout,
            option("decoration:rounding", "rounding", "int", "0", 7),
            option("decoration:blur:enabled", "enabled", "bool", "", 0, "    blur:enabled = {value}", 7),
            option("decoration:active_opacity", "active_opacity", "float", "", 0, "    active_opacity = {value}", 7),
        }},
    };
}

// A stand-in for `claude -p` that prints what the real one streams.
QString fakeClaude(const QString &directory, const QJsonObject &structured) {
    const QString path = directory + "/claude";
    const QJsonObject tool{{"type", "assistant"}, {"message", QJsonObject{{"content", QJsonArray{
        QJsonObject{{"type", "tool_use"}, {"name", "WebSearch"}, {"input", QJsonObject{{"query", "hyprland options"}}}}}}}}};
    const QJsonObject result{{"type", "result"}, {"subtype", "success"}, {"is_error", false},
                             {"structured_output", structured}};
    write(directory + "/out.jsonl", QJsonDocument(tool).toJson(QJsonDocument::Compact) + "\n"
                                    + QJsonDocument(result).toJson(QJsonDocument::Compact) + "\n");
    write(path, "#!/bin/sh\ncat > '" + directory.toUtf8() + "/prompt.txt'\nprintf '%s' \"$*\" > '"
                + directory.toUtf8() + "/args.txt'\ncat '" + directory.toUtf8() + "/out.jsonl'\n");
    QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    return path;
}

} // namespace

class KnobsTests : public QObject {
    Q_OBJECT

private slots:
    void initTestCase() { QStandardPaths::setTestModeEnabled(true); }

    void findsTheValueAfterAName() {
        QCOMPARE(ConfigDocument::valueAfterName("    gaps_in = 5 # inner", "gaps_in"), QString("5"));
        QCOMPARE(ConfigDocument::valueAfterName("font_size 11.5", "font_size"), QString("11.5"));
        QCOMPARE(ConfigDocument::valueAfterName("color = #ff0000", "color"), QString("#ff0000"));
        QCOMPARE(ConfigDocument::valueAfterName("title = \"a # b\" ; note", "title"), QString("\"a # b\""));
        QCOMPARE(ConfigDocument::valueAfterName("key: value", "key"), QString("value"));
        QCOMPARE(ConfigDocument::valueAfterName("  \"font-size\": 12,", "font-size"), QString("12"));
        QCOMPARE(ConfigDocument::valueAfterName("    gaps_in = 5, -- px", "gaps_in"), QString("5"));
    }

    void relocatesDriftedLines() {
        const auto doc = ConfigDocument::fromAnalysis(analysis(), Conf);
        QCOMPARE(doc.options.size(), 6);
        QCOMPARE(doc.options.at(0).line, 2);
        QCOMPARE(doc.options.at(0).value(), QString("5"));
        // Said line 9, but it is on line 3.
        QCOMPARE(doc.options.at(1).line, 3);
        QCOMPARE(doc.options.at(1).value(), QString("2"));
        QVERIFY(!doc.options.at(2).isSet());
        QCOMPARE(doc.sections(), QStringList({"general", "decoration"}));
    }

    void changesOnlyTheValue() {
        auto doc = ConfigDocument::fromAnalysis(analysis(), Conf);
        QVERIFY(doc.setValue(0, "10"));
        QVERIFY(doc.text.contains("    gaps_in = 10 # inner\n"));
        QCOMPARE(doc.text.size(), QString(Conf).size() + 1);
    }

    void insertsInsideTheSectionAndRenumbers() {
        auto doc = ConfigDocument::fromAnalysis(analysis(), Conf);
        QVERIFY(doc.setValue(2, "master"));
        QCOMPARE(doc.text.split('\n').at(3), QString("    layout = master"));
        QCOMPARE(doc.options.at(2).line, 4);
        QCOMPARE(doc.options.at(3).line, 8); // rounding moved down.
        QCOMPARE(doc.options.at(4).insertAfter, 8);

        // Two inserts after the same line keep their order inside the block.
        QVERIFY(doc.setValue(4, "true"));
        QVERIFY(doc.setValue(5, "0.9"));
        const QStringList lines = doc.text.split('\n');
        QCOMPARE(lines.at(7), QString("    rounding = 0"));
        QCOMPARE(lines.at(8), QString("    blur:enabled = true"));
        QCOMPARE(lines.at(9), QString("    active_opacity = 0.9"));
        QCOMPARE(lines.at(10), QString("}"));
        QVERIFY(doc.text.endsWith("}\n"));
    }

    void unsetRemovesTheLine() {
        auto doc = ConfigDocument::fromAnalysis(analysis(), Conf);
        QVERIFY(doc.unset(0));
        QVERIFY(!doc.text.contains("gaps_in"));
        QCOMPARE(doc.options.at(1).line, 2);
        QCOMPARE(doc.options.at(3).line, 6);
        // Setting it again puts it back where it was.
        QVERIFY(doc.setValue(0, "7"));
        QCOMPARE(doc.text.split('\n').at(1), QString("gaps_in = 7"));
        QVERIFY(!doc.unset(2));
    }

    void validatesValues() {
        const auto doc = ConfigDocument::fromAnalysis(analysis(), Conf);
        QVERIFY(!doc.validate(0, "five").isEmpty());
        QVERIFY(!doc.validate(0, "-1").isEmpty()); // below min 0.
        QVERIFY(doc.validate(0, "8").isEmpty());
        QVERIFY(!doc.validate(2, "spiral").isEmpty());
        QVERIFY(!doc.validate(4, "yes").isEmpty());
        QVERIFY(!doc.validate(5, "0,9x").isEmpty());
        QVERIFY(!doc.validate(0, "1\n2").isEmpty());
    }

    void editsQuotedKeys() {
        QJsonObject a = analysis();
        a.insert("options", QJsonArray{option("font.size", "font-size", "int", "", 2)});
        auto doc = ConfigDocument::fromAnalysis(a, "{\n  \"font-size\": 12,\n}\n");
        QCOMPARE(doc.options.at(0).value(), QString("12"));
        QVERIFY(doc.setValue(0, "14"));
        QCOMPARE(doc.text, QString("{\n  \"font-size\": 14,\n}\n"));
    }

    void quotesWhatTheFormatQuotes() {
        QJsonObject a = analysis();
        QJsonObject font = option("font.family", "family", "string", "\"JetBrains Mono\"", 1);
        font.insert("quote", "\"");
        a.insert("options", QJsonArray{font});
        auto doc = ConfigDocument::fromAnalysis(a, "family = \"JetBrains Mono\"\n");
        QCOMPARE(doc.options.at(0).value(), QString("JetBrains Mono"));
        QVERIFY(doc.setValue(0, "Iosevka"));
        QCOMPARE(doc.text, QString("family = \"Iosevka\"\n"));
        QVERIFY(!doc.validate(0, "a\"b").isEmpty());
    }

    void roundTripsThroughTheCache() {
        const auto doc = ConfigDocument::fromAnalysis(analysis(), Conf);
        const auto again = ConfigDocument::fromAnalysis(doc.toAnalysis(), Conf);
        QCOMPARE(again.options.size(), doc.options.size());
        QCOMPARE(again.options.at(1).line, 3);
        QCOMPARE(again.docs.size(), 1);
        QCOMPARE(again.program, QString("Hyprland"));
    }

    void previewsColors() {
        QCOMPARE(Backend::previewColor("#ff0000"), QString("#ffff0000"));
        QCOMPARE(Backend::previewColor("rgba(33ccffee) rgba(00ff99ee) 45deg"), QString("#ee33ccff"));
        QCOMPARE(Backend::previewColor("0x801e1e2e"), QString("#801e1e2e"));
        QCOMPARE(Backend::previewColor("rgb(255, 0, 0)"), QString("#ffff0000"));
        QCOMPARE(Backend::previewColor("\"#00ff0080\""), QString("#8000ff00"));
        QCOMPARE(Backend::previewColor("12"), QString());
    }

    void describesWhatClaudeIsDoing() {
        const QJsonObject fetch{{"type", "assistant"}, {"message", QJsonObject{{"content", QJsonArray{
            QJsonObject{{"type", "tool_use"}, {"name", "WebFetch"}, {"input", QJsonObject{{"url", "https://wiki.hypr.land/x"}}}}}}}}};
        QVERIFY(Analyzer::describe(fetch).contains("wiki.hypr.land"));
        QVERIFY(Analyzer::describe(QJsonObject{{"type", "system"}}).isEmpty());
        QVERIFY(Analyzer::prompt("/x.conf", "a = 1", "da").contains("    1| a = 1"));
        QVERIFY(Analyzer::prompt("/x.conf", "a = 1", "da").contains("dansk"));
    }

    void analyzesEditsAndSaves() {
        QTemporaryDir dir;
        qputenv("KNOBS_CLAUDE", fakeClaude(dir.path(), analysis()).toUtf8());
        const QString path = dir.path() + "/hyprland.conf";
        write(path, Conf);

        Backend backend;
        QSignalSpy analyzed(&backend, &Backend::analyzed);
        QVERIFY(backend.openFile(path));
        QVERIFY(backend.busy());
        QVERIFY(analyzed.wait(5000));
        QVERIFY(backend.error().isEmpty());
        QCOMPARE(backend.optionCount(), 6);
        QCOMPARE(backend.setCount(), 3);
        QVERIFY(read(dir.path() + "/prompt.txt").contains("gaps_in = 5"));
        QVERIFY(read(dir.path() + "/args.txt").contains("--json-schema"));

        QCOMPARE(backend.setValue(0, "nope").isEmpty(), false);
        QVERIFY(!backend.dirty());
        QCOMPARE(backend.setValue(0, "12"), QString());
        QVERIFY(backend.dirty());
        QCOMPARE(read(path), QByteArray(Conf)); // Nothing written yet.
        backend.undo();
        QVERIFY(!backend.dirty());
        backend.redo();
        QVERIFY(backend.save());
        QVERIFY(read(path).contains("gaps_in = 12 # inner"));
        QVERIFY(!backend.dirty());

        // The first save kept the original.
        const QString backups = QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + "/knobs/backups";
        bool found = false;
        for (const auto &name : QDir(backups).entryList(QDir::Files))
            found |= name.startsWith("hyprland.conf.") && read(backups + "/" + name) == Conf;
        QVERIFY(found);

        // Reopening uses the cache, with the saved lines, and needs no Claude.
        qputenv("KNOBS_CLAUDE", "/nonexistent");
        Backend again;
        QVERIFY(again.openFile(path));
        QVERIFY(!again.busy());
        QVERIFY(!again.stale());
        QCOMPARE(again.document().options.at(0).value(), QString("12"));
        qunsetenv("KNOBS_CLAUDE");
    }

    void refusesToOverwriteOutsideChanges() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/hyprland.conf";
        write(path, Conf);
        Store::saveAnalysis(path, Store::hashOf(Conf), analysis());

        Backend backend;
        QVERIFY(backend.openFile(path));
        QVERIFY(!backend.busy());
        QCOMPARE(backend.setValue(3, "8"), QString());
        write(path, QByteArray(Conf) + "# edited elsewhere\n");
        QVERIFY(!backend.save());
        QVERIFY(!backend.error().isEmpty());
        QVERIFY(read(path).endsWith("# edited elsewhere\n"));
    }

    void staleCacheStillFindsSettings() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/hyprland.conf";
        write(path, Conf);
        Store::saveAnalysis(path, Store::hashOf(Conf), analysis());
        write(path, "# a new first line\n" + QByteArray(Conf).replace("border_size = 2", "border_size = 4"));

        Backend backend;
        QVERIFY(backend.openFile(path));
        QVERIFY(backend.stale());
        QCOMPARE(backend.document().options.at(1).line, 4);
        QCOMPARE(backend.document().options.at(1).value(), QString("4"));
    }

    void reportsAMissingClaude() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/x.conf";
        write(path, "a = 1\n");
        qputenv("KNOBS_CLAUDE", (dir.path() + "/missing").toUtf8());
        Backend backend;
        QSignalSpy errors(&backend, &Backend::errorChanged);
        backend.openFile(path);
        QTRY_VERIFY(!backend.error().isEmpty());
        QVERIFY(!backend.busy());
        qunsetenv("KNOBS_CLAUDE");
    }

    void refusesBinaryFiles() {
        QTemporaryDir dir;
        write(dir.path() + "/blob", QByteArray("a\0b", 3));
        Backend backend;
        QVERIFY(!backend.openFile(dir.path() + "/blob"));
        QVERIFY(!backend.hasFile());
    }

    void filtersTheList() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/hyprland.conf";
        write(path, Conf);
        Store::saveAnalysis(path, Store::hashOf(Conf), analysis());
        Backend backend;
        QVERIFY(backend.openFile(path));
        auto *filter = backend.options();
        QCOMPARE(filter->count(), 6);
        filter->setSection("decoration");
        QCOMPARE(filter->count(), 3);
        filter->setSearch("gaps");
        QCOMPARE(filter->count(), 1); // Search spans every section.
        QCOMPARE(filter->optionAt(0), 0);
        filter->setSearch("");
        filter->setSetOnly(true);
        QCOMPARE(filter->count(), 3);
    }

    void themeFallsBack() {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QString("black"));
    }

    void themeReadsAccent() {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        write(dir.path() + "/theme/colors.toml", "accent = \"#112233\"\n");
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#112233"));
        QCOMPARE(theme.accentForeground(), QString("white"));
    }

    void themeFollowsHyprlandRounding() {
        QTemporaryDir dir;
        const QString response = dir.filePath("response.json"), command = dir.filePath("hyprctl");
        write(command, "#!/bin/sh\ncat '" + response.toUtf8() + "'\n");
        QVERIFY(QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        write(response, "{\"int\":0}");
        Theme theme(dir.path(), nullptr, command);
        QCOMPARE(theme.radius(), 0);
        write(response, "{\"int\":6}");
        QTRY_COMPARE(theme.radius(), 6);
    }

    void translatorFallsBackToEnglish() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Save").isNull());
    }

    void translatorFollowsTheLanguageFile() {
        QTemporaryDir dir;
        write(dir.path() + "/language", "pt-BR\n");
        write(dir.path() + "/pt.json", R"({"Save": "Guardar", "Open": "Abrir"})");
        write(dir.path() + "/pt-BR.json", R"({"Save": "Salvar"})");
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("pt-BR"));
        QCOMPARE(translator.translate("Main", "Save"), QString("Salvar"));
        QCOMPARE(translator.translate("Main", "Open"), QString("Abrir"));
        QVERIFY(translator.translate("Main", "Quit").isNull());
    }

    void translatorPicksPluralForms() {
        QTemporaryDir dir;
        write(dir.path() + "/language", "ru\n");
        write(dir.path() + "/en.json", R"({"%n clips": {"one": "%n clip", "other": "%n clips"}})");
        write(dir.path() + "/ru.json", R"({"%n clips": {"one": "%n клип", "few": "%n клипа", "many": "%n клипов", "other": "%n клипа"}})");
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 21), QString("%n клип"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 25), QString("%n клипов"));
        QCOMPARE(Translator::pluralCategory("ar", 11), QString("many"));
    }

    void shipsCatalogsForEveryString() {
        // Every catalog compiled in parses, so a broken file shows up here.
        for (const auto &code : {"en", "da", "de", "es"}) {
            QJsonParseError error;
            QJsonDocument::fromJson(read(QString(":/i18n/%1.json").arg(code)), &error);
            QCOMPARE(error.error, QJsonParseError::NoError);
        }
    }
};

QTEST_MAIN(KnobsTests)
#include "knobs_tests.moc"
