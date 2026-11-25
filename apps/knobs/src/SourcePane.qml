import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// The file as it will be saved, scrolled to the line of the current setting.
Rectangle {
    id: pane

    property QtObject colors
    property var lines: []
    property int highlightLine: 0

    color: colors.panel

    onHighlightLineChanged: if (highlightLine > 0) view.positionViewAtIndex(highlightLine - 1, ListView.Center)

    Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: pane.colors.line }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 1
        spacing: 0

        Label {
            Layout.fillWidth: true
            Layout.margins: 12
            text: qsTr("File")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: pane.colors.muted
        }

        ListView {
            id: view
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: pane.lines
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            ScrollBar.horizontal: ScrollBar {}
            contentWidth: 1600
            flickableDirection: Flickable.AutoFlickIfNeeded
            delegate: Rectangle {
                required property string modelData
                required property int index
                width: Math.max(view.width, lineText.implicitWidth + 64)
                height: lineText.implicitHeight + 2
                color: index + 1 === pane.highlightLine ? Qt.alpha(theme.accent, 0.2) : "transparent"
                Label {
                    id: number
                    width: 44
                    horizontalAlignment: Text.AlignRight
                    text: index + 1
                    font.family: "monospace"
                    font.pixelSize: 12
                    color: pane.colors.muted
                    opacity: 0.6
                }
                Label {
                    id: lineText
                    anchors.left: number.right
                    anchors.leftMargin: 12
                    text: modelData.length > 0 ? modelData : " "
                    font.family: "monospace"
                    font.pixelSize: 12
                    textFormat: Text.PlainText
                    color: modelData.trim().startsWith("#") || modelData.trim().startsWith(";") || modelData.trim().startsWith("//")
                           ? pane.colors.muted : pane.colors.text
                }
            }
        }
    }
}
