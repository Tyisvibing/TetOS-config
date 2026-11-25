import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Every shortcut, shown with ?.
Rectangle {
    id: overlay

    property QtObject colors
    signal dismissed()

    color: Qt.rgba(0, 0, 0, 0.6)

    TapHandler { onTapped: overlay.dismissed() }

    readonly property var shortcuts: [
        ["Ctrl+O", qsTr("Open a config file")],
        ["/", qsTr("Search settings")],
        ["↑ ↓", qsTr("Move between settings")],
        ["Enter / Space", qsTr("Change the current setting")],
        ["Delete", qsTr("Remove it from the file, so the default applies")],
        ["Esc", qsTr("Leave a field, clear the search, or stop reading the docs")],
        ["Ctrl+S", qsTr("Save")],
        ["Ctrl+Z", qsTr("Undo")],
        ["Ctrl+Shift+Z", qsTr("Redo")],
        ["R", qsTr("Read the documentation again")],
        ["S", qsTr("Show or hide the file")],
        ["Ctrl+W", qsTr("Close the file")],
        ["?", qsTr("Show or hide these shortcuts")],
        ["Q", qsTr("Quit")],
    ]

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, grid.implicitWidth + 64)
        height: Math.min(parent.height - 48, column.implicitHeight + 48)
        radius: theme.radius
        color: overlay.colors.raised
        border.color: overlay.colors.line

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16
            Label {
                text: qsTr("Keyboard shortcuts")
                font.pixelSize: 18
                font.weight: Font.DemiBold
                color: overlay.colors.text
            }
            GridLayout {
                id: grid
                columns: 2
                columnSpacing: 24
                rowSpacing: 8
                Repeater {
                    model: overlay.shortcuts.length * 2
                    Label {
                        required property int index
                        readonly property bool isKey: index % 2 === 0
                        text: overlay.shortcuts[Math.floor(index / 2)][isKey ? 0 : 1]
                        font.family: isKey ? "monospace" : Qt.application.font.family
                        color: isKey ? theme.accent : overlay.colors.text
                    }
                }
            }
        }
    }
}
