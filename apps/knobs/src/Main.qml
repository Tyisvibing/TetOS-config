import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1240
    height: 800
    minimumWidth: 760
    minimumHeight: 480
    visible: true
    title: backend.hasFile ? (backend.dirty ? "• " : "") + backend.fileName + " — knobs" : "knobs"
    color: colors.window

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    readonly property QtObject colors: QtObject {
        readonly property color window: "#0e0e10"
        readonly property color panel: "#151518"
        readonly property color raised: "#1c1c21"
        readonly property color line: "#26262d"
        readonly property color text: "#e6e6ea"
        readonly property color muted: "#8b8b96"
        readonly property color danger: "#ff6b6b"
    }

    property bool helpVisible: false
    property bool sourceVisible: width > 1000
    // The document index of the selected row; reading count re-evaluates it when the filter changes.
    readonly property int currentOption: list.count >= 0 && list.currentIndex >= 0 ? backend.options.optionAt(list.currentIndex) : -1
    property var pendingAction: null
    readonly property bool typing: activeFocusItem !== null && activeFocusItem.hasOwnProperty("cursorPosition")

    // Anything that would throw away unsaved edits goes through here first.
    function guard(action) {
        if (backend.dirty) {
            pendingAction = action
            unsavedDialog.open()
        } else {
            action()
        }
    }

    function focusSearch() {
        if (backend.hasOptions) {
            search.forceActiveFocus()
            search.selectAll()
        }
    }

    onClosing: close => {
        if (backend.dirty) {
            close.accepted = false
            guard(() => Qt.quit())
        }
    }

    Shortcut { sequence: "?"; enabled: !win.typing; context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Q"; enabled: !win.typing; context: Qt.ApplicationShortcut; onActivated: win.guard(() => Qt.quit()) }
    Shortcut { sequence: "Ctrl+Q"; context: Qt.ApplicationShortcut; onActivated: win.guard(() => Qt.quit()) }
    Shortcut { sequence: "Ctrl+O"; context: Qt.ApplicationShortcut; onActivated: win.guard(() => backend.pickFile()) }
    Shortcut { sequence: "Ctrl+W"; context: Qt.ApplicationShortcut; enabled: backend.hasFile; onActivated: win.guard(() => backend.closeFile()) }
    Shortcut { sequences: [StandardKey.Save]; context: Qt.ApplicationShortcut; onActivated: backend.save() }
    Shortcut { sequences: [StandardKey.Undo]; enabled: !win.typing; context: Qt.ApplicationShortcut; onActivated: backend.undo() }
    Shortcut { sequences: [StandardKey.Redo, "Ctrl+Shift+Z"]; enabled: !win.typing; context: Qt.ApplicationShortcut; onActivated: backend.redo() }
    Shortcut { sequences: ["/", StandardKey.Find]; enabled: !win.typing || search.activeFocus; context: Qt.ApplicationShortcut; onActivated: win.focusSearch() }
    Shortcut { sequence: "R"; enabled: !win.typing && backend.hasFile; context: Qt.ApplicationShortcut; onActivated: backend.reanalyze() }
    Shortcut { sequence: "S"; enabled: !win.typing && backend.hasOptions; context: Qt.ApplicationShortcut; onActivated: win.sourceVisible = !win.sourceVisible }
    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        onActivated: {
            if (win.helpVisible) win.helpVisible = false
            else if (backend.busy) backend.cancel()
            else if (search.text.length > 0) { search.text = ""; list.forceActiveFocus() }
            else list.forceActiveFocus()
        }
    }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        StartPane {
            anchors.fill: parent
            visible: !backend.hasFile
            colors: win.colors
            onOpenRequested: path => backend.openFile(path)
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            visible: backend.hasFile

            // Header: the file, what reads it, and where its docs are.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: header.implicitHeight + 24
                color: win.colors.panel

                RowLayout {
                    id: header
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 16
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: 10
                            Label {
                                text: backend.fileName
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                                color: win.colors.text
                            }
                            Label {
                                visible: backend.program.length > 0
                                text: backend.format.length > 0 ? backend.program + " · " + backend.format : backend.program
                                color: win.colors.muted
                            }
                            Rectangle {
                                visible: backend.dirty
                                width: 8; height: 8; radius: 4
                                color: theme.accent
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: backend.summary.length > 0 ? backend.summary : backend.path
                            color: win.colors.muted
                            elide: Text.ElideMiddle
                        }
                    }

                    Button {
                        visible: backend.docs.length > 0
                        text: qsTr("Docs")
                        flat: true
                        onClicked: docsMenu.popup()
                        Menu {
                            id: docsMenu
                            Repeater {
                                model: backend.docs
                                MenuItem {
                                    text: modelData.title
                                    onTriggered: Qt.openUrlExternally(modelData.url.startsWith("/") ? "file://" + modelData.url : modelData.url)
                                }
                            }
                        }
                    }
                    Button {
                        text: qsTr("Explain again")
                        flat: true
                        enabled: !backend.busy
                        visible: backend.hasOptions
                        onClicked: backend.reanalyze()
                    }
                    Button {
                        text: qsTr("Save")
                        highlighted: true
                        enabled: backend.dirty
                        onClicked: backend.save()
                    }
                }
            }

            // What Claude is doing while it reads the docs.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                visible: backend.busy
                color: win.colors.raised
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 16
                    spacing: 12
                    BusyIndicator { Layout.preferredWidth: 24; Layout.preferredHeight: 24; running: backend.busy }
                    Label {
                        Layout.fillWidth: true
                        text: backend.status
                        color: win.colors.text
                        elide: Text.ElideRight
                    }
                    Label { text: qsTr("Esc to stop"); color: win.colors.muted }
                }
            }

            Banner {
                Layout.fillWidth: true
                visible: backend.error.length > 0
                text: backend.error
                tone: win.colors.danger
                colors: win.colors
                actionText: qsTr("Dismiss")
                onAction: backend.clearError()
            }

            Banner {
                Layout.fillWidth: true
                visible: backend.stale && !backend.busy && backend.error.length === 0
                text: qsTr("The file changed since it was explained, so some settings may be out of date.")
                tone: theme.accent
                colors: win.colors
                actionText: qsTr("Explain again")
                onAction: backend.reanalyze()
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Sections.
                Rectangle {
                    Layout.preferredWidth: 230
                    Layout.fillHeight: true
                    color: win.colors.panel
                    visible: backend.hasOptions

                    ListView {
                        id: sectionList
                        anchors.fill: parent
                        anchors.topMargin: 8
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        model: [{ "name": "", "label": qsTr("All settings"), "count": backend.optionCount },
                                { "name": "\u0001", "label": qsTr("Set in this file"), "count": backend.setCount }]
                               .concat(backend.sections.map(s => ({ "name": s.name, "label": s.name, "count": s.count })))
                        delegate: ItemDelegate {
                            id: sectionItem
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: 38
                            readonly property bool selected: modelData.name === "\u0001"
                                ? backend.options.setOnly
                                : !backend.options.setOnly && backend.options.section === modelData.name
                            background: Rectangle {
                                color: sectionItem.selected ? Qt.alpha(theme.accent, 0.16)
                                     : sectionItem.hovered ? win.colors.raised : "transparent"
                            }
                            contentItem: RowLayout {
                                spacing: 8
                                Label {
                                    Layout.fillWidth: true
                                    text: sectionItem.modelData.label
                                    color: sectionItem.selected ? theme.accent : win.colors.text
                                    font.weight: sectionItem.index < 2 ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }
                                Label {
                                    text: Number(sectionItem.modelData.count).toLocaleString(Qt.locale(), 'f', 0)
                                    color: win.colors.muted
                                    font.pixelSize: 12
                                }
                            }
                            onClicked: {
                                search.text = ""
                                backend.options.setOnly = modelData.name === "\u0001"
                                backend.options.section = modelData.name === "\u0001" ? "" : modelData.name
                                list.currentIndex = 0
                                list.positionViewAtBeginning()
                            }
                        }
                    }
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: win.colors.line }
                }

                // Settings.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    TextField {
                        id: search
                        Layout.fillWidth: true
                        Layout.margins: 12
                        visible: backend.hasOptions
                        placeholderText: qsTr("Search %n settings  ( / )", "", backend.optionCount)
                        onTextChanged: {
                            backend.options.search = text
                            list.currentIndex = 0
                        }
                        Keys.onDownPressed: list.forceActiveFocus()
                        Keys.onReturnPressed: list.forceActiveFocus()
                    }

                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: backend.hasOptions
                        clip: true
                        focus: true
                        model: backend.options
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 0
                        keyNavigationEnabled: true
                        ScrollBar.vertical: ScrollBar {}
                        delegate: OptionRow {
                            width: list.width
                            colors: win.colors
                            current: ListView.isCurrentItem
                            onActivated: list.currentIndex = index
                        }
                        // Enter or Space edits the current setting.
                        Keys.onReturnPressed: if (currentItem) currentItem.edit()
                        Keys.onSpacePressed: if (currentItem) currentItem.edit()
                        Keys.onDeletePressed: if (currentItem) currentItem.reset()

                        Label {
                            anchors.centerIn: parent
                            visible: list.count === 0 && backend.hasOptions
                            text: qsTr("Nothing matches “%1”.").arg(search.text)
                            color: win.colors.muted
                        }
                    }

                    // While the first explanation is being written.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !backend.hasOptions
                        spacing: 10
                        Item { Layout.fillHeight: true }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: backend.busy ? qsTr("Reading the documentation for %1…").arg(backend.fileName)
                                               : qsTr("No explanation yet.")
                            font.pixelSize: 18
                            color: win.colors.text
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 460
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: backend.busy ? qsTr("Claude is finding the docs and listing every setting this file can hold. A big program can take a few minutes; the result is kept, so this happens once per file.")
                                               : qsTr("Press R to read the documentation and list every setting.")
                            color: win.colors.muted
                        }
                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            visible: !backend.busy
                            text: qsTr("Explain this file")
                            highlighted: true
                            onClicked: backend.reanalyze()
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                SourcePane {
                    Layout.preferredWidth: Math.min(520, win.width * 0.36)
                    Layout.fillHeight: true
                    visible: win.sourceVisible || !backend.hasOptions
                    colors: win.colors
                    lines: backend.lines
                    highlightLine: backend.optionLine(win.currentOption) + (backend.lines.length * 0)
                }
            }
        }

        // Saved, undone, and other short notes.
        Rectangle {
            id: toast
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            width: Math.min(parent.width - 48, toastLabel.implicitWidth + 32)
            height: toastLabel.implicitHeight + 20
            radius: theme.radius
            color: win.colors.raised
            border.color: win.colors.line
            opacity: toastTimer.running ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Label {
                id: toastLabel
                anchors.centerIn: parent
                width: Math.min(implicitWidth, toast.parent.width - 80)
                wrapMode: Text.WordWrap
                color: win.colors.text
            }
            Timer { id: toastTimer; interval: 4000 }
            Connections {
                target: backend
                function onMessage(text) { toastLabel.text = text; toastTimer.restart() }
                function onFileChanged() { list.currentIndex = 0; search.text = ""; backend.options.section = ""; backend.options.setOnly = false; Qt.callLater(() => list.forceActiveFocus()) }
                function onAnalyzed() { list.currentIndex = 0; list.forceActiveFocus() }
            }
        }

        HelpOverlay {
            anchors.fill: parent
            visible: win.helpVisible
            colors: win.colors
            onDismissed: win.helpVisible = false
        }
    }

    Dialog {
        id: unsavedDialog
        anchors.centerIn: parent
        modal: true
        title: qsTr("Save changes to %1?").arg(backend.fileName)
        Label {
            text: qsTr("Your changes are lost if you don't save them.")
            color: win.colors.muted
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Save")
                highlighted: true
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            }
            Button {
                text: qsTr("Don't save")
                flat: true
                DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
            }
            Button {
                text: qsTr("Cancel")
                flat: true
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            }
            onAccepted: {
                unsavedDialog.close()
                if (backend.save() && win.pendingAction) win.pendingAction()
                win.pendingAction = null
            }
            onRejected: { unsavedDialog.close(); win.pendingAction = null }
            onClicked: button => {
                if (button.DialogButtonBox.buttonRole === DialogButtonBox.DestructiveRole) {
                    unsavedDialog.close()
                    const action = win.pendingAction
                    win.pendingAction = null
                    // Discarding means the edits go, so undo them first.
                    while (backend.canUndo) backend.undo()
                    if (action) action()
                }
            }
        }
    }
}
