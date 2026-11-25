// Omarchy-style top bar for MangoWC, ported from the Hyprland bar in
// ~/.config/omarchy/shell.json. Same layout (menu + workspaces | clock | tray,
// keyboard, bluetooth, network, audio, power) and the tetos palette.
// Mango has no Quickshell backend, so workspaces come from `mmsg` instead.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Networking
import Quickshell.Bluetooth

ShellRoot {
  id: root

  // ---- palette and metrics (from ~/.config/omarchy/themes/tetos/colors.toml)
  readonly property color bg: "#140d0f"
  readonly property color fg: "#f0dde2"
  readonly property color dimFg: "#6b4a52"
  readonly property color accent: "#c43552"
  readonly property color urgent: "#d9405e"
  readonly property string fontFamily: "DepartureMono Nerd Font"
  readonly property int fontSize: 12
  readonly property int barHeight: 26
  readonly property string home: Quickshell.env("HOME")

  // Workspace glyphs, same order as the jcruz.custom-workspaces entry in shell.json.
  // Tags past the sixth have no glyph there, so they show their number.
  readonly property var tagIcons: ["", "", "", "", "\uDB80\uDF86", ""]

  // ---- mango state -----------------------------------------------------------
  property var tagsByMonitor: ({})
  property string layoutName: ""

  function parseTags(text) {
    try {
      var data = JSON.parse(text)
      var map = {}
      for (var i = 0; i < data.all_tags.length; i++)
        map[data.all_tags[i].monitor] = data.all_tags[i].tags
      root.tagsByMonitor = map
    } catch (e) {
      console.warn("mangobar: bad all-tags output:", e)
    }
  }

  function parseLayout(text) {
    try {
      root.layoutName = JSON.parse(text).layout || ""
    } catch (e) {
      console.warn("mangobar: bad keyboardlayout output:", e)
    }
  }

  // "English (US)" -> "US", anything without a parenthesised part -> first two letters.
  function shortLayout(name) {
    var m = name.match(/\(([^)]+)\)/)
    return m ? m[1] : name.slice(0, 2).toUpperCase()
  }

  function refreshTags() { if (!tagsProc.running) tagsProc.running = true }
  function refreshLayout() { if (!layoutProc.running) layoutProc.running = true }

  Process {
    id: tagsProc
    command: ["mmsg", "get", "all-tags"]
    stdout: StdioCollector { id: tagsOut; onStreamFinished: root.parseTags(tagsOut.text) }
  }

  Process {
    id: layoutProc
    command: ["mmsg", "get", "keyboardlayout"]
    stdout: StdioCollector { id: layoutOut; onStreamFinished: root.parseLayout(layoutOut.text) }
  }

  // `mmsg watch` streams a line whenever a tag or the keyboard layout changes.
  // Each line just triggers a fresh read, which keeps parsing in one place.
  Process {
    command: ["mmsg", "watch", "all-tags"]
    running: true
    stdout: SplitParser { onRead: root.refreshTags() }
  }

  Process {
    command: ["mmsg", "watch", "keyboardlayout"]
    running: true
    stdout: SplitParser { onRead: root.refreshLayout() }
  }

  // Fallback in case a watch stream dies. Cheap, one short read each time.
  Timer {
    interval: 3000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: { root.refreshTags(); root.refreshLayout() }
  }

  // ---- clock -----------------------------------------------------------------
  SystemClock { id: clock; precision: SystemClock.Minutes }

  // ---- world clocks (the omarchy.elsewhen cities from shell.json) -------------
  readonly property var cities: [
    { name: "UTC", zone: "UTC" },
    { name: "Dubai", zone: "Asia/Dubai" },
    { name: "Tokyo", zone: "Asia/Tokyo" },
    { name: "Los Angeles", zone: "America/Los_Angeles" },
    { name: "New York", zone: "America/New_York" }
  ]
  property var cityTimes: []
  property int cityIndex: 0

  // QML has no timezone support, so ask `date` for each zone.
  Process {
    id: zonesProc
    running: true
    command: ["sh", "-c", root.cities.map(c => "TZ=" + c.zone + " date +%H:%M").join("; ")]
    stdout: StdioCollector { id: zonesOut; onStreamFinished: root.cityTimes = zonesOut.text.trim().split("\n") }
  }
  Connections {
    target: clock
    function onDateChanged() { if (!zonesProc.running) zonesProc.running = true }
  }

  // ---- weather (location from Omarchy's weather.json) -------------------------
  property string weatherText: ""

  function weatherIcon(code, isDay) {
    if (code === 0) return isDay ? "" : ""        // clear
    if (code <= 2) return isDay ? "" : ""         // partly cloudy
    if (code === 3) return ""                           // overcast
    if (code === 45 || code === 48) return ""           // fog
    if (code >= 51 && code <= 67) return ""             // drizzle / rain
    if (code >= 71 && code <= 77) return ""             // snow
    if (code >= 80 && code <= 82) return ""             // showers
    if (code >= 85 && code <= 86) return ""             // snow showers
    if (code >= 95) return ""                           // thunder
    return ""
  }

  FileView {
    id: weatherLocation
    path: root.home + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.fetchWeather()
  }

  function fetchWeather() {
    try {
      var loc = JSON.parse(weatherLocation.text())
      weatherProc.command = ["curl", "-sf", "--max-time", "15",
        "https://api.open-meteo.com/v1/forecast?latitude=" + loc.latitude + "&longitude=" + loc.longitude +
        "&current=temperature_2m,weather_code,is_day"]
      weatherProc.running = true
    } catch (e) {
      console.warn("mangobar: bad weather.json:", e)
    }
  }

  Process {
    id: weatherProc
    stdout: StdioCollector {
      id: weatherOut
      onStreamFinished: {
        try {
          var c = JSON.parse(weatherOut.text).current
          root.weatherText = root.weatherIcon(c.weather_code, c.is_day === 1) + " " + Math.round(c.temperature_2m) + "°C"
        } catch (e) { /* keep the last reading */ }
      }
    }
  }

  Timer { interval: 15 * 60 * 1000; repeat: true; running: true; onTriggered: root.fetchWeather() }

  // ---- audio -----------------------------------------------------------------
  PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

  readonly property var sinkAudio: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null

  function volumeIcon() {
    if (!sinkAudio) return ""
    if (sinkAudio.muted) return ""
    var v = sinkAudio.volume
    if (v >= 0.67) return ""
    if (v >= 0.34) return ""
    if (v > 0) return ""
    return ""
  }

  // ---- network and bluetooth -------------------------------------------------
  function listValues(list) {
    if (!list) return []
    return list.values !== undefined ? list.values : list
  }

  function wifiIcon(strength) {
    var icons = ["\uDB82\uDD2F", "\uDB82\uDD1F", "\uDB82\uDD22", "\uDB82\uDD25", "\uDB82\uDD28"]
    var i = Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1))
    return icons[i]
  }

  function networkIcon() {
    var devices = listValues(Networking.devices)
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d.connected) continue
      if (d.networks !== undefined) {
        var nets = listValues(d.networks)
        for (var j = 0; j < nets.length; j++)
          if (nets[j].connected) return wifiIcon(nets[j].signalStrength)
        return wifiIcon(50)
      }
      return "\uDB80\uDE00" // wired
    }
    return "\uDB82\uDD2E" // disconnected
  }

  function bluetoothIcon() {
    var adapter = Bluetooth.defaultAdapter
    if (!adapter || !adapter.enabled) return "\uDB80\uDCB2"
    var devices = listValues(Bluetooth.devices)
    for (var i = 0; i < devices.length; i++)
      if (devices[i].connected) return "\uDB80\uDCB1"
    return "\uDB80\uDCAF"
  }

  function run(cmd) { Quickshell.execDetached(cmd) }

  // ---- bar, one per screen ---------------------------------------------------
  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: bar
      required property var modelData
      screen: modelData

      anchors { top: true; left: true; right: true }
      implicitHeight: root.barHeight
      exclusiveZone: root.barHeight
      color: root.bg
      WlrLayershell.namespace: "mangobar"

      readonly property var tags: root.tagsByMonitor[modelData.name] || []

      // Left: menu, then workspaces
      RowLayout {
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Text {
          text: ""
          font.family: "omarchy"
          font.pixelSize: root.fontSize + 2
          color: root.fg
          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
              if (mouse.button === Qt.RightButton) root.run(["xdg-terminal-exec"])
              else root.run(["rofi", "-show", "drun"])
            }
          }
        }

        Item { implicitWidth: 6 }

        Repeater {
          model: bar.tags
          delegate: Text {
            required property var modelData
            readonly property int slot: modelData.index
            readonly property bool hasIcon: slot - 1 < root.tagIcons.length && root.tagIcons[slot - 1] !== ""
            text: hasIcon ? root.tagIcons[slot - 1] : String(slot)
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            color: modelData.is_urgent ? root.urgent
                 : modelData.is_active ? root.accent
                 : modelData.client_count > 0 ? root.fg
                 : root.dimFg
            font.bold: modelData.is_active
            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              onClicked: root.run(["mmsg", "dispatch", "view," + slot + ",0"])
            }
          }
        }
      }

      // Center: clock
      Text {
        id: clockText
        anchors.centerIn: parent
        text: Qt.formatDateTime(clock.date, "ddd d MMM h:mm AP")
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        color: root.fg
      }

      // Center end: world clock (click to cycle cities), then weather
      RowLayout {
        anchors.left: clockText.right
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Text {
          visible: root.cityTimes.length === root.cities.length
          text: " " + root.cities[root.cityIndex].name + " " + (root.cityTimes[root.cityIndex] || "")
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          color: root.fg
          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
              var n = root.cities.length
              root.cityIndex = (root.cityIndex + (mouse.button === Qt.RightButton ? n - 1 : 1)) % n
            }
          }
        }

        Text {
          visible: root.weatherText !== ""
          text: root.weatherText
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          color: root.fg
          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: root.fetchWeather()
          }
        }
      }

      // Right: tray, keyboard layout, bluetooth, network, audio, power
      RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Repeater {
          model: SystemTray.items
          delegate: Image {
            required property var modelData
            // Quickshell already hands tray icons over as a ready image:// URL.
            // Running it through Quickshell.iconPath() treats it as an icon name,
            // which fails and draws the purple/black missing-icon texture.
            source: modelData.icon
            sourceSize: Qt.size(14, 14)
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14
            MouseArea {
              anchors.fill: parent
              onClicked: modelData.activate()
            }
          }
        }

        Text {
          text: " " + root.shortLayout(root.layoutName)
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          color: root.fg
          visible: root.layoutName !== ""
        }

        Text {
          text: root.bluetoothIcon()
          font.family: root.fontFamily
          font.pixelSize: root.fontSize + 1
          color: root.fg
          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: { if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled }
          }
        }

        Text {
          text: root.networkIcon()
          font.family: root.fontFamily
          font.pixelSize: root.fontSize + 1
          color: root.fg
        }

        Text {
          text: root.volumeIcon() + (root.sinkAudio ? " " + Math.round(root.sinkAudio.volume * 100) + "%" : "")
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          color: root.sinkAudio && root.sinkAudio.muted ? root.dimFg : root.fg
          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            acceptedButtons: Qt.LeftButton
            onClicked: { if (root.sinkAudio) root.sinkAudio.muted = !root.sinkAudio.muted }
            onWheel: (wheel) => {
              if (!root.sinkAudio) return
              var step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
              root.sinkAudio.volume = Math.max(0, Math.min(1, root.sinkAudio.volume + step))
            }
          }
        }

        Text {
          text: ""
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          color: root.fg
          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: root.run([root.home + "/.config/mango/power.sh"])
          }
        }
      }
    }
  }
}
