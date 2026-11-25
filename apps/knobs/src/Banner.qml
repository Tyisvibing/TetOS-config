import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// A one-line notice under the header: an error, or a file gone stale.
Rectangle {
    id: banner

    property string text
    property color tone
    property string actionText
    property QtObject colors

    signal action()

    implicitHeight: label.implicitHeight + 20
    color: Qt.alpha(tone, 0.14)

    Rectangle { width: 3; height: parent.height; color: banner.tone }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 12
        spacing: 12
        Label {
            id: label
            Layout.fillWidth: true
            text: banner.text
            wrapMode: Text.WordWrap
            color: banner.colors.text
        }
        Button {
            text: banner.actionText
            flat: true
            onClicked: banner.action()
        }
    }
}
