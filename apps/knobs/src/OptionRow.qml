import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// One setting: its name, what the docs say about it, and a control that
// writes it back to the file.
Rectangle {
    id: row

    required property int index
    required property string key
    required property string name
    required property string type
    required property string description
    required property string defaultValue
    required property string value
    required property var choices
    required property bool isSet
    required property int line
    required property int optionIndex
    property QtObject colors
    property bool current: false
    property string problem: ""

    signal activated()

    implicitHeight: content.implicitHeight + 28
    color: current ? colors.raised : "transparent"

    readonly property bool isBool: type === "bool"
    readonly property bool isChoice: type === "enum" && choices.length > 0
    readonly property bool isColor: type === "color"
    readonly property string swatch: isColor ? backend.previewColor(field.text) : ""

    function commit(text) {
        problem = backend.setValue(optionIndex, text)
        if (problem.length === 0 && field.text !== value) field.text = value
    }

    // Enter or Space on the row.
    function edit() {
        if (isBool) commit(toggle.checked ? backend.boolFalse : backend.boolTrue)
        else if (isChoice) combo.popup.open()
        else { field.forceActiveFocus(); field.selectAll() }
    }

    function reset() {
        if (isSet) problem = backend.unset(optionIndex)
    }

    onValueChanged: if (!field.activeFocus) { field.text = value; field.cursorPosition = 0 }

    Rectangle {
        visible: row.current
        width: 3
        height: parent.height
        color: theme.accent
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: row.colors.line }

    TapHandler { onTapped: row.activated() }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Label {
                    Layout.fillWidth: true
                    text: row.key
                    font.family: "monospace"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: row.colors.text
                    elide: Text.ElideRight
                }
                RowLayout {
                    spacing: 8
                    Rectangle {
                        visible: row.isSet
                        radius: Math.min(4, theme.radius)
                        color: Qt.alpha(theme.accent, 0.18)
                        implicitWidth: setLabel.implicitWidth + 12
                        implicitHeight: setLabel.implicitHeight + 4
                        Label {
                            id: setLabel
                            anchors.centerIn: parent
                            text: qsTr("line %1").arg(row.line)
                            font.pixelSize: 11
                            color: theme.accent
                        }
                    }
                    Label {
                        visible: !row.isSet || (row.defaultValue.length > 0 && row.value !== row.defaultValue)
                        text: row.isSet ? qsTr("default %1").arg(row.defaultValue)
                                        : row.defaultValue.length > 0 ? qsTr("not set · default %1").arg(row.defaultValue)
                                                                      : qsTr("not set")
                        font.pixelSize: 11
                        color: row.colors.muted
                        elide: Text.ElideRight
                        Layout.maximumWidth: 320
                    }
                }
            }

            Switch {
                id: toggle
                visible: row.isBool
                checked: row.value === backend.boolTrue
                onToggled: row.commit(checked ? backend.boolTrue : backend.boolFalse)
                onActiveFocusChanged: if (activeFocus) row.activated()
            }

            ComboBox {
                id: combo
                visible: row.isChoice
                Layout.preferredWidth: 230
                model: row.choices
                currentIndex: row.choices.indexOf(row.value)
                displayText: currentIndex < 0 ? row.value : currentText
                onActivated: idx => row.commit(row.choices[idx])
                onActiveFocusChanged: if (activeFocus) row.activated()
            }

            RowLayout {
                visible: !row.isBool && !row.isChoice
                spacing: 8
                Rectangle {
                    visible: row.isColor
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Math.min(4, theme.radius)
                    color: row.swatch.length > 0 ? row.swatch : "transparent"
                    border.color: row.colors.line
                    // A checker would be nicer under translucent colors; a
                    // diagonal says "not a color" when the text isn't one.
                    Rectangle {
                        visible: row.swatch.length === 0
                        anchors.centerIn: parent
                        width: parent.width * 1.2; height: 1
                        rotation: -45
                        color: row.colors.muted
                    }
                }
                TextField {
                    id: field
                    Layout.preferredWidth: row.isColor ? 222 : 260
                    text: row.value
                    placeholderText: row.defaultValue
                    font.family: "monospace"
                    selectByMouse: true
                    inputMethodHints: row.type === "int" || row.type === "float" ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
                    Component.onCompleted: cursorPosition = 0
                    onActiveFocusChanged: if (activeFocus) row.activated(); else cursorPosition = 0
                    onAccepted: { row.commit(text); ListView.view ? ListView.view.forceActiveFocus() : null }
                    onEditingFinished: if (text !== row.value) row.commit(text)
                    Keys.onEscapePressed: { text = row.value; row.problem = ""; row.ListView.view.forceActiveFocus() }
                }
            }

            ToolButton {
                // Kept in the layout when unset, so every row's control lines up.
                opacity: row.isSet ? 1 : 0
                enabled: row.isSet
                text: "↺"
                font.pixelSize: 16
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Remove from the file, so the default applies (Delete)")
                onClicked: row.reset()
            }
        }

        Label {
            Layout.fillWidth: true
            visible: row.description.length > 0
            text: row.description
            wrapMode: Text.WordWrap
            color: row.colors.muted
            lineHeight: 1.15
        }

        Label {
            Layout.fillWidth: true
            visible: row.problem.length > 0
            text: row.problem
            wrapMode: Text.WordWrap
            color: row.colors.danger
        }
    }
}
