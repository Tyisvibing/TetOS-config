#pragma once

#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVector>

// One setting the program understands, whether or not the file sets it.
struct Option {
    QString key;          // Unique id, e.g. "general:gaps_in" or "font.size".
    QString name;         // The key exactly as it is written on its line, e.g. "gaps_in".
    QString section;      // Human-readable group, e.g. "General".
    QString type;         // bool, int, float, enum, color, string, or list.
    QString description;  // What it does, from the documentation.
    QString defaultValue; // The program's default, as it would be written.
    QStringList choices;  // For enums.
    QString minimum, maximum;
    QString quote;        // Quote character the value is wrapped in when written, or empty.
    QString insert;       // Template for a new line, with {value} where the value goes.
    QString raw;          // The value exactly as written in the file, quotes included.
    int line = 0;         // 1-based line in the file, 0 when unset.
    int insertAfter = 0;  // Where a new line for this option goes when it isn't set yet.

    bool isSet() const { return line > 0; }
    QString value() const;
};

struct DocLink {
    QString title;
    QString url;
};

// The file's text together with what the documentation says about it. Every
// edit changes the text directly and keeps the line numbers of every option
// in step, so the file is only ever changed on the lines the user touched.
class ConfigDocument {
public:
    QString path;
    QString text;
    QString program;
    QString format;
    QString summary;
    QString boolTrue = "true";
    QString boolFalse = "false";
    QString analyzedAt;
    QVector<DocLink> docs;
    QVector<Option> options;

    // Builds a document from an analysis (the JSON Claude returns, or a cached
    // copy of it) and the file's current text. Line numbers in the analysis are
    // checked against the text and searched for when they have drifted.
    static ConfigDocument fromAnalysis(const QJsonObject &analysis, const QString &text, QString *error = nullptr);
    QJsonObject toAnalysis() const;

    int indexOf(const QString &key) const;
    QStringList sections() const;

    bool setValue(int index, const QString &value, QString *error = nullptr);
    bool unset(int index, QString *error = nullptr);

    // Checks a value against the option's type before anything is written.
    QString validate(int index, const QString &value) const;

    // The JSON Schema Claude's answer must match.
    static QJsonObject schema();

    // A line's text with a trailing comment removed, and the value that follows
    // a key on it ("gaps_in = 5 # px" gives "5").
    static QString valueAfterName(const QString &line, const QString &name);

private:
    QStringList lines() const;
    void setLines(const QStringList &lines);
    void relocate(Option &option, const QStringList &lines) const;
    void shift(int fromLine, int delta);
};
