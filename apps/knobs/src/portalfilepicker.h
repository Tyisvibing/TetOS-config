#pragma once

#include <QVariantMap>

#include "filepicker.h"

// Open dialogs through xdg-desktop-portal (org.freedesktop.portal.FileChooser),
// so the picker is the desktop's own and works the same in every theme.
class PortalFilePicker : public FilePicker {
    Q_OBJECT

public:
    using FilePicker::FilePicker;
    void open(const QString &title, const QString &folder) override;

private slots:
    void onResponse(uint response, const QVariantMap &results);

private:
    QString m_handle;
    int m_counter = 0;
};
