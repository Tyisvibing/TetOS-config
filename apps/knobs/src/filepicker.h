#pragma once

#include <QObject>

// Picks a file to open. The app uses the desktop portal; tests inject a fake.
class FilePicker : public QObject {
    Q_OBJECT

public:
    using QObject::QObject;
    virtual void open(const QString &title, const QString &folder) = 0;

signals:
    void picked(const QString &path);
    void failed(const QString &error);
};
