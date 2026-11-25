#include "configdocument.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QRegularExpression>
#include <QSet>
#include <cmath>

namespace {

QString tr(const char *text) { return QCoreApplication::translate("ConfigDocument", text); }

QString asText(const QJsonValue &value) {
    if (value.isString()) return value.toString();
    if (value.isBool()) return value.toBool() ? "true" : "false";
    if (value.isDouble()) {
        const double d = value.toDouble();
        return d == std::floor(d) && std::abs(d) < 1e15 ? QString::number(qint64(d)) : QString::number(d);
    }
    return {};
}

bool isComment(const QString &trimmed) {
    return trimmed.startsWith('#') || trimmed.startsWith(';') || trimmed.startsWith("//");
}

// A line sets `name` when, once indented whitespace is skipped, it starts with
// the name followed by a separator, rather than merely mentioning it.
bool lineSets(const QString &line, const QString &name) {
    const QString trimmed = line.trimmed();
    if (name.isEmpty() || isComment(trimmed))
        return false;
    // JSON and some Lua tables write the key in quotes: "font-size": 12,
    int length = name.size();
    if (trimmed.startsWith('"' + name + '"') || trimmed.startsWith('\'' + name + '\''))
        length += 2;
    else if (!trimmed.startsWith(name))
        return false;
    if (trimmed.size() == length)
        return true;
    const QChar next = trimmed.at(length);
    return next.isSpace() || next == '=' || next == ':';
}

// JSON, JSONC and Lua tables end entries with a comma that isn't the value's.
QString withoutComma(const QString &value) {
    return value.endsWith(',') ? value.chopped(1).trimmed() : value;
}

int realLineCount(const QStringList &lines) {
    return !lines.isEmpty() && lines.last().isEmpty() ? lines.size() - 1 : lines.size();
}

} // namespace

QString Option::value() const {
    if (!quote.isEmpty() && raw.size() >= 2 * quote.size() && raw.startsWith(quote) && raw.endsWith(quote))
        return raw.mid(quote.size(), raw.size() - 2 * quote.size());
    return raw;
}

QString ConfigDocument::valueAfterName(const QString &line, const QString &name) {
    int position = line.indexOf(name);
    position = position < 0 ? 0 : position + name.size();
    QString rest = line.mid(position);
    if (position > name.size() && (rest.startsWith('"') || rest.startsWith('\''))
        && line.at(position - name.size() - 1) == rest.at(0))
        rest = rest.mid(1); // The closing quote of a quoted key.

    int start = 0;
    while (start < rest.size() && rest.at(start).isSpace()) ++start;
    if (start < rest.size() && (rest.at(start) == '=' || rest.at(start) == ':')) ++start;
    while (start < rest.size() && rest.at(start).isSpace()) ++start;
    rest = rest.mid(start);

    // A comment starts at whitespace followed by # or ;, outside quotes. A
    // value that itself starts with # (a hex color) is not a comment.
    QChar inQuote;
    for (int i = 0; i < rest.size(); ++i) {
        const QChar c = rest.at(i);
        if (!inQuote.isNull()) {
            if (c == inQuote) inQuote = QChar();
            continue;
        }
        if (c == '"' || c == '\'') {
            inQuote = c;
            continue;
        }
        if (i > 0 && (c == '#' || c == ';' || (c == '-' && rest.mid(i, 2) == "--")) && rest.at(i - 1).isSpace())
            return withoutComma(rest.left(i).trimmed());
    }
    return withoutComma(rest.trimmed());
}

QStringList ConfigDocument::lines() const { return text.split('\n'); }

void ConfigDocument::setLines(const QStringList &lines) { text = lines.join('\n'); }

void ConfigDocument::relocate(Option &option, const QStringList &lines) const {
    if (option.line > 0 && option.line <= lines.size() && lineSets(lines.at(option.line - 1), option.name)) {
        const QString &line = lines.at(option.line - 1);
        if (option.raw.isEmpty() || !line.contains(option.raw))
            option.raw = valueAfterName(line, option.name);
        return;
    }

    // The analysis was off by a few lines, or the file changed since; take the
    // matching line nearest to where it was, since names like "enabled" repeat
    // across sections.
    int best = 0;
    for (int i = 0; i < lines.size(); ++i) {
        if (!lineSets(lines.at(i), option.name))
            continue;
        if (best == 0 || std::abs(i + 1 - option.line) < std::abs(best - option.line))
            best = i + 1;
    }
    if (option.line <= 0 && option.raw.isEmpty()) {
        // The analysis said it is unset; only trust a match that is unique.
        int matches = 0;
        for (const auto &line : lines) matches += lineSets(line, option.name);
        if (matches != 1 || option.key.contains(':') || option.key.contains('.'))
            best = 0;
    }
    option.line = best;
    option.raw = best ? valueAfterName(lines.at(best - 1), option.name) : QString();
}

