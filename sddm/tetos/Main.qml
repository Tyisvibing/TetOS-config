// TetOS 4.1 SDDM greeter. Matches the TetOS splash / lock screen:
// blurred wallpaper, serif clock, grey beveled dialog with the Teto logo.
// Test: sddm-greeter-qt6 --test-mode --theme ~/Work/tetos-sddm/tetos
import QtQuick 2.15
import SddmComponents 2.0

Rectangle {
  id: root
  width: 1920
  height: 1080
  color: "#6361a0"

  readonly property color tetoRed: "#c43552"
  readonly property color dialogGrey: "#dedede"
  readonly property color inkColor: "#111111"

  property int userIndex: Math.max(0, userModel.lastIndex)
  property string userName: userData(userIndex, "name")
  property string userReal: userData(userIndex, "realName")
  property bool loginFailed: false
  property bool busy: false
  property var now: new Date()

  // Prefer Omarchy's session, else whatever was used last.
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var f = (sessionModel.data(sessionModel.index(i, 0), Qt.UserRole + 2) || "").toString()
      var n = (sessionModel.data(sessionModel.index(i, 0), Qt.UserRole + 4) || "").toString()
      if (f.indexOf("omarchy") !== -1 || n.toLowerCase().indexOf("omarchy") !== -1) return i
    }
    return Math.max(0, sessionModel.lastIndex)
  }

  // UserModel roles: NameRole = UserRole+1, RealNameRole = +2
  function userData(i, what) {
    var role = what === "name" ? Qt.UserRole + 1 : Qt.UserRole + 2
    return (userModel.data(userModel.index(i, 0), role) || "").toString()
  }

  function submit() {
    if (busy) return
    busy = true
    loginFailed = false
    sddm.login(userName, password.text, sessionIndex)
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.busy = false
      root.loginFailed = true
      password.text = ""
      password.forceActiveFocus()
    }
    function onLoginSucceeded() { root.busy = false }
  }

  Timer {
    interval: 1000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: root.now = new Date()
  }

  Image {
    anchors.fill: parent
    source: "background.jpg"
    fillMode: Image.PreserveAspectCrop
    asynchronous: false
  }

  MouseArea { anchors.fill: parent; onClicked: password.forceActiveFocus() }

  // ---- clock ----
  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: dialog.top
    anchors.bottomMargin: 40

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDateTime(root.now, "HH:mm")
      color: "#ffffff"
      font.family: "Liberation Serif"
      font.pixelSize: 132
      font.letterSpacing: -3
      style: Text.Raised
      styleColor: "#55000000"
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDateTime(root.now, "dddd, MMMM d")
      color: "#f7e9ed"
      font.family: "ChicagoFLF"
      font.pixelSize: 20
      style: Text.Raised
      styleColor: "#55000000"
    }
  }

  // ---- dialog ----
  Rectangle {
    x: dialog.x + 8; y: dialog.y + 8
    width: dialog.width; height: dialog.height
    color: "#000000"; opacity: 0.35
  }

  Rectangle {
    id: dialog
    width: 460
    height: 34 + panel.height + 16 + greeting.height + 14 + userRow.height + 12 + field.height + 30
    anchors.centerIn: parent
    anchors.verticalCenterOffset: 70
    color: root.dialogGrey
    border.color: "#4a4a4a"
    border.width: 1

    // classic bevel: light top/left, dark bottom/right
    Rectangle { x: 1; y: 1; width: parent.width - 2; height: 2; color: "#ffffff" }
    Rectangle { x: 1; y: 1; width: 2; height: parent.height - 2; color: "#ffffff" }
    Rectangle { x: 1; y: parent.height - 3; width: parent.width - 2; height: 2; color: "#a8a8a8" }
    Rectangle { x: parent.width - 3; y: 1; width: 2; height: parent.height - 2; color: "#a8a8a8" }

    Image {
      id: panel
      source: "panel.png"
      width: 381
      height: Math.round(width * 258 / 368)
      anchors.horizontalCenter: parent.horizontalCenter
      y: 34
      smooth: true
      mipmap: true
    }

    Text {
      id: greeting
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: panel.bottom
      anchors.topMargin: 16
      text: "Welcome to Kasane Territory"
      color: "#1a1a1a"
      font.family: "ChicagoFLF"
      font.pixelSize: 17
    }

    // user picker: arrows only appear when there is more than one user
    Row {
      id: userRow
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: greeting.bottom
      anchors.topMargin: 14
      spacing: 14

      RetroButton {
        label: "◀"; width: 30; visible: userModel.count > 1
        onClicked: { root.userIndex = (root.userIndex - 1 + userModel.count) % userModel.count; password.forceActiveFocus() }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.userReal.length > 0 ? root.userReal : root.userName
        color: root.inkColor
        font.family: "ChicagoFLF"
        font.pixelSize: 15
      }
      RetroButton {
        label: "▶"; width: 30; visible: userModel.count > 1
        onClicked: { root.userIndex = (root.userIndex + 1) % userModel.count; password.forceActiveFocus() }
      }
    }

    // sunken white password field
    Rectangle {
      id: field
      width: 381
      height: 52
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: userRow.bottom
      anchors.topMargin: 12
      color: "#ffffff"
      border.color: root.loginFailed ? root.tetoRed : "#1e1e1e"
      border.width: root.loginFailed ? 3 : 2
      // inset bevel
      Rectangle { x: 0; y: -2; width: parent.width; height: 1; color: "#a8a8a8" }
      Rectangle { x: -2; y: 0; width: 1; height: parent.height; color: "#a8a8a8" }

      TextInput {
        id: password
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        echoMode: TextInput.Password
        passwordCharacter: "●"
        passwordMaskDelay: 0
        color: root.inkColor
        selectionColor: root.tetoRed
        selectedTextColor: "#ffffff"
        font.pixelSize: 22
        font.letterSpacing: 4
        clip: true
        focus: true
        readOnly: root.busy
        cursorDelegate: Rectangle { width: 2; color: root.inkColor; visible: password.activeFocus && password.text.length > 0 }

        onTextChanged: if (text.length > 0) root.loginFailed = false
        onAccepted: root.submit()
        Keys.onEscapePressed: text = ""
      }

      Text {
        anchors.fill: parent
        visible: password.text.length === 0
        text: root.busy ? "Checking…" : (root.loginFailed ? "Wrong password, try again" : "Enter password")
        color: root.loginFailed ? root.tetoRed : (root.busy ? root.inkColor : "#7a7a7a")
        font.family: "ChicagoFLF"
        font.pixelSize: 18
        font.italic: root.loginFailed
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  // ---- bottom bar: session + power ----
  Row {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: 24
    spacing: 10

    RetroButton {
      width: Math.max(150, implicitW)
      label: "Session: " + ((sessionModel.data(sessionModel.index(root.sessionIndex, 0), Qt.UserRole + 4) || "?").toString())
      visible: sessionModel.rowCount() > 1
      onClicked: { root.sessionIndex = (root.sessionIndex + 1) % sessionModel.rowCount(); password.forceActiveFocus() }
    }
  }

  Row {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 24
    spacing: 10

    RetroButton { label: "Sleep"; visible: sddm.canSuspend; onClicked: sddm.suspend() }
    RetroButton { label: "Restart"; visible: sddm.canReboot; onClicked: sddm.reboot() }
    RetroButton { label: "Shut Down"; visible: sddm.canPowerOff; onClicked: sddm.powerOff() }
  }

  Component.onCompleted: password.forceActiveFocus()
}
