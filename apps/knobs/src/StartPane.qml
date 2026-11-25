import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// No file open: type a path, pick one, or reopen a recent one.
Item {
    id: start

    property QtObject colors
    signal openRequested(string path)

    readonly property var files: {
        const seen = {}
        const list = []
        for (const path of backend.recentFiles.concat(backend.suggestedFiles)) {
            if (seen[path]) continue
            seen[path] = true
            list.push({ "path": path, "recent": backend.recentFiles.indexOf(path) >= 0 })
        }
        return list.slice(0, 12)
    }

    function shortPath(path) {
        return path.startsWith(backend.home + "/") ? "~" + path.slice(backend.home.length) : path
    }

    onVisibleChanged: if (visible) pathField.forceActiveFocus()
    Component.onCompleted: pathField.forceActiveFocus()

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 620)
        spacing: 14

        Label {
            text: "knobs"
            font.pixelSize: 40
            font.weight: Font.Bold
            color: theme.accent
        }
        Label {
            Layout.fillWidth: true
            text: qsTr("Open any config file to see every setting it can hold, explained from the program's own documentation.")
            wrapMode: Text.WordWrap
            color: start.colors.muted
            font.pixelSize: 15
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            spacing: 10
            TextField {
                id: pathField
                Layout.fillWidth: true
                placeholderText: qsTr("Path to a config file")
                font.family: "monospace"
                onAccepted: if (text.trim().length > 0) start.openRequested(text)
                Keys.onDownPressed: recentList.forceActiveFocus()
            }
            Button {
                text: qsTr("Choose…")
                highlighted: true
                onClicked: backend.pickFile()
            }
        }

        Label {
            visible: backend.error.length > 0
            Layout.fillWidth: true
            text: backend.error
            wrapMode: Text.WordWrap
            color: start.colors.danger
        }

        Label {
            visible: start.files.length > 0
            Layout.topMargin: 12
            text: backend.recentFiles.length > 0 ? qsTr("Recent and common") : qsTr("Found on this computer")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: start.colors.muted
        }

        ListView {
            id: recentList
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 40 * 8)
            clip: true
            model: start.files
            keyNavigationEnabled: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: ItemDelegate {
                id: fileItem
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 40
                highlighted: ListView.isCurrentItem && recentList.activeFocus
                contentItem: RowLayout {
                    spacing: 10
                    Label {
                        Layout.fillWidth: true
                        text: start.shortPath(fileItem.modelData.path)
                        font.family: "monospace"
                        color: start.colors.text
                        elide: Text.ElideMiddle
                    }
                    Label {
                        visible: fileItem.modelData.recent
                        text: qsTr("recent")
                        font.pixelSize: 11
                        color: start.colors.muted
                    }
                }
                onClicked: start.openRequested(modelData.path)
            }
            Keys.onReturnPressed: if (currentItem) start.openRequested(start.files[currentIndex].path)
            Keys.onUpPressed: currentIndex > 0 ? decrementCurrentIndex() : pathField.forceActiveFocus()
        }

        Label {
            Layout.topMargin: 8
            text: qsTr("Press ? for shortcuts")
            color: start.colors.muted
            font.pixelSize: 12
        }
    }
}