ConfigDocument ConfigDocument::fromAnalysis(const QJsonObject &analysis, const QString &text, QString *error) {
    ConfigDocument doc;
    doc.text = text;
    doc.program = analysis.value("program").toString();
    doc.format = analysis.value("format").toString();
    doc.summary = analysis.value("summary").toString();
    doc.analyzedAt = analysis.value("analyzedAt").toString();
    if (!analysis.value("boolTrue").toString().isEmpty()) doc.boolTrue = analysis.value("boolTrue").toString();
    if (!analysis.value("boolFalse").toString().isEmpty()) doc.boolFalse = analysis.value("boolFalse").toString();

    for (const auto &value : analysis.value("docs").toArray()) {
        const auto object = value.toObject();
        if (!object.value("url").toString().isEmpty())
            doc.docs.append({object.value("title").toString(), object.value("url").toString()});
    }

    const QStringList lines = doc.lines();
    QSet<QString> seen;
    for (const auto &value : analysis.value("options").toArray()) {
        const auto o = value.toObject();
        Option option;
        option.key = o.value("key").toString().trimmed();
        if (option.key.isEmpty() || seen.contains(option.key))
            continue;
        seen.insert(option.key);
        option.name = o.value("name").toString().trimmed();
        if (option.name.isEmpty())
            option.name = option.key.section(QRegularExpression("[:.]"), -1);
        option.section = o.value("section").toString().trimmed();
        option.type = o.value("type").toString("string").toLower();
        option.description = o.value("description").toString().trimmed();
        option.defaultValue = asText(o.value("default"));
        for (const auto &choice : o.value("choices").toArray())
            option.choices.append(asText(choice));
        option.minimum = asText(o.value("min"));
        option.maximum = asText(o.value("max"));
        option.quote = o.value("quote").toString();
        option.insert = o.value("insert").toString();
        option.raw = asText(o.value("value"));
        option.line = o.value("line").toInt();
        option.insertAfter = qMax(0, o.value("insertAfter").toInt());
        doc.relocate(option, lines);
        doc.options.append(option);
    }

    if (doc.options.isEmpty() && error)
        *error = tr("The analysis listed no settings for this file.");
    return doc;
}

QJsonObject ConfigDocument::toAnalysis() const {
    QJsonArray docArray;
    for (const auto &link : docs)
        docArray.append(QJsonObject{{"title", link.title}, {"url", link.url}});
    QJsonArray optionArray;
    for (const auto &o : options) {
        optionArray.append(QJsonObject{
            {"key", o.key}, {"name", o.name}, {"section", o.section}, {"type", o.type},
            {"description", o.description}, {"default", o.defaultValue},
            {"choices", QJsonArray::fromStringList(o.choices)}, {"min", o.minimum}, {"max", o.maximum},
            {"quote", o.quote}, {"insert", o.insert}, {"value", o.raw}, {"line", o.line},
            {"insertAfter", o.insertAfter},
        });
    }
    return {
        {"program", program}, {"format", format}, {"summary", summary}, {"boolTrue", boolTrue},
        {"boolFalse", boolFalse}, {"analyzedAt", analyzedAt}, {"docs", docArray}, {"options", optionArray},
    };
}

int ConfigDocument::indexOf(const QString &key) const {
    for (int i = 0; i < options.size(); ++i)
        if (options.at(i).key == key) return i;
    for (int i = 0; i < options.size(); ++i)
        if (options.at(i).name == key) return i;
    return -1;
}

QStringList ConfigDocument::sections() const {
    QStringList result;
    for (const auto &o : options)
        if (!result.contains(o.section)) result.append(o.section);
    return result;
}

QString ConfigDocument::validate(int index, const QString &value) const {
    if (index < 0 || index >= options.size())
        return tr("There is no such setting.");
    const Option &o = options.at(index);
    if (value.contains('\n'))
        return tr("A value can't span several lines.");
    if (!o.quote.isEmpty() && value.contains(o.quote))
        return tr("The value can't contain %1.").arg(o.quote);

    bool numeric = false;
    double number = 0;
    if (o.type == "bool") {
        if (value != boolTrue && value != boolFalse)
            return tr("Use %1 or %2.").arg(boolTrue, boolFalse);
    } else if (o.type == "int") {
        static const QRegularExpression integer(R"(^[+-]?\d+$)");
        if (!integer.match(value).hasMatch())
            return tr("%1 needs a whole number.").arg(o.name);
        number = value.toDouble(&numeric);
    } else if (o.type == "float") {
        number = value.toDouble(&numeric);
        if (!numeric)
            return tr("%1 needs a number.").arg(o.name);
    } else if (o.type == "enum" && !o.choices.isEmpty() && !o.choices.contains(value)) {
        return tr("%1 must be one of: %2.").arg(o.name, o.choices.join(", "));
    }
    if (numeric) {
        bool ok = false;
        const double min = o.minimum.toDouble(&ok);
        if (ok && number < min) return tr("%1 can't be below %2.").arg(o.name, o.minimum);
        const double max = o.maximum.toDouble(&ok);
        if (ok && number > max) return tr("%1 can't be above %2.").arg(o.name, o.maximum);
    }
    return {};
}

