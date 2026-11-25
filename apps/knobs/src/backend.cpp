#include "backend.h"

#include "filepicker.h"
#include "store.h"

#include <QColor>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QUrl>

namespace {
constexpr qint64 MaximumFileSize = 512 * 1024;
}

Backend::Backend(FilePicker *picker, QObject *parent)
    : QObject(parent), m_picker(picker), m_model(&m_document) {
    m_filter.setSourceModel(&m_model);
    m_recent = Store::recentFiles();

    if (m_picker) {
        m_picker->setParent(this);
        connect(m_picker, &FilePicker::picked, this, [this](const QString &path) { openFile(path); });
        connect(m_picker, &FilePicker::failed, this, &Backend::setError);
    }

    connect(&m_analyzer, &Analyzer::status, this, &Backend::setStatus);
    connect(&m_analyzer, &Analyzer::failed, this, [this](const QString &error) {
        setStatus({});
        setError(error);
        emit busyChanged();
    });
    connect(&m_analyzer, &Analyzer::finished, this, [this](QJsonObject analysis) {
        analysis.insert("analyzedAt", QDateTime::currentDateTime().toString(Qt::ISODate));
        QString problem;
        const ConfigDocument document = ConfigDocument::fromAnalysis(analysis, m_document.text, &problem);
        setStatus({});
        emit busyChanged();
        if (!problem.isEmpty()) {
            setError(problem);
            return;
        }
        Store::saveAnalysis(m_path, Store::hashOf(document.text), document.toAnalysis());
        m_stale = false;
        m_undo.clear();
        m_redo.clear();
        loadDocument(document);
        emit analyzed();
    });
}

QString Backend::home() const { return QDir::homePath(); }

QStringList Backend::suggestedFiles() const {
    static const QStringList candidates{
        ".config/hypr/input.lua", ".config/hypr/looknfeel.lua", ".config/hypr/input.conf",
        ".config/hypr/looknfeel.conf", ".config/hypr/hypridle.conf", ".config/hypr/hyprlock.conf", ".config/alacritty/alacritty.toml",
        ".config/ghostty/config", ".config/kitty/kitty.conf", ".config/foot/foot.ini",
        ".config/mako/config", ".config/btop/btop.conf", ".config/starship.toml",
        ".config/walker/config.toml", ".config/fastfetch/config.jsonc", ".gitconfig",
    };
    QStringList result;
    for (const auto &relative : candidates) {
        const QString path = QDir::homePath() + "/" + relative;
        if (QFileInfo(path).isFile()) result.append(path);
    }
    return result;
}

QString Backend::fileName() const { return QFileInfo(m_path).fileName(); }

QVariantList Backend::docs() const {
    QVariantList result;
    for (const auto &link : m_document.docs)
        result.append(QVariantMap{{"title", link.title.isEmpty() ? link.url : link.title}, {"url", link.url}});
    return result;
}

QVariantList Backend::sections() const {
    QVariantList result;
    for (const auto &name : m_document.sections()) {
        int count = 0, set = 0;
        for (const auto &o : m_document.options)
            if (o.section == name) {
                ++count;
                set += o.isSet();
            }
        result.append(QVariantMap{{"name", name}, {"count", count}, {"setCount", set}});
    }
    return result;
}

int Backend::setCount() const {
    int count = 0;
    for (const auto &o : m_document.options) count += o.isSet();
    return count;
}

void Backend::setError(const QString &error) {
    if (error == m_error) return;
    m_error = error;
    emit errorChanged();
}

void Backend::clearError() { setError({}); }

void Backend::setStatus(const QString &status) {
    if (status == m_status) return;
    m_status = status;
    emit statusChanged();
}

bool Backend::openFile(const QString &input) {
    QString path = input.trimmed();
    if (path.startsWith("file://")) path = QUrl(path).toLocalFile();
    if (path.startsWith("~/")) path = QDir::homePath() + path.mid(1);
    const QFileInfo info(path);
    if (!info.exists() || !info.isFile()) {
        setError(tr("%1 doesn't exist.").arg(path));
        return false;
    }
    if (info.size() > MaximumFileSize) {
        setError(tr("%1 is too big to be a config file.").arg(info.fileName()));
        return false;
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        setError(tr("Couldn't open %1: %2").arg(path, file.errorString()));
        return false;
    }
    const QByteArray bytes = file.readAll();
    if (bytes.contains('\0')) {
        setError(tr("%1 isn't a text file.").arg(info.fileName()));
        return false;
    }

    m_analyzer.cancel();
    setError({});
    setStatus({});
    m_path = info.absoluteFilePath();
    m_savedText = QString::fromUtf8(bytes);
    m_undo.clear();
    m_redo.clear();
    Store::addRecentFile(m_path);
    m_recent = Store::recentFiles();
    emit recentFilesChanged();
    emit fileChanged();

    QJsonObject cached;
    QString hash;
    if (Store::loadAnalysis(m_path, &cached, &hash)) {
        // The file may have changed since it was explained; the cached
        // options are re-found in the new text, and R explains it afresh.
        m_stale = hash != Store::hashOf(m_savedText);
        loadDocument(ConfigDocument::fromAnalysis(cached, m_savedText));
        if (hasOptions()) return true;
    }

    ConfigDocument blank;
    blank.text = m_savedText;
    m_stale = false;
    loadDocument(blank);
    startAnalysis();
    return true;
}

void Backend::startAnalysis() {
    setError({});
    m_analyzer.start(m_path, m_document.text, m_language);
    emit busyChanged();
}

void Backend::pickFile() {
    if (!m_picker) {
        setError(tr("There is no file chooser."));
        return;
    }
    const QString folder = hasFile() ? QFileInfo(m_path).absolutePath() : QDir::homePath() + "/.config";
    m_picker->open(tr("Open a config file"), folder);
}

