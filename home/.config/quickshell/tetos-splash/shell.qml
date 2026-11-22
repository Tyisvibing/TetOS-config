// TetOS 4.1 login splash. Shows the "Welcome to Kasane Territory" box centred on
// every screen for a few seconds, fades out, then exits. Click to dismiss early.
// Run again any time with:  qs -c tetos-splash
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    property int holdMs: 4000
    property int fadeMs: 700
    property real alpha: 0

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "tetos-splash"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                anchors.fill: parent
                opacity: root.alpha

                // soft drop shadow
                Rectangle {
                    x: box.x + 6; y: box.y + 6
                    width: box.width; height: box.height
                    color: "#000000"; opacity: 0.35
                }
                Image {
                    id: box
                    source: Qt.resolvedUrl("tetos-splash.png")
                    width: Math.min(444, parent.width * 0.8)
                    height: width * 376 / 444
                    anchors.centerIn: parent
                    smooth: true
                    mipmap: true
                }
                MouseArea { anchors.fill: parent; onClicked: hide.restart() }
            }
        }
    }

    NumberAnimation on alpha { id: show; from: 0; to: 1; duration: 250; running: true }
    Timer { interval: root.holdMs; running: true; onTriggered: hide.start() }
    SequentialAnimation {
        id: hide
        NumberAnimation { target: root; property: "alpha"; to: 0; duration: root.fadeMs; easing.type: Easing.InQuad }
        ScriptAction { script: Qt.quit() }
    }
}
