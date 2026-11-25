#pragma once

#include <QObject>
#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <QVector>

#include "analyzer.h"
#include "configdocument.h"
#include "optionsmodel.h"

class FilePicker;

// The open config file, what its documentation says, and the edits made to it.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hasFile READ hasFile NOTIFY fileChanged)
    Q_PROPERTY(bool hasOptions READ hasOptions NOTIFY documentChanged)
    Q_PROPERTY(QString path READ path NOTIFY fileChanged)
    Q_PROPERTY(QString fileName READ fileName NOTIFY fileChanged)
    Q_PROPERTY(QString program READ program NOTIFY documentChanged)
    Q_PROPERTY(QString format READ format NOTIFY documentChanged)
    Q_PROPERTY(QString summary READ summary NOTIFY documentChanged)
    Q_PROPERTY(QVariantList docs READ docs NOTIFY documentChanged)
    Q_PROPERTY(QVariantList sections READ sections NOTIFY documentChanged)
    Q_PROPERTY(int optionCount READ optionCount NOTIFY documentChanged)
    Q_PROPERTY(int setCount READ setCount NOTIFY documentChanged)
    Q_PROPERTY(QStringList lines READ lines NOTIFY documentChanged)
    Q_PROPERTY(bool stale READ stale NOTIFY documentChanged)
    Q_PROPERTY(QString analyzedAt READ analyzedAt NOTIFY documentChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(bool dirty READ dirty NOTIFY documentChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY documentChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY documentChanged)
    Q_PROPERTY(QString boolTrue READ boolTrue NOTIFY documentChanged)
    Q_PROPERTY(QString boolFalse READ boolFalse NOTIFY documentChanged)
    Q_PROPERTY(QStringList recentFiles READ recentFiles NOTIFY recentFilesChanged)
    Q_PROPERTY(QStringList suggestedFiles READ suggestedFiles CONSTANT)
    Q_PROPERTY(QString home READ home CONSTANT)
    Q_PROPERTY(OptionsFilter *options READ options CONSTANT)

public:
    explicit Backend(FilePicker *picker = nullptr, QObject *parent = nullptr);

    bool hasFile() const { return !m_path.isEmpty(); }
    bool hasOptions() const { return !m_document.options.isEmpty(); }
    QString path() const { return m_path; }
    QString fileName() const;
    QString program() const { return m_document.program; }
    QString format() const { return m_document.format; }
    QString summary() const { return m_document.summary; }
    QVariantList docs() const;
    QVariantList sections() const;
    int optionCount() const { return int(m_document.options.size()); }
    int setCount() const;
    QStringList lines() const { return m_document.text.split('\n'); }
    bool stale() const { return m_stale; }
    QString analyzedAt() const { return m_document.analyzedAt; }
    bool busy() const { return m_analyzer.isRunning(); }
    QString status() const { return m_status; }
    QString error() const { return m_error; }
    bool dirty() const { return hasFile() && m_document.text != m_savedText; }
    bool canUndo() const { return !m_undo.isEmpty(); }
    bool canRedo() const { return !m_redo.isEmpty(); }
    QString boolTrue() const { return m_document.boolTrue; }
    QString boolFalse() const { return m_document.boolFalse; }
    QStringList recentFiles() const { return m_recent; }
    OptionsFilter *options() { return &m_filter; }
    // Common config files that exist on this computer, for the start screen.
    QStringList suggestedFiles() const;
    QString home() const;
    const ConfigDocument &document() const { return m_document; }

    void setLanguage(const QString &language) { m_language = language; }

    Q_INVOKABLE bool openFile(const QString &path);
    Q_INVOKABLE void pickFile();
    Q_INVOKABLE void reanalyze();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void closeFile();
    // Each returns an empty string on success, or what went wrong.
    Q_INVOKABLE QString setValue(int option, const QString &value);
    Q_INVOKABLE QString unset(int option);
    Q_INVOKABLE bool save();
    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();
    Q_INVOKABLE void clearError();
    Q_INVOKABLE int optionLine(int option) const;

    // A QML color for a value as configs write them ("#88c0d0",
    // "rgba(33ccffee)", "0xff1e1e2e", "rgb(255, 0, 0)"), or "" if it isn't one.
    Q_INVOKABLE static QString previewColor(const QString &value);

signals:
    void fileChanged();
    void documentChanged();
    void busyChanged();
    void statusChanged();
    void errorChanged();
    void recentFilesChanged();
    void message(const QString &text);
    void analyzed();

private:
    void setError(const QString &error);
    void setStatus(const QString &status);
    void loadDocument(const ConfigDocument &document);
    void edited();
    void startAnalysis();

    FilePicker *m_picker;
    Analyzer m_analyzer;
    ConfigDocument m_document;
    OptionsModel m_model;
    OptionsFilter m_filter;
    QVector<ConfigDocument> m_undo, m_redo;
    QSet<QString> m_backedUp;
    QStringList m_recent;
    QString m_path, m_savedText, m_status, m_error, m_language = "en";
    bool m_stale = false;
};
