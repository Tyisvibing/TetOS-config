#include "portalfilepicker.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QUrl>

namespace {
const char *Service = "org.freedesktop.portal.Desktop";
const char *ObjectPath = "/org/freedesktop/portal/desktop";
}

void PortalFilePicker::open(const QString &title, const QString &folder) {
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        emit failed(tr("The desktop portal isn't reachable (no D-Bus session)."));
        return;
    }

    // Subscribe to the request's Response before asking, at the handle the
    // portal will use for our token, so a fast answer can't be missed.
    const QString token = QString("knobs%1").arg(++m_counter);
    QString sender = bus.baseService().mid(1);
    sender.replace('.', '_');
    const QString expected = QString("/org/freedesktop/portal/desktop/request/%1/%2").arg(sender, token);
    if (!m_handle.isEmpty())
        bus.disconnect(Service, m_handle, "org.freedesktop.portal.Request", "Response", this,
                       SLOT(onResponse(uint, QVariantMap)));
    m_handle = expected;
    bus.connect(Service, m_handle, "org.freedesktop.portal.Request", "Response", this,
                SLOT(onResponse(uint, QVariantMap)));

    QVariantMap options{{"handle_token", token}, {"modal", true}};
    if (!folder.isEmpty())
        options.insert("current_folder", folder.toUtf8() + '\0');

    auto message = QDBusMessage::createMethodCall(Service, ObjectPath, "org.freedesktop.portal.FileChooser", "OpenFile");
    message << QString() << title << options;
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        watcher->deleteLater();
        QDBusPendingReply<QDBusObjectPath> reply = *watcher;
        if (reply.isError()) {
            emit failed(tr("The file chooser didn't open: %1").arg(reply.error().message()));
            return;
        }
        // Older portals pick their own handle; follow it.
        const QString actual = reply.value().path();
        if (actual != m_handle) {
            auto bus = QDBusConnection::sessionBus();
            bus.disconnect(Service, m_handle, "org.freedesktop.portal.Request", "Response", this,
                           SLOT(onResponse(uint, QVariantMap)));
            m_handle = actual;
            bus.connect(Service, m_handle, "org.freedesktop.portal.Request", "Response", this,
                        SLOT(onResponse(uint, QVariantMap)));
        }
    });
}

void PortalFilePicker::onResponse(uint response, const QVariantMap &results) {
    if (response != 0)
        return; // Cancelled.
    QStringList uris;
    const QVariant value = results.value("uris");
    if (value.canConvert<QDBusArgument>())
        value.value<QDBusArgument>() >> uris;
    else
        uris = value.toStringList();
    if (!uris.isEmpty())
        emit picked(QUrl(uris.first()).toLocalFile());
}
