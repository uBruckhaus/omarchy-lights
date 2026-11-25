pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "I18n.js" as I18n
import "corners.js" as Corners

// Bar indicator for Philips Hue. Lit icon in the theme's green while any light is on,
// dim icon when all are off or no bridge is paired. Left click opens the panel; right
// click switches every light off. All bridge traffic goes through scripts/hue-lights.py,
// which receives JSON commands on stdin and streams JSON snapshots on stdout.
Ui.BarWidget {
  id: root
  moduleName: "ubruckhaus.lights"

  // Interface language: the system's unless one is picked in the panel's
  // settings (stored in this widget's own shell.json entry).
  readonly property string systemLang: I18n.systemLanguage(Quickshell.env("LC_ALL"), Quickshell.env("LC_MESSAGES"), Quickshell.env("LANG"))
  readonly property string languageSetting: String(root.setting("language", "auto"))
  readonly property string lang: I18n.resolve(languageSetting, systemLang)
  function t(key, args) { return I18n.tr(lang, key, args) }
  function tn(key, n, args) { return I18n.trn(lang, key, n, args) }
  function setLanguage(code) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var next = Object.assign({}, root.settings || {})
    if (code === "auto") delete next.language
    else next.language = code
    root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  // Persisted settings in this widget's shell.json entry; defaults omit the key.
  readonly property string cornersSetting: Corners.choice(String(root.setting("corners", "windows")))
  readonly property var corners: Corners.sizes(cornersSetting, Style.cornerRadius)
  readonly property bool screenshotKey: root.setting("screenshotKey", true) !== false

  readonly property var validBarIcons: ["bulb", "deskLamp", "floorLamp", "sun", "sparkles", "bolt", "flame", "dot"]
  readonly property string barIconSetting: {
    var v = String(root.setting("barIcon", "bulb"))
    return validBarIcons.indexOf(v) >= 0 ? v : "bulb"
  }
  readonly property bool showCountSetting: root.setting("showCount", false) === true

  readonly property var validSkins: ["native", "synthwave", "cozy", "terminal", "disco", "zen"]
  readonly property string skinSetting: {
    var v = String(root.setting("skin", "native"))
    return validSkins.indexOf(v) >= 0 ? v : "native"
  }

  readonly property bool confirmAllOnSetting: root.setting("confirmAllOn", false) === true
  readonly property bool askAiSetting: root.setting("askAi", false) === true

  readonly property string scheduleModeSetting: String(root.setting("scheduleMode", "bridge")) === "local" ? "local" : "bridge"
  onScheduleModeSettingChanged: send({ cmd: "schedule_mode", mode: scheduleModeSetting })

  readonly property var favoritesSetting: {
    var v = root.setting("favorites", [])
    return Array.isArray(v) ? v : []
  }
  readonly property var excludeAllOnSetting: {
    var v = root.setting("excludeAllOn", [])
    return Array.isArray(v) ? v : []
  }

  // Saved popup size & offset (panelWidth 380..760, default 430; panelHeight 0=auto or 360..900;
  // panelOffsetX -320..320 default 0; panelOffsetY 0..240 default 0).
  readonly property int panelWidthSetting: {
    var n = Math.round(Number(root.setting("panelWidth", 430)))
    return isFinite(n) ? Math.max(380, Math.min(760, n)) : 430
  }
  readonly property int panelHeightSetting: {
    var n = Math.round(Number(root.setting("panelHeight", 0)))
    if (!isFinite(n) || n <= 0) return 0
    return Math.max(360, Math.min(900, n))
  }
  readonly property int panelOffsetXSetting: {
    var n = Math.round(Number(root.setting("panelOffsetX", 0)))
    return isFinite(n) ? Math.max(-320, Math.min(320, n)) : 0
  }
  readonly property int panelOffsetYSetting: {
    var n = Math.round(Number(root.setting("panelOffsetY", 0)))
    return isFinite(n) ? Math.max(0, Math.min(240, n)) : 0
  }

  function barIconGlyph(code, lit) {
    switch (code) {
    case "deskLamp":  return "󰥟"
    case "floorLamp": return "󰣜"
    case "sun":       return lit ? "󰖙" : "󰖨"
    case "sparkles":  return lit ? "󰦥" : "󰓒"
    case "bolt":      return lit ? "󱐋" : "󱐌"
    case "flame":     return "󰈸"
    case "dot":       return lit ? "●" : "○"
    default:          return lit ? "󰛨" : "󰌵"
    }
  }

  function saveSetting(key, value, fallback) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var next = Object.assign({}, root.settings || {})
    if (value === fallback) delete next[key]
    else next[key] = value
    root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  function saveListSetting(key, list) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var next = Object.assign({}, root.settings || {})
    var clean = Array.isArray(list) ? list.filter(function(x) { return typeof x === "string" && x.length > 0 }) : []
    if (clean.length === 0) delete next[key]
    else next[key] = clean
    root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  function setCorners(code) { saveSetting("corners", Corners.choice(code), "windows") }
  function setScreenshotKey(on) { saveSetting("screenshotKey", on === true, true) }
  function setBarIcon(code) {
    var v = validBarIcons.indexOf(code) >= 0 ? code : "bulb"
    saveSetting("barIcon", v, "bulb")
  }
  function setShowCount(on) { saveSetting("showCount", on === true, false) }
  function setSkin(code) {
    var v = validSkins.indexOf(code) >= 0 ? code : "native"
    saveSetting("skin", v, "native")
  }
  function setConfirmAllOn(on) { saveSetting("confirmAllOn", on === true, false) }
  function setAskAi(on) { saveSetting("askAi", on === true, false) }
  function setScheduleMode(mode) {
    var v = mode === "local" ? "local" : "bridge"
    saveSetting("scheduleMode", v, "bridge")
    send({ cmd: "schedule_mode", mode: v })
  }

  function isFavorite(key) {
    return favoritesSetting.indexOf(key) >= 0
  }
  function toggleFavorite(key) {
    if (!key) return
    var list = favoritesSetting.slice()
    var idx = list.indexOf(key)
    if (idx >= 0) list.splice(idx, 1)
    else list.push(key)
    saveListSetting("favorites", list)
  }

  function isExcludedAllOn(roomId) {
    return excludeAllOnSetting.indexOf(roomId) >= 0
  }
  function toggleExcludeAllOn(roomId) {
    if (!roomId) return
    var list = excludeAllOnSetting.slice()
    var idx = list.indexOf(roomId)
    if (idx >= 0) list.splice(idx, 1)
    else list.push(roomId)
    saveListSetting("excludeAllOn", list)
  }

  function setPanelGeometry(width, height, offsetX, offsetY) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var next = Object.assign({}, root.settings || {})
    var w = Math.max(380, Math.min(760, Math.round(Number(width) || 430)))
    var rawH = Math.round(Number(height) || 0)
    var h = rawH <= 0 ? 0 : Math.max(360, Math.min(900, rawH))
    var ox = Math.max(-320, Math.min(320, Math.round(Number(offsetX) || 0)))
    var oy = Math.max(0, Math.min(240, Math.round(Number(offsetY) || 0)))
    if (w === 430) delete next.panelWidth; else next.panelWidth = w
    if (h === 0) delete next.panelHeight; else next.panelHeight = h
    if (ox === 0) delete next.panelOffsetX; else next.panelOffsetX = ox
    if (oy === 0) delete next.panelOffsetY; else next.panelOffsetY = oy
    root.bar.shell.updateEntryInline(root.moduleName, next)
  }
  function setPanelWidth(w) { setPanelGeometry(w, panelHeightSetting, panelOffsetXSetting, panelOffsetYSetting) }
  function setPanelHeight(h) { setPanelGeometry(panelWidthSetting, h, panelOffsetXSetting, panelOffsetYSetting) }
  function setPanelOffsetX(ox) { setPanelGeometry(panelWidthSetting, panelHeightSetting, ox, panelOffsetYSetting) }
  function setPanelOffsetY(oy) { setPanelGeometry(panelWidthSetting, panelHeightSetting, panelOffsetXSetting, oy) }
  function resetPanelGeometry() { setPanelGeometry(430, 0, 0, 0) }

  property var stats: ({})
  // Push every snapshot into the panel; never let it read from an older widget instance.
  onStatsChanged: if (panelLoader.item && "stats" in panelLoader.item) panelLoader.item.stats = root.stats
  readonly property int onCount: Number(stats.on_count || 0)
  readonly property int lightCount: Number(stats.light_count || 0)
  readonly property bool anyOn: onCount > 0
  // The theme's green (colors.toml), like the other running indicators in the bar.
  property color green: "#66c98b"
  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/current/theme/colors.toml"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var match = text().match(/^\s*green\s*=\s*"(#[0-9a-fA-F]{6})"/m)
      if (match) root.green = match[1]
    }
  }
  readonly property string scriptDir: Qt.resolvedUrl("scripts").toString().replace(/^file:\/\//, "")

  readonly property string summary: {
    if (stats.phase === "unpaired" || stats.phase === "pairing") return "Lights\n" + t("tipUnpaired")
    if (stats.phase === "error") return "Lights\n" + (errorText() || t("tipUnreachable"))
    var lines = ["Lights · " + t("ofOn", [onCount, lightCount])]
    var rooms = stats.rooms || []
    for (var i = 0; i < rooms.length; i++) {
      if (rooms[i].kind === "room" || rooms[i].kind === "other")
        lines.push((rooms[i].on ? "● " : "○ ") + (rooms[i].kind === "other" ? t("otherLights") : rooms[i].name) + (rooms[i].on ? "  " + Math.round(rooms[i].bri) + "%" : ""))
    }
    if (anyOn) lines.push(t("rightClickOff"))
    return lines.join("\n")
  }

  // The helper's error in the interface language (older helpers send text only).
  function errorText() {
    if (!stats.error) return ""
    return stats.error_code ? t(stats.error_code, stats.error_args || []) : String(stats.error)
  }

  function send(obj) {
    if (helper.running) helper.write(JSON.stringify(obj) + "\n")
  }

  Process {
    id: helper
    command: ["python3", root.scriptDir + "/hue-lights.py"]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        try { root.stats = JSON.parse(line) } catch (e) { /* partial line during shutdown */ }
      }
    }
    onRunningChanged: {
      if (running) {
        Qt.callLater(function() {
          root.send({ cmd: "schedule_mode", mode: root.scheduleModeSetting })
          if (root.opened) root.send({ cmd: "open" })
        })
      }
    }
    onExited: restart.start()
  }
  Timer { id: restart; interval: 5000; onTriggered: helper.running = true }
  onOpenedChanged: send({ cmd: root.opened ? "open" : "closed" })

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("stats" in target) target.stats = root.stats
  }

  // Shape contract for shell summon/hide/toggle routing.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml") + "?load=" + Date.now()
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIconGlyph(root.barIconSetting, root.anyOn) + (root.showCountSetting && root.anyOn ? " " + root.onCount : "")
    dimmed: !root.anyOn
    foreground: root.anyOn ? root.green : (root.bar ? root.bar.barForeground : Commons.Color.foreground)
    tooltipText: root.opened ? "" : root.summary
    onPressed: function(code) {
      if (code === Qt.LeftButton) root.toggle()
      else if (code === Qt.RightButton && root.anyOn) root.send({ cmd: "all_off" })
    }
  }
}