void Backend::reanalyze() {
    if (!hasFile() || busy()) return;
    if (dirty()) {
        setError(tr("Save or undo your changes before explaining the file again."));
        return;
    }
    startAnalysis();
}

void Backend::cancel() {
    if (!busy()) return;
    m_analyzer.cancel();
    setStatus({});
    emit busyChanged();
}

void Backend::closeFile() {
    m_analyzer.cancel();
    m_path.clear();
    m_savedText.clear();
    m_undo.clear();
    m_redo.clear();
    m_stale = false;
    setError({});
    setStatus({});
    loadDocument({});
    emit busyChanged();
    emit fileChanged();
}

void Backend::loadDocument(const ConfigDocument &document) {
    const QString path = m_path;
    m_document = document;
    m_document.path = path;
    m_model.reset();
    emit documentChanged();
}

void Backend::edited() {
    m_redo.clear();
    m_model.refresh();
    emit documentChanged();
}

QString Backend::setValue(int option, const QString &value) {
    if (option < 0 || option >= m_document.options.size()) return tr("There is no such setting.");
    const Option &o = m_document.options.at(option);
    if (o.isSet() && o.value() == value) return {};
    ConfigDocument before = m_document;
    QString problem;
    if (!m_document.setValue(option, value, &problem)) {
        m_model.refresh();
        return problem;
    }
    m_undo.append(before);
    edited();
    return {};
}

QString Backend::unset(int option) {
    ConfigDocument before = m_document;
    QString problem;
    if (!m_document.unset(option, &problem)) return problem;
    m_undo.append(before);
    edited();
    return {};
}

void Backend::undo() {
    if (m_undo.isEmpty()) return;
    m_redo.append(m_document);
    m_document = m_undo.takeLast();
    m_model.refresh();
    emit documentChanged();
}

void Backend::redo() {
    if (m_redo.isEmpty()) return;
    m_undo.append(m_document);
    m_document = m_redo.takeLast();
    m_model.refresh();
    emit documentChanged();
}

bool Backend::save() {
    if (!dirty()) return true;

    // Refuse to overwrite edits another program made while the file was open.
    QFile current(m_path);
    if (current.open(QIODevice::ReadOnly) && QString::fromUtf8(current.readAll()) != m_savedText) {
        setError(tr("%1 changed on disk since it was opened. Reopen it to pick up those changes.").arg(fileName()));
        return false;
    }
    current.close();

    QString backupPath;
    if (!m_backedUp.contains(m_path)) {
        backupPath = Store::backup(m_path, m_savedText.toUtf8());
        if (backupPath.isEmpty()) {
            setError(tr("Couldn't back up %1, so it wasn't saved.").arg(fileName()));
            return false;
        }
        m_backedUp.insert(m_path);
    }

    QString problem;
    if (!Store::writeFile(m_path, m_document.text.toUtf8(), &problem)) {
        setError(problem);
        return false;
    }
    m_savedText = m_document.text;
    Store::saveAnalysis(m_path, Store::hashOf(m_savedText), m_document.toAnalysis());
    m_stale = false;
    emit documentChanged();
    emit message(backupPath.isEmpty() ? tr("Saved %1").arg(fileName())
                                      : tr("Saved %1. The original is kept at %2").arg(fileName(), backupPath));
    return true;
}

int Backend::optionLine(int option) const {
    return option >= 0 && option < m_document.options.size() ? m_document.options.at(option).line : 0;
}

QString Backend::previewColor(const QString &input) {
    // Gradients ("rgba(33ccffee) rgba(00ff99ee) 45deg") preview their first color.
    // A function form keeps its spaces ("rgb(255, 0, 0)"); anything else is cut at the first one.
    QString value = input.trimmed().remove('"').remove('\'');
    value = value.startsWith("rgb") && value.contains(')') ? value.left(value.indexOf(')') + 1)
                                                           : value.section(' ', 0, 0);
    static const QRegularExpression hexFunction(R"(^rgba?\(([0-9a-fA-F]{6})([0-9a-fA-F]{2})?\)$)");
    static const QRegularExpression decimalFunction(
        R"(^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$)");
    static const QRegularExpression hash(R"(^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$)");
    static const QRegularExpression zeroX(R"(^0x([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$)");

    QColor color;
    if (auto m = hexFunction.match(value); m.hasMatch()) {
        color = QColor("#" + m.captured(1));
        if (!m.captured(2).isEmpty()) color.setAlpha(m.captured(2).toInt(nullptr, 16));
    } else if (auto m = decimalFunction.match(value); m.hasMatch()) {
        color = QColor(m.captured(1).toInt(), m.captured(2).toInt(), m.captured(3).toInt());
        if (!m.captured(4).isEmpty()) {
            const double alpha = m.captured(4).toDouble();
            color.setAlphaF(alpha > 1 ? alpha / 255.0 : alpha);
        }
    } else if (auto m = hash.match(value); m.hasMatch()) {
        // Eight digits are #rrggbbaa, the way CSS and most configs write them.
        const QString digits = m.captured(1);
        color = QColor("#" + digits.left(digits.size() == 8 ? 6 : digits.size()));
        if (digits.size() == 8) color.setAlpha(digits.right(2).toInt(nullptr, 16));
    } else if (auto m = zeroX.match(value); m.hasMatch()) {
        const QString digits = m.captured(1);
        color = QColor("#" + digits.right(6));
        if (digits.size() == 8) color.setAlpha(digits.left(2).toInt(nullptr, 16));
    } else if (QColor::isValidColorName(value) && !value.isEmpty() && value.at(0).isLetter()) {
        color = QColor::fromString(value);
    }
    return color.isValid() ? color.name(QColor::HexArgb) : QString();
}