bool ConfigDocument::setValue(int index, const QString &value, QString *error) {
    const QString problem = validate(index, value);
    if (!problem.isEmpty()) {
        if (error) *error = problem;
        return false;
    }
    Option &o = options[index];
    const QString written = o.quote + value + o.quote;
    QStringList all = lines();

    if (o.isSet()) {
        QString line = all.at(o.line - 1);
        const int namePosition = line.indexOf(o.name);
        const int from = namePosition < 0 ? 0 : namePosition + o.name.size();
        const int at = o.raw.isEmpty() ? -1 : line.indexOf(o.raw, from);
        if (at >= 0) {
            line.replace(at, o.raw.size(), written);
        } else if (o.raw.isEmpty()) {
            line = line.endsWith(' ') ? line + written : line + ' ' + written;
        } else {
            if (error) *error = tr("Line %1 no longer holds %2.").arg(o.line).arg(o.name);
            return false;
        }
        all[o.line - 1] = line;
        o.raw = written;
        setLines(all);
        return true;
    }

    QString line = o.insert.contains("{value}") ? o.insert : o.name + " = {value}";
    line.replace("{value}", written);
    const int after = qBound(0, o.insertAfter, realLineCount(all));
    all.insert(after, line);
    for (auto &other : options) {
        if (other.line > after) ++other.line;
        if (other.insertAfter >= after && &other != &o) ++other.insertAfter;
    }
    o.line = after + 1;
    o.raw = written;
    setLines(all);
    return true;
}

bool ConfigDocument::unset(int index, QString *error) {
    if (index < 0 || index >= options.size() || !options.at(index).isSet()) {
        if (error) *error = tr("That setting isn't in the file.");
        return false;
    }
    const int removed = options.at(index).line;
    QStringList all = lines();
    all.removeAt(removed - 1);
    for (auto &other : options) {
        if (other.line == removed) {
            other.line = 0;
            other.raw.clear();
            other.insertAfter = removed - 1;
        } else {
            if (other.line > removed) --other.line;
            if (other.insertAfter >= removed) --other.insertAfter;
        }
    }
    setLines(all);
    return true;
}

QJsonObject ConfigDocument::schema() {
    auto str = [](const char *description) {
        return QJsonObject{{"type", "string"}, {"description", description}};
    };
    const QJsonObject option{
        {"type", "object"},
        {"properties", QJsonObject{
            {"key", str("Unique id including its section path, e.g. general:gaps_in or font.size")},
            {"name", str("The key exactly as written at the start of its line in this file format, e.g. gaps_in")},
            {"section", str("Human readable group name, e.g. General or Keyboard")},
            {"type", QJsonObject{{"type", "string"}, {"enum", QJsonArray{"bool", "int", "float", "enum", "color", "string", "list"}}}},
            {"description", str("One or two plain sentences on what it does and when you would change it")},
            {"default", str("The program's default, written as it would appear in the file without quotes; empty if none")},
            {"choices", QJsonObject{{"type", "array"}, {"items", QJsonObject{{"type", "string"}}}}},
            {"min", str("Lowest allowed number, or empty")},
            {"max", str("Highest allowed number, or empty")},
            {"quote", str("The quote character values of this option are wrapped in when written (\" or '), or empty")},
            {"value", str("If the file sets it: the value exactly as written on its line, quotes included, comment excluded. Otherwise empty")},
            {"line", QJsonObject{{"type", "integer"}, {"description", "If the file sets it: its 1-based line number. Otherwise 0"}}},
            {"insert", str("A complete line that would set this option, with {value} where the value goes and the right indentation, e.g. '    gaps_in = {value}'")},
            {"insertAfter", QJsonObject{{"type", "integer"}, {"description", "Line number the insert line belongs after (inside the right section or block; add nothing that needs a new block). 0 for the top"}}},
        }},
        {"required", QJsonArray{"key", "name", "section", "type", "description", "default", "value", "line", "insert", "insertAfter"}},
    };
    return {
        {"type", "object"},
        {"properties", QJsonObject{
            {"program", str("The program that reads this file, e.g. Hyprland")},
            {"format", str("The file format, e.g. TOML or hyprlang")},
            {"summary", str("One sentence on what this file controls")},
            {"boolTrue", str("How this format writes true, e.g. true or yes")},
            {"boolFalse", str("How this format writes false")},
            {"docs", QJsonObject{{"type", "array"}, {"items", QJsonObject{
                {"type", "object"},
                {"properties", QJsonObject{{"title", str("Title")}, {"url", str("URL or local path")}}},
                {"required", QJsonArray{"title", "url"}},
            }}}},
            {"options", QJsonObject{{"type", "array"}, {"items", option}}},
        }},
        {"required", QJsonArray{"program", "format", "summary", "boolTrue", "boolFalse", "docs", "options"}},
    };
}
