#pragma once

#include <QJsonObject>
#include <QString>
#include <QStringList>

// What knobs keeps on disk: analyses cached per file (so reopening a file is
// instant and free), backups taken before the first save of each session, and
// the recently opened files.
namespace Store {

QString hashOf(const QString &text);
QString cacheFile(const QString &path);

// The cached analysis for a file and the hash of the text it was made from.
bool loadAnalysis(const QString &path, QJsonObject *analysis, QString *hash);
bool saveAnalysis(const QString &path, const QString &hash, const QJsonObject &analysis);

// Copies the file's current contents aside and returns where they went.
QString backup(const QString &path, const QByteArray &contents);

QStringList recentFiles();
void addRecentFile(const QString &path);

// Writes atomically next to the real file (following symlinks, which
// Omarchy uses for its themes), so a crash never leaves half a config.
bool writeFile(const QString &path, const QByteArray &contents, QString *error);

} // namespace Store
