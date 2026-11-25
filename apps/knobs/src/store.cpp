#include "store.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>

namespace {

QString stateDirectory() {
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + "/knobs";
}

QString canonical(const QString &path) {
    const QString resolved = QFileInfo(path).canonicalFilePath();
    return resolved.isEmpty() ? QFileInfo(path).absoluteFilePath() : resolved;
}

} // namespace

namespace Store {

QString hashOf(const QString &text) {
    return QString::fromLatin1(QCryptographicHash::hash(text.toUtf8(), QCryptographicHash::Sha256).toHex());
}

QString cacheFile(const QString &path) {
    const QString id = QString::fromLatin1(
        QCryptographicHash::hash(QFileInfo(path).absoluteFilePath().toUtf8(), QCryptographicHash::Sha1).toHex());
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/analyses/" + id + ".json";
}

bool loadAnalysis(const QString &path, QJsonObject *analysis, QString *hash) {
    QFile file(cacheFile(path));
    if (!file.open(QIODevice::ReadOnly))
        return false;
    const QJsonObject object = QJsonDocument::fromJson(file.readAll()).object();
    if (!object.value("analysis").isObject())
        return false;
    *analysis = object.value("analysis").toObject();
    *hash = object.value("hash").toString();
    return true;
}

bool saveAnalysis(const QString &path, const QString &hash, const QJsonObject &analysis) {
    const QString target = cacheFile(path);
    QDir().mkpath(QFileInfo(target).absolutePath());
    const QJsonObject object{{"path", QFileInfo(path).absoluteFilePath()}, {"hash", hash}, {"analysis", analysis}};
    QString ignored;
    return writeFile(target, QJsonDocument(object).toJson(QJsonDocument::Compact), &ignored);
}

QString backup(const QString &path, const QByteArray &contents) {
    const QString directory = stateDirectory() + "/backups";
    QDir().mkpath(directory);
    const QString target = directory + "/" + QFileInfo(path).fileName() + "."
                         + QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss");
    QFile file(target);
    if (!file.open(QIODevice::WriteOnly) || file.write(contents) != contents.size())
        return {};
    return target;
}

QStringList recentFiles() {
    QFile file(stateDirectory() + "/recent.json");
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QStringList result;
    for (const auto &value : QJsonDocument::fromJson(file.readAll()).array())
        if (QFileInfo::exists(value.toString())) result.append(value.toString());
    return result;
}

void addRecentFile(const QString &path) {
    QStringList recent = recentFiles();
    const QString absolute = QFileInfo(path).absoluteFilePath();
    recent.removeAll(absolute);
    recent.prepend(absolute);
    while (recent.size() > 12) recent.removeLast();
    QDir().mkpath(stateDirectory());
    QString ignored;
    writeFile(stateDirectory() + "/recent.json",
              QJsonDocument(QJsonArray::fromStringList(recent)).toJson(QJsonDocument::Compact), &ignored);
}

bool writeFile(const QString &path, const QByteArray &contents, QString *error) {
    QSaveFile file(canonical(path));
    if (!file.open(QIODevice::WriteOnly) || file.write(contents) != contents.size() || !file.commit()) {
        *error = QCoreApplication::translate("Store", "Couldn't write %1: %2").arg(path, file.errorString());
        return false;
    }
    return true;
}

} // namespace Store
