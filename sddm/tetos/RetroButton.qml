// Grey beveled push button in the TetOS / classic-Mac style.
import QtQuick 2.15

Rectangle {
  id: btn
  property string label: ""
  property real implicitW: txt.implicitWidth + 32
  signal clicked()

  width: Math.max(96, implicitW)
  height: 32
  color: area.pressed ? "#c4c4c4" : "#dedede"
  border.color: "#4a4a4a"
  border.width: 1

  // bevel flips when pressed
  Rectangle { x: 1; y: 1; width: parent.width - 2; height: 2; color: area.pressed ? "#a8a8a8" : "#ffffff" }
  Rectangle { x: 1; y: 1; width: 2; height: parent.height - 2; color: area.pressed ? "#a8a8a8" : "#ffffff" }
  Rectangle { x: 1; y: parent.height - 3; width: parent.width - 2; height: 2; color: area.pressed ? "#ffffff" : "#a8a8a8" }
  Rectangle { x: parent.width - 3; y: 1; width: 2; height: parent.height - 2; color: area.pressed ? "#ffffff" : "#a8a8a8" }

  Text {
    id: txt
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: area.pressed ? 1 : 0
    anchors.verticalCenterOffset: area.pressed ? 1 : 0
    text: btn.label
    color: area.containsMouse ? "#c43552" : "#111111"
    font.family: "ChicagoFLF"
    font.pixelSize: 14
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: btn.clicked()
  }
}
