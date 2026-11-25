pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "I18n.js" as I18n
import "corners.js" as Corners

// Lights popup: pairing flow while no bridge is paired; afterwards 5 tabs
// (Lights, Map, Schedules, Rules, Synth) plus Settings and Information pages.
// Repeaters are driven by counts and read the current snapshot by index, so a
// refresh never rebuilds rows (a slider drag survives every snapshot).
Panel {
  id: root
  moduleName: "ubruckhaus.lights"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property var stats: ({})  // pushed by BarWidget on every snapshot
  readonly property string phase: String(stats.phase || "connecting")
  readonly property bool paired: phase === "ok" || phase === "error" || phase === "connecting"
  readonly property var rooms: stats.rooms || []
  readonly property var candidates: stats.candidates || []
  readonly property var bridge: stats.bridge || ({})
  readonly property var schedules: stats.schedules || []
  readonly property var themes: stats.themes || []
  readonly property var rules: stats.rules || []
  readonly property bool rulesPaused: stats.rules_paused === true
  readonly property var ruleLog: stats.rule_log || []
  readonly property var synth: stats.synth || ({
    running: false, source: "system", mode: "club", palette: "neon",
    room_id: "", sensitivity: 1.0, smoothness: 0.45,
    bass: 0.0, mids: 0.0, treble: 0.0, beat: false, error: ""
  })
  readonly property var floorplan: stats.floorplan || null
  readonly property var entertainmentAreas: stats.entertainment_areas || []
  readonly property var sensors: stats.sensors || []
  readonly property var motionAreas: stats.motion_areas || []
  readonly property var providers: stats.providers || []
  readonly property var discoveredProviders: stats.discovered_providers || []
  readonly property bool discoveringProviders: stats.discovering_providers === true
  readonly property var providerAction: stats.provider_action || ({ running: false, kind: "", ok: false, message: "", pair_id: "" })
  readonly property bool huePaired: stats.hue_paired === true
  readonly property var aiState: stats.ai || ({
    busy: false, last_prompt: "", last_reply: "", last_actions: [], engine: "", error: ""
  })

  // Multi-device provider editor state
  property bool providerFormOpen: false
  property string provEditId: ""
  property string provKind: "home_assistant"
  property string provName: ""
  property string provHost: ""
  property string provPort: "8123"
  property string provRoom: ""
  property string provToken: ""
  property string provPairId: ""
  property bool provHttps: false
  property bool provHasSavedToken: false
  property bool provAwaitingSave: false
  property string provConfirmRemoveId: ""
  property string provOriginalHost: ""
  property string provOriginalPort: ""
  property string provOriginalKind: ""
  property bool provHasCertFp: false

  // Two-click delete for schedules and rules (second click within 4 s deletes)
  property string confirmDeleteSchedule: ""
  property string confirmDeleteRule: ""
  Timer {
    id: confirmDeleteTimer
    interval: 4000
    onTriggered: {
      root.confirmDeleteSchedule = ""
      root.confirmDeleteRule = ""
    }
  }

  // "kind|host|port" of every saved device, to mark discovered ones as already added
  function providerTargetKey(kind, host, port) {
    return String(kind || "") + "|" + String(host || "").toLowerCase() + "|" + String(parseInt(port, 10) || 0)
  }
  readonly property var existingProviderTargets: {
    var out = ({})
    var list = root.providers || []
    for (var i = 0; i < list.length; i++) out[root.providerTargetKey(list[i].kind, list[i].host, list[i].port)] = true
    return out
  }
  // Discovered devices that need no token and are not saved yet ("Add all found")
  readonly property var addableDiscovered: {
    var out = []
    var list = root.discoveredProviders || []
    for (var i = 0; i < list.length; i++) {
      var d = list[i] || {}
      var info = root.providerInfo(d.kind)
      if (!info || info.reqTok) continue
      if (root.existingProviderTargets[root.providerTargetKey(d.kind, d.host, d.port)]) continue
      out.push(d)
    }
    return out
  }
  function addAllDiscovered() {
    var list = root.addableDiscovered
    var room = root.provRoom.trim()
    for (var i = 0; i < list.length; i++) {
      var d = list[i]
      root.send({ cmd: "save_provider", provider: {
        id: "", kind: String(d.kind || ""), name: String(d.name || ""), host: String(d.host || ""),
        port: parseInt(d.port, 10) || null, room_name: room, token: "", pair_id: "", use_https: false, enabled: true
      } })
    }
    if (list.length > 0) root.providerFormOpen = false
  }
  function providerSetupHint(kind) {
    var keys = {
      home_assistant: "provHintHa", nanoleaf: "provHintNanoleaf", govee: "provHintGovee",
      dirigera: "provHintDirigera", wiz: "provHintWiz", lifx: "provHintLifx", wled: "provHintWled", shelly: "provHintShelly"
    }
    return keys[kind] ? root.t(keys[kind]) : ""
  }

  readonly property var extraProviderCatalog: [
    { kind: "home_assistant", name: "Home Assistant", badge: "HA", port: 8123, reqTok: true, pair: false, color: "#03A9F4" },
    { kind: "wled", name: "WLED", badge: "WLED", port: 80, reqTok: false, pair: false, color: "#EC4899" },
    { kind: "wiz", name: "WiZ", badge: "WiZ", port: 38899, reqTok: false, pair: false, color: "#8B5CF6" },
    { kind: "lifx", name: "LIFX", badge: "LIFX", port: 56700, reqTok: false, pair: false, color: "#10B981" },
    { kind: "govee", name: "Govee LAN", badge: "Govee", port: 4003, reqTok: false, pair: false, color: "#3B82F6" },
    { kind: "nanoleaf", name: "Nanoleaf", badge: "Nanoleaf", port: 16021, reqTok: true, pair: true, color: "#22C55E" },
    { kind: "shelly", name: "Shelly", badge: "Shelly", port: 80, reqTok: false, pair: false, color: "#06B6D4" },
    { kind: "dirigera", name: "IKEA DIRIGERA", badge: "IKEA", port: 8443, reqTok: true, pair: true, color: "#EAB308" }
  ]

  function providerInfo(kind) {
    for (var i = 0; i < extraProviderCatalog.length; i++) {
      if (extraProviderCatalog[i].kind === kind) return extraProviderCatalog[i]
    }
    return null
  }

  function openNewProvider(kind) {
    var k = kind || "home_assistant"
    var info = providerInfo(k) || extraProviderCatalog[0]
    root.provEditId = ""
    root.provKind = info.kind
    root.provName = ""
    root.provHost = ""
    root.provPort = String(info.port)
    root.provRoom = ""
    root.provToken = ""
    root.provPairId = ""
    root.provHttps = (info.kind === "dirigera")
    root.provHasSavedToken = false
    root.provAwaitingSave = false
    root.provOriginalHost = ""
    root.provOriginalPort = ""
    root.provOriginalKind = ""
    root.provHasCertFp = false
    root.provConfirmRemoveId = ""
    root.providerFormOpen = true
    root.send({ cmd: "clear_provider_action" })
    root.send({ cmd: "discover_providers" })
  }

  function openEditProvider(p) {
    if (!p) return
    root.provEditId = String(p.id || "")
    root.provKind = String(p.kind || "home_assistant")
    root.provName = String(p.name || "")
    root.provHost = String(p.host || "")
    root.provPort = String(p.port || "")
    root.provRoom = String(p.room_name || "")
    root.provToken = ""
    root.provPairId = ""
    root.provHttps = p.use_https === true
    root.provHasSavedToken = p.has_token === true
    root.provAwaitingSave = false
    root.provOriginalHost = root.provHost
    root.provOriginalPort = root.provPort
    root.provOriginalKind = root.provKind
    root.provHasCertFp = p.has_cert_fingerprint === true
    root.provConfirmRemoveId = ""
    root.providerFormOpen = true
    root.send({ cmd: "clear_provider_action" })
  }

  function buildProviderPayload() {
    var portNum = parseInt(root.provPort.trim(), 10)
    return {
      id: root.provEditId,
      kind: root.provKind,
      name: root.provName.trim(),
      host: root.provHost.trim(),
      port: isNaN(portNum) ? null : portNum,
      room_name: root.provRoom.trim(),
      token: root.provToken.trim(),
      pair_id: root.provPairId,
      use_https: root.provHttps,
      enabled: true
    }
  }

  onProviderActionChanged: {
    if (!root.providerFormOpen || !providerAction) return
    if (providerAction.kind === ("pair_" + root.provKind) && providerAction.ok && providerAction.pair_id) {
      root.provPairId = String(providerAction.pair_id)
    }
    if (root.provAwaitingSave && providerAction.kind === "save" && !providerAction.running) {
      root.provAwaitingSave = false
      if (providerAction.ok) {
        root.providerFormOpen = false
        root.provPairId = ""
      }
    }
  }

  // Navigation & transient UI state
  property string activeTab: "lights"          // lights | map | schedules | rules | synth
  property string lightFilter: "all"           // all | on | rooms | zones | favorites
  property var expanded: ({})                  // room key -> true while expanded
  property string openLightDrawer: ""          // light id whose color/warmth/themes drawer is open
  property string openLightMenu: ""            // light id whose ⋯ submenu is open
  property string lightDialog: ""              // "" | "brightness" | "rename" | "icon"
  property string lightDialogId: ""            // target light id for modal dialog
  property bool motionAwareHintDismissed: false
  property bool themeFieldFocused: false       // true while any inline "Save theme" field has focus
  property bool confirmUnpair: false
  property bool confirmAllOnPending: false
  property bool settingsOpen: false
  property bool infoOpen: false
  property bool helpOpen: false
  property bool aiOpen: false

  // New schedule builder state
  property bool showNewSchedule: false
  property string schedTargetKey: ""           // "<kind>:<id>"
  function validOptionValue(options, current, fallbackIndex) {
    if (!options || options.length === 0) return ""
    for (var i = 0; i < options.length; i++) if (options[i].value === current) return current
    var idx = fallbackIndex || 0
    return idx < options.length ? options[idx].value : options[0].value
  }
  property string schedTrigger: "time"         // time | sunrise | sunset
  property int schedOffsetMin: 0
  property var schedDays: []                   // subset of ["mon","tue","wed","thu","fri","sat","sun"]
  property string schedAction: "on"            // on | off | scene
  property string schedSceneId: ""
  property int schedBri: 80
  property int schedFadeMin: 0

  // New rule builder state
  property bool showNewRule: false
  property string ruleKind: "follow"           // follow | exclusive | companion
  property string ruleTriggerKey: ""           // "<kind>:<id>"
  property string ruleTriggerState: "on"       // on|off | motion|clear | open|closed | press|long_press
  property string ruleTargetKey: ""            // "<kind>:<id>"
  property bool ruleMirrorOff: true
  property bool ruleMatchBri: false
  property bool ruleOnlyIfOff: false

  // Interactive panel resize state
  property bool resizing: false
  property int dragWidth: 430
  property int dragHeight: 0
  property Item panelCard: null

  // Settings mirrored from BarWidget (shell.json)
  readonly property string lang: hostWidget ? hostWidget.lang : "en"
  readonly property string languageSetting: hostWidget ? hostWidget.languageSetting : "auto"
  readonly property string systemLang: hostWidget ? hostWidget.systemLang : "en"
  function t(key, args) { return I18n.tr(lang, key, args) }
  function tn(key, n, args) { return I18n.trn(lang, key, n, args) }

  readonly property string cornersSetting: hostWidget ? hostWidget.cornersSetting : "windows"
  readonly property var corners: Corners.sizes(cornersSetting, Style.cornerRadius)
  readonly property bool screenshotKey: hostWidget ? hostWidget.screenshotKey : true
  readonly property string barIconSetting: hostWidget ? hostWidget.barIconSetting : "bulb"
  readonly property bool showCountSetting: hostWidget ? hostWidget.showCountSetting : false
  readonly property string skinSetting: hostWidget ? hostWidget.skinSetting : "native"
  readonly property bool confirmAllOnSetting: hostWidget ? hostWidget.confirmAllOnSetting : false
  readonly property bool askAiSetting: hostWidget ? hostWidget.askAiSetting : false
  onAskAiSettingChanged: if (!askAiSetting) root.aiOpen = false
  readonly property string scheduleModeSetting: hostWidget ? hostWidget.scheduleModeSetting : String(stats.schedule_mode || "bridge")
  readonly property var favorites: hostWidget ? hostWidget.favoritesSetting : []
  readonly property var excludeAllOn: hostWidget ? hostWidget.excludeAllOnSetting : []
  readonly property int panelWidthSetting: hostWidget ? hostWidget.panelWidthSetting : 430
  readonly property int panelHeightSetting: hostWidget ? hostWidget.panelHeightSetting : 0
  readonly property int panelOffsetX: hostWidget ? hostWidget.panelOffsetXSetting : 0
  readonly property int panelOffsetY: hostWidget ? hostWidget.panelOffsetYSetting : 0

  readonly property int effectivePanelWidth: resizing ? dragWidth : panelWidthSetting
  readonly property int effectivePanelHeight: resizing ? dragHeight : panelHeightSetting

  readonly property real settingsLabelWidth: Style.space(138)
  readonly property real maxRoomListHeight: effectivePanelHeight > 0
    ? Math.max(Style.space(200), Style.space(effectivePanelHeight) - Style.space(220))
    : Style.space(460)
  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string font: root.bar ? root.bar.fontFamily : Style.font.family

  // Skin accent, tint wash & card borders (keeps "native" untouched and preserves PopupGlass)
  readonly property bool hasSkin: skinSetting !== "native"
  readonly property color accentColor: {
    switch (skinSetting) {
    case "synthwave": return "#ff2e93"
    case "cozy":      return "#f59e0b"
    case "terminal":  return "#22c55e"
    case "disco":     return "#a855f7"
    case "zen":       return "#5eead4"
    default:          return Commons.Color.accent
    }
  }
  readonly property real skinTintAlpha: {
    switch (skinSetting) {
    case "synthwave": return 0.15
    case "cozy":      return 0.14
    case "terminal":  return 0.12
    case "disco":     return 0.16
    case "zen":       return 0.12
    default:          return 0.0
    }
  }
  readonly property color skinCardBorder: hasSkin
    ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.28)
    : Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property color skinCardFill: hasSkin
    ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.07)
    : Qt.rgba(fg.r, fg.g, fg.b, 0.04)

  // Presets matching Maprisma Lights / Maprisma Hue
  readonly property var warmthPresets: [
    { key: "warmthCandle",   mirek: 500, color: "#ff9429" },
    { key: "warmthWarm",     mirek: 370, color: "#ffc97a" },
    { key: "warmthNeutral",  mirek: 250, color: "#ffedd9" },
    { key: "warmthDaylight", mirek: 154, color: "#d9ebff" }
  ]
  readonly property var colorPresets: [
    { xy: [0.675, 0.322], color: "#e53835" },
    { xy: [0.585, 0.388], color: "#fa8c00" },
    { xy: [0.505, 0.445], color: "#ffb300" },
    { xy: [0.215, 0.700], color: "#42a147" },
    { xy: [0.165, 0.360], color: "#00abc2" },
    { xy: [0.153, 0.048], color: "#1f87e5" },
    { xy: [0.272, 0.118], color: "#8f24ab" },
    { xy: [0.460, 0.215], color: "#e81f63" }
  ]
  readonly property var dayCodes: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
  readonly property var synthPaletteDefs: [
    { id: "neon",   key: "palNeon",   colors: ["#ff007f", "#00f5ff", "#8a2be2"] },
    { id: "sunset", key: "palSunset", colors: ["#ff4e50", "#fc913a", "#f9d423"] },
    { id: "ocean",  key: "palOcean",  colors: ["#005c97", "#00b4db", "#38ef7d"] },
    { id: "aurora", key: "palAurora", colors: ["#00f260", "#0575e6", "#7f00ff"] },
    { id: "fire",   key: "palFire",   colors: ["#ff1e00", "#ff6a00", "#ffb300"] },
    { id: "pastel", key: "palPastel", colors: ["#ffb3ba", "#bae1ff", "#e0bbff"] }
  ]

  // Filtered rooms for Lights tab
  readonly property var filteredRooms: {
    var list = root.rooms || []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var r = list[i]
      if (root.lightFilter === "on" && !r.on) continue
      if (root.lightFilter === "rooms" && r.kind !== "room" && r.kind !== "other") continue
      if (root.lightFilter === "zones" && r.kind !== "zone") continue
      if (root.lightFilter === "favorites") {
        var match = root.isFav("room:" + root.roomKey(r))
        if (!match) {
          var ls = r.lights || []
          for (var j = 0; j < ls.length; j++) {
            if (root.isFav("light:" + ls[j].id)) { match = true; break }
          }
        }
        if (!match) continue
      }
      out.push(r)
    }
    return out
  }

  // Resolved favorite items for the quick strip
  readonly property var favoriteItems: {
    var favs = root.favorites || []
    if (favs.length === 0) return []
    var out = []
    var seen = ({})
    for (var i = 0; i < favs.length; i++) {
      var key = favs[i]
      if (seen[key]) continue
      seen[key] = true
      if (key.indexOf("room:") === 0) {
        var rid = key.slice(5)
        for (var r = 0; r < root.rooms.length; r++) {
          if (root.roomKey(root.rooms[r]) === rid) {
            var rm = root.rooms[r]
            out.push({
              key: key, kind: "room", id: rid, room: rm,
              name: rm.kind === "other" ? root.t("otherLights") : rm.name,
              on: rm.on === true, color: rm.color || "#ffd27a"
            })
            break
          }
        }
      } else if (key.indexOf("light:") === 0) {
        var lid = key.slice(6)
        var found = false
        for (var r2 = 0; r2 < root.rooms.length && !found; r2++) {
          var ls = root.rooms[r2].lights || []
          for (var l = 0; l < ls.length; l++) {
            if (ls[l].id === lid) {
              out.push({
                key: key, kind: "light", id: lid, light: ls[l],
                name: ls[l].name, on: ls[l].on === true, color: ls[l].color || "#ffd27a"
              })
              found = true
              break
            }
          }
        }
      }
    }
    return out
  }

  // Schedule target options (rooms, zones, lights)
  readonly property var scheduleTargetOptions: {
    var out = []
    var seenLights = ({})
    for (var i = 0; i < root.rooms.length; i++) {
      var r = root.rooms[i]
      if (r.id && (r.kind === "room" || r.kind === "zone")) {
        out.push({
          value: r.kind + ":" + r.id,
          label: r.kind === "zone" ? (r.name + " (" + root.t("zone") + ")") : r.name
        })
      }
    }
    for (var j = 0; j < root.rooms.length; j++) {
      var rm = root.rooms[j]
      var rname = rm.kind === "other" ? root.t("otherLights") : rm.name
      var ls = rm.lights || []
      for (var k = 0; k < ls.length; k++) {
        var lt = ls[k]
        if (!lt.id || seenLights[lt.id]) continue
        seenLights[lt.id] = true
        out.push({ value: "light:" + lt.id, label: lt.name + (rname ? " · " + rname : "") })
      }
    }
    return out
  }

  // Scene options for currently chosen schedule target room/zone
  readonly property var scheduleSceneOptions: {
    var tkey = root.validOptionValue(root.scheduleTargetOptions, root.schedTargetKey, 0)
    var idx = tkey.indexOf(":")
    if (idx < 0) return []
    var tkind = tkey.slice(0, idx)
    var tid = tkey.slice(idx + 1)
    if (tkind !== "room" && tkind !== "zone") return []
    var out = []
    for (var i = 0; i < root.rooms.length; i++) {
      var r = root.rooms[i]
      if (r && r.kind === tkind && r.id === tid) {
        var scs = r.scenes || []
        for (var j = 0; j < scs.length; j++) {
          if (scs[j] && scs[j].id) out.push({ value: String(scs[j].id), label: String(scs[j].name || "") })
        }
        break
      }
    }
    return out
  }

  function openSceneSchedule(roomKind, roomId, sceneId, sceneName) {
    root.schedTargetKey = roomKind + ":" + roomId
    root.schedAction = "scene"
    root.schedSceneId = sceneId || ""
    schedNameField.text = sceneName || ""
    root.showNewSchedule = true
    root.activeTab = "schedules"
    root.confirmAllOnPending = false
  }

  // Rule target options (rooms and lights only; helper rejects zones/sensors as targets)
  readonly property var ruleEntityOptions: {
    var out = []
    var seenLights = ({})
    for (var i = 0; i < root.rooms.length; i++) {
      var r = root.rooms[i]
      if (r.id && r.kind === "room") {
        out.push({ value: "room:" + r.id, label: r.name })
      }
    }
    for (var j = 0; j < root.rooms.length; j++) {
      var rm = root.rooms[j]
      var rname = rm.kind === "other" ? root.t("otherLights") : rm.name
      var ls = rm.lights || []
      for (var k = 0; k < ls.length; k++) {
        var lt = ls[k]
        if (!lt.id || seenLights[lt.id]) continue
        seenLights[lt.id] = true
        out.push({ value: "light:" + lt.id, label: lt.name + (rname ? " · " + rname : "") })
      }
    }
    return out
  }

  // Rule trigger options: rooms & lights + Bridge Pro MotionAware areas + physical sensors
  readonly property var ruleTriggerOptions: {
    var out = root.ruleEntityOptions.slice()
    var areas = root.motionAreas || []
    for (var a = 0; a < areas.length; a++) {
      var ma = areas[a]
      if (ma && ma.id) {
        out.push({ value: "motion_area:" + ma.id, label: String(ma.name || "") + " · " + root.t("motionAwareTitle") })
      }
    }
    var sens = root.sensors || []
    for (var s = 0; s < sens.length; s++) {
      var sn = sens[s]
      if (sn && sn.id && sn.kind) {
        out.push({ value: sn.kind + ":" + sn.id, label: String(sn.name || "") + " · " + root.sensorKindLabel(sn.kind) })
      }
    }
    return out
  }

  function sensorKindLabel(kind) {
    if (kind === "motion") return root.t("sensorKindMotion")
    if (kind === "contact") return root.t("sensorKindContact")
    if (kind === "button") return root.t("sensorKindButton")
    if (kind === "motion_area") return root.t("motionAwareTitle")
    return String(kind || "")
  }

  function triggerKindOf(key) {
    var s = String(key || "")
    var idx = s.indexOf(":")
    return idx > 0 ? s.slice(0, idx) : "light"
  }

  function triggerStateChoices(tkind) {
    if (tkind === "motion" || tkind === "motion_area") {
      return [
        { id: "motion", key: "trigMotionDetected" },
        { id: "clear",  key: "trigNoMotion" }
      ]
    }
    if (tkind === "contact") {
      return [
        { id: "open",   key: "trigOpens" },
        { id: "closed", key: "trigCloses" }
      ]
    }
    if (tkind === "button") {
      return [
        { id: "press",      key: "trigPressed" },
        { id: "long_press", key: "trigLongPress" }
      ]
    }
    return [
      { id: "on",  key: "mapTriggerTurnsOn" },
      { id: "off", key: "mapTriggerTurnsOff" }
    ]
  }

  function triggerStateLabel(tkind, st) {
    var choices = triggerStateChoices(tkind)
    for (var i = 0; i < choices.length; i++) {
      if (choices[i].id === st) return root.t(choices[i].key)
    }
    return String(st || "")
  }

  function roomMotionActive(room) {
    if (!room || room.kind === "zone") return false
    var areas = root.motionAreas || []
    if (room.id) {
      for (var i = 0; i < areas.length; i++) {
        var a = areas[i]
        if (a && a.room_id === room.id && a.enabled === true && a.motion === true) return true
      }
    }
    var ls = room.lights || []
    for (var j = 0; j < ls.length; j++) {
      if (ls[j] && ls[j].motion_active === true) return true
    }
    return false
  }

  // Bridge Pro MotionAware™ ready hint (rooms with 3+ lights, hidden if not Pro or areas exist)
  readonly property var motionAwareEligibleRooms: {
    var out = []
    var list = root.rooms || []
    for (var i = 0; i < list.length; i++) {
      var r = list[i]
      if (r && r.kind === "room" && (r.lights || []).length >= 3) out.push(String(r.name || ""))
    }
    return out
  }
  readonly property bool showMotionAwareHint: root.paired
    && root.bridge && root.bridge.is_pro === true
    && (!root.motionAreas || root.motionAreas.length === 0)
    && !root.motionAwareHintDismissed

  // Lookup light by id for Lights tab modals
  readonly property var lightDialogTarget: {
    if (!root.lightDialogId) return null
    var rs = root.rooms || []
    for (var i = 0; i < rs.length; i++) {
      var ls = (rs[i] && rs[i].lights) ? rs[i].lights : []
      for (var j = 0; j < ls.length; j++) {
        if (ls[j] && ls[j].id === root.lightDialogId) return ls[j]
      }
    }
    return null
  }
  readonly property real lightModalMinHeight: {
    if (root.lightDialog === "icon") return lightIconDlgCol.implicitHeight + Style.space(52)
    if (root.lightDialog === "brightness") return lightBriDlgCol.implicitHeight + Style.space(52)
    if (root.lightDialog === "rename") return lightRenDlgCol.implicitHeight + Style.space(52)
    return 0
  }

  function lightIconFor(lid) {
    if (!lid) return "bulb"
    return mapTab ? mapTab.lampIconFor(lid) : "bulb"
  }
  function lightContrastTint(lt) {
    if (!lt || !lt.on) return Qt.rgba(1, 1, 1, 0.72)
    var c = Qt.color(lt.color || "#ffd27a")
    var luma = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    return luma > 0.56 ? "#141820" : "#ffffff"
  }
  function openLightBrightnessDialog(lid) {
    if (!lid) return
    root.openLightMenu = ""
    root.lightDialogId = lid
    root.lightDialog = "brightness"
  }
  function openLightRenameDialog(lid) {
    if (!lid) return
    root.openLightMenu = ""
    root.lightDialogId = lid
    var lt = root.lightDialogTarget
    lightRenameField.text = lt ? String(lt.name || "") : ""
    lightRenameField.cursorPosition = lightRenameField.text.length
    root.lightDialog = "rename"
    Qt.callLater(function() { lightRenameField.forceActiveFocus() })
  }
  function openLightIconDialog(lid) {
    if (!lid) return
    root.openLightMenu = ""
    root.lightDialogId = lid
    root.lightDialog = "icon"
  }
  function closeLightDialog() {
    root.lightDialog = ""
    root.lightDialogId = ""
    keyCatcher.forceActiveFocus()
  }
  function closeLightsTransient() {
    if (root.lightDialog !== "") {
      root.closeLightDialog()
      return true
    }
    if (root.openLightMenu !== "") {
      root.openLightMenu = ""
      return true
    }
    if (root.openLightDrawer !== "") {
      root.openLightDrawer = ""
      root.themeFieldFocused = false
      return true
    }
    return false
  }
  function wireLightOnMap(lid) {
    root.openLightMenu = ""
    root.lightDialog = ""
    root.lightDialogId = ""
    root.confirmAllOnPending = false
    root.activeTab = "map"
    mapTab.startWireFromLight(lid)
  }

  // Synth room dropdown options
  readonly property var synthRoomOptions: {
    var out = [{ value: "", label: root.t("synthAllRooms") }]
    for (var i = 0; i < root.rooms.length; i++) {
      var r = root.rooms[i]
      if (r.id && (r.kind === "room" || r.kind === "zone")) {
        out.push({
          value: r.id,
          label: r.kind === "zone" ? (r.name + " (" + root.t("zone") + ")") : r.name
        })
      }
    }
    return out
  }

  // Helper functions
  function send(obj) { if (root.hostWidget) root.hostWidget.send(obj) }
  function filteredRoomAt(i) { return i < filteredRooms.length ? filteredRooms[i] : ({ lights: [], scenes: [] }) }
  function roomKey(room) { return room.id || room.kind }
  function isFav(key) { return (root.favorites || []).indexOf(key) >= 0 }
  function isExcluded(roomId) { return (root.excludeAllOn || []).indexOf(roomId) >= 0 }
  function toggleExpanded(room) {
    var next = Object.assign({}, expanded)
    next[roomKey(room)] = !next[roomKey(room)]
    expanded = next
  }
  function setRoom(room, fields) {
    if (room.grouped_light) {
      send(Object.assign({ cmd: "group", id: room.grouped_light }, fields))
    } else {
      for (var i = 0; i < room.lights.length; i++)
        send(Object.assign({ cmd: "light", id: room.lights[i].id }, fields))
    }
  }
  function clampMirek(light, m) {
    var lo = Number(light.mirek_min || 153)
    var hi = Number(light.mirek_max || 500)
    return Math.max(lo, Math.min(hi, Math.round(m)))
  }
  function effectLabel(eff) {
    switch (eff) {
    case "no_effect":  return root.t("effNone")
    case "candle":     return root.t("effCandle")
    case "fire":       return root.t("effFire")
    case "sparkle":    return root.t("effSparkle")
    case "prism":      return root.t("effPrism")
    case "opal":       return root.t("effOpal")
    case "glisten":    return root.t("effGlisten")
    case "underwater": return root.t("effUnderwater")
    case "cosmos":     return root.t("effCosmos")
    case "sunbeam":    return root.t("effSunbeam")
    case "enchant":    return root.t("effEnchant")
    default:
      var s = String(eff || "").replace(/_/g, " ")
      return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : root.t("effNone")
    }
  }
  function themeLabel(th) {
    if (th.built_in) {
      switch (th.id) {
      case "reading":    return root.t("themeReading")
      case "relax":      return root.t("themeRelax")
      case "focus":      return root.t("themeFocus")
      case "sunset":     return root.t("themeSunset")
      case "ocean":      return root.t("themeOcean")
      case "cyberpunk":  return root.t("themeCyberpunk")
      case "fireplace":  return root.t("themeFireplace")
      case "nightlight": return root.t("themeNightlight")
      }
    }
    return String(th.name || "")
  }
  function dayLabel(code) {
    switch (code) {
    case "mon": return root.t("dayMon")
    case "tue": return root.t("dayTue")
    case "wed": return root.t("dayWed")
    case "thu": return root.t("dayThu")
    case "fri": return root.t("dayFri")
    case "sat": return root.t("daySat")
    case "sun": return root.t("daySun")
    default:    return code
    }
  }
  function validHHMM(str) {
    return /^([01]\d|2[0-3]):([0-5]\d)$/.test(String(str || "").trim())
  }
  function resolveEntityName(kind, id) {
    if (kind === "room" || kind === "zone") {
      for (var i = 0; i < root.rooms.length; i++) {
        if (root.rooms[i].id === id) return root.rooms[i].name
      }
    } else if (kind === "motion_area") {
      var areas = root.motionAreas || []
      for (var a = 0; a < areas.length; a++) {
        if (areas[a] && areas[a].id === id) return areas[a].name
      }
    } else if (kind === "motion" || kind === "contact" || kind === "button") {
      var sens = root.sensors || []
      for (var s = 0; s < sens.length; s++) {
        if (sens[s] && sens[s].id === id) return sens[s].name
      }
    }
    for (var j = 0; j < root.rooms.length; j++) {
      var ls = root.rooms[j].lights || []
      for (var k = 0; k < ls.length; k++) {
        if (ls[k].id === id) return ls[k].name
      }
    }
    return String(id || "").slice(0, 8)
  }
  function formatScheduleSummary(sched) {
    var parts = []
    if (sched.target_name) parts.push(sched.target_name)
    else if (sched.target_id) parts.push(resolveEntityName(sched.target_kind, sched.target_id))
    if (sched.trigger_kind === "sunrise") {
      var off1 = Number(sched.offset_min || 0)
      parts.push(root.t("triggerSunrise") + (off1 !== 0 ? (" " + (off1 > 0 ? "+" : "") + off1 + "m") : ""))
    } else if (sched.trigger_kind === "sunset") {
      var off2 = Number(sched.offset_min || 0)
      parts.push(root.t("triggerSunset") + (off2 !== 0 ? (" " + (off2 > 0 ? "+" : "") + off2 + "m") : ""))
    } else {
      parts.push(String(sched.time || "00:00"))
    }
    var ds = sched.days || []
    parts.push(ds.length === 0 || ds.length === 7 ? root.t("everyDay") : ds.map(dayLabel).join(" "))
    if (sched.action === "off") parts.push(root.t("actionOff"))
    else if (sched.action === "scene") parts.push(root.t("recallScene"))
    else parts.push(root.t("actionOn") + (sched.bri !== null && sched.bri !== undefined ? (" " + Math.round(Number(sched.bri)) + "%") : ""))
    if (Number(sched.fade_min || 0) > 0) parts.push(root.t("fadeMin", [sched.fade_min]))
    return parts.join(" · ")
  }
  function ruleKindLabel(kind) {
    if (kind === "exclusive") return root.t("ruleExclusive")
    if (kind === "companion") return root.t("ruleCompanion")
    if (kind === "sensor") return root.t("ruleSensor")
    return root.t("ruleFollow")
  }
  function formatRuleSummary(rule) {
    var trig = resolveEntityName(rule.trigger_kind, rule.trigger_id)
    if (rule.trigger_kind === "motion" || rule.trigger_kind === "motion_area" || rule.trigger_kind === "contact" || rule.trigger_kind === "button") {
      trig += " (" + triggerStateLabel(rule.trigger_kind, rule.trigger_state) + ")"
    }
    var targs = rule.targets || []
    var tnames = []
    for (var i = 0; i < targs.length; i++) {
      var act = targs[i].action === "off" ? root.t("actionOff") : root.t("actionOn")
      tnames.push(resolveEntityName(targs[i].kind, targs[i].id) + " (" + act + ")")
    }
    var line = trig + " → " + tnames.join(", ")
    var extras = []
    if (rule.mirror_off) extras.push(root.t("mirrorOff"))
    if (rule.match_bri) extras.push(root.t("matchBri"))
    if (rule.only_if_off) extras.push(root.t("onlyIfOff"))
    if (rule.time_start && rule.time_end) extras.push(rule.time_start + "–" + rule.time_end)
    if (extras.length > 0) line += " · " + extras.join(", ")
    return line
  }
  function formatLogTime(ts) {
    var d = new Date(Number(ts || 0) * 1000)
    var hh = String(d.getHours()).padStart(2, "0")
    var mm = String(d.getMinutes()).padStart(2, "0")
    var ss = String(d.getSeconds()).padStart(2, "0")
    return hh + ":" + mm + ":" + ss
  }

  function roomIcon(room) {
    if (room.kind === "zone") return "󰌨"
    if (room.kind === "other") return "󰌵"
    var name = String(room.name || "").toLowerCase()
    var byName = [
      [/schlaf|bed|kinder|gäste|guest|nursery/, "󰋣"],
      [/küche|kueche|kitchen|ess|dining/, "󰩰"],
      [/bad|bath|wc|toilet|dusche/, "󰦠"],
      [/büro|buero|office|arbeit|studio/, "󰌢"],
      [/flur|diele|treppe|hall|stair|eingang/, "󰓍"],
      [/garage|carport/, "󰛙"],
      [/garten|terrasse|balkon|garden|terrace|balcony|patio|außen|outdoor/, "󰔱"],
      [/wohn|living|lounge|tv/, "󰒹"]
    ]
    for (var i = 0; i < byName.length; i++) if (byName[i][0].test(name)) return byName[i][1]
    switch (room.archetype) {
    case "living_room": case "lounge": case "tv": return "󰒹"
    case "kitchen": case "dining": return "󰩰"
    case "bedroom": case "kids_bedroom": case "guest_room": case "nursery": return "󰋣"
    case "bathroom": case "toilet": return "󰦠"
    case "office": case "computer": case "studio": return "󰌢"
    case "hallway": case "staircase": case "top_floor": case "upstairs": case "downstairs": return "󰓍"
    case "garage": case "carport": case "driveway": return "󰛙"
    case "garden": case "terrace": case "balcony": case "porch": case "barbecue": case "pool": case "front_door": return "󰔱"
    default: return "󰋜"
    }
  }
  function roomStatus(room, unreachable) {
    var total = room.lights.length
    var parts = []
    if (room.kind === "zone") parts.push(t("zone"))
    parts.push(room.on ? t("ofOn", [room.on_count, total]) : tn("offLights", total))
    if (unreachable > 0) parts.push(t("unreachableN", [unreachable]))
    if (room.kind === "room" && root.isExcluded(room.id)) parts.push(t("excludedBadge"))
    return parts.join(" · ")
  }
  function onTint(c) {
    var luma = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    return luma > 0.6 ? "#1a1a1a" : "#ffffff"
  }
  function scrollRooms(wheel) {
    var f = roomScroller
    if (f.contentHeight <= f.height) return
    f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY - wheel.angleDelta.y * 0.6))
  }
  function findCard() {
    for (var it = shot ? shot.parent : null; it; it = it.parent) {
      if (it.borderSpec !== undefined && it.padding !== undefined && it.color !== undefined && it.radius !== undefined)
        return it
    }
    return null
  }
  function barGlyph(lit) {
    return hostWidget ? hostWidget.barIconGlyph(barIconSetting, lit) : (lit ? "󰛨" : "󰌵")
  }

  function open() { root.controller.show() }
  function close() {
    root.aiOpen = false
    root.helpOpen = false
    helpPage.selectedIndex = -1
    root.infoOpen = false
    root.settingsOpen = false
    root.confirmUnpair = false
    root.confirmAllOnPending = false
    root.themeFieldFocused = false
    root.openLightMenu = ""
    root.lightDialog = ""
    root.lightDialogId = ""
    mapTab.resetTransient()
    root.controller.hide()
  }

  // Reusable 1:1 vector lamp icon glyph (mirrors MapTab's drawLampIcon)
  component LightLampGlyph: Canvas {
    id: lGlyph
    property string iconName: "bulb"
    property color tint: root.fg
    property int version: mapTab ? mapTab.iconVersion : 0
    width: Style.space(13)
    height: Style.space(13)
    onIconNameChanged: requestPaint()
    onTintChanged: requestPaint()
    onVersionChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onAvailableChanged: if (available) requestPaint()
    Component.onCompleted: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (mapTab) mapTab.drawLampIcon(ctx, iconName, width / 2, height / 2, Math.min(width, height), tint)
    }
  }
  function submitAiPrompt(textOverride) {
    var p = (textOverride !== undefined ? String(textOverride) : aiPromptField.text).trim()
    if (!p || root.aiState.busy === true) return
    aiPromptField.text = p
    root.send({ cmd: "ai_ask", prompt: p })
  }
  function toggle() { if (root.opened) root.close(); else root.open() }

  // Reusable PageTab (matches omarchy-widget-layout / WLAN Monitor)
  component PageTab: Item {
    id: tab
    property string label: ""
    property string icon: ""
    property bool active: false
    signal activated()
    implicitWidth: tabText.implicitWidth + Style.space(12)
    implicitHeight: tabText.implicitHeight + Style.space(10)
    Text {
      id: tabText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: tab.icon + "  " + tab.label
      color: tab.active ? root.accentColor : (tabMouse.containsMouse ? root.fg : root.dim)
      font.family: root.font
      font.pixelSize: Style.font.bodySmall
      font.bold: tab.active
    }
    Rectangle {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - Style.space(6)
      height: Style.space(2)
      radius: Math.min(root.corners.small, 1)
      color: root.accentColor
      visible: tab.active
    }
    MouseArea {
      id: tabMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tab.activated()
    }
  }

  // Reusable Meter (matches omarchy-widget-layout / LLM Monitor)
  component Meter: Column {
    id: meter
    property string label: ""
    property real ratio: 0
    property color fillColor: root.accentColor
    width: parent ? parent.width : Style.space(200)
    spacing: Style.space(3)
    Item {
      width: parent.width
      height: meterLbl.implicitHeight
      Text {
        id: meterLbl
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: meter.label
        color: root.dim
        font.family: root.font
        font.pixelSize: Style.font.caption
      }
      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: Math.round(Math.max(0, Math.min(1, meter.ratio)) * 100) + "%"
        color: root.fg
        font.family: root.font
        font.pixelSize: Style.font.caption
      }
    }
    Rectangle {
      width: parent.width
      height: Style.space(5)
      radius: Math.min(root.corners.small, height / 2)
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
      Rectangle {
        width: Math.round(parent.width * Math.max(0, Math.min(1, meter.ratio)))
        height: parent.height
        radius: parent.radius
        color: meter.fillColor
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      }
    }
  }

  // See-through with the window style (Theme Manager → Settings).
  PopupGlass { inside: shot; active: panel.open }

  // Apply optional saved horizontal offset cleanly without breaking KeyboardPanel's default anchored layout
  Binding {
    target: root.panelCard
    property: "x"
    when: root.panelCard !== null && root.panelOffsetX !== 0 && panel.morph >= 1
    value: Math.round(Math.max(panel.margin, Math.min(panel.cardOrigin.x + root.panelOffsetX, panel.screenW - panel.contentWidth - panel.margin)))
    restoreMode: Binding.RestoreBindingOrValue
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    gap: Math.max(Style.gapsOut, Style.gapsOut + root.panelOffsetY)
    contentWidth: panel.fittedContentWidth(Style.space(root.effectivePanelWidth))
    contentHeight: root.effectivePanelHeight > 0
      ? panel.cappedContentHeight(Math.max(Style.space(root.effectivePanelHeight), root.lightModalMinHeight, shot.neededHeight + panel.verticalContentInset))
      : panel.fittedContentHeight(Math.max(column.implicitHeight, root.lightModalMinHeight, shot.neededHeight))
    onOpenChanged: {
      if (open && !root.panelCard) root.panelCard = root.findCard()
    }

    // F12: a screenshot of this panel into ~/Pictures/Lights, then an optional note
    PanelShot {
      id: shot
      anchors.fill: parent
      pluginId: "ubruckhaus.lights"
      folderName: "Lights"
      active: root.screenshotKey
      panelOpen: root.opened
      returnFocus: keyCatcher
      lang: root.lang
      fg: root.fg
      dim: root.dim
      fontFamily: root.font
      corners: root.corners

      // Skin wash, crisp accent border & header glow inside the panel card (preserves PopupGlass)
      Rectangle {
        anchors.fill: parent
        radius: root.corners.radius
        visible: root.hasSkin
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, root.skinTintAlpha)
        border.width: 1
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.42)
        clip: true

        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(52)
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }
        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(2)
          color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.78)
        }
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: shot.overlayOpen
          || manualIp.activeFocus
          || aiPromptField.activeFocus
          || lightRenameField.activeFocus
          || root.themeFieldFocused
          || schedNameField.activeFocus
          || schedTimeField.activeFocus
          || ruleNameField.activeFocus
          || ruleStartField.activeFocus
          || ruleEndField.activeFocus
          || languagePicker.popupOpen
          || schedModePicker.popupOpen
          || skinPicker.popupOpen
          || barIconPicker.popupOpen
          || cornersPicker.popupOpen
          || schedTargetPicker.popupOpen
          || schedScenePicker.popupOpen
          || ruleTriggerPicker.popupOpen
          || ruleTargetPicker.popupOpen
          || synthRoomPicker.popupOpen
          || mapTab.inputBlocked
          || root.providerFormOpen
        onCloseRequested: {
          if (root.providerFormOpen) root.providerFormOpen = false
          else if (root.aiOpen) root.aiOpen = false
          else if (root.helpOpen) {
            if (helpPage.selectedIndex >= 0) helpPage.selectedIndex = -1
            else root.helpOpen = false
          }
          else if (root.infoOpen) root.infoOpen = false
          else if (root.settingsOpen) root.settingsOpen = false
          else if (root.activeTab === "lights" && root.closeLightsTransient()) return
          else if (root.activeTab === "map" && mapTab.closeTransient()) return
          else root.close()
        }
        onTextKey: function(text) {
          if (text === "\b" && root.aiOpen) { root.aiOpen = false; return }
          if (text === "\b" && root.helpOpen) {
            if (helpPage.selectedIndex >= 0) helpPage.selectedIndex = -1
            else root.helpOpen = false
            return
          }
          if (text === "\b" && root.infoOpen) { root.infoOpen = false; return }
          if (text === "\b" && root.settingsOpen) root.settingsOpen = false
        }
        onTabRequested: function(direction) { root.switchPanel(direction) }

        Flickable {
          id: scroller
          anchors.fill: parent
          contentWidth: width
          contentHeight: column.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: column
            width: scroller.width
            spacing: Style.space(10)

            PanelHero {
              foreground: root.fg
              fontFamily: root.font
              title: "Lights"
              meta: root.paired
                ? (root.bridge.name || "Hue Bridge") + (root.bridge.ip ? " · " + root.bridge.ip : "")
                : root.t("noBridge")
              detail: root.phase === "ok" ? root.t("ofOn", [Number(root.stats.on_count || 0), Number(root.stats.light_count || 0)]) : ""
              trailingControl: Component {
                Item {
                  visible: !root.settingsOpen && !root.infoOpen && !root.helpOpen && !root.aiOpen
                  implicitWidth: gearButton.x + gearButton.width
                  implicitHeight: heroTitle.implicitHeight + Style.space(2) + heroMeta.implicitHeight
                  Text { id: heroTitle; visible: false; textFormat: Text.PlainText; text: "W"; font.family: root.font; font.pixelSize: Style.font.title; font.bold: true }
                  Text { id: heroBody; visible: false; textFormat: Text.PlainText; text: "W"; font.family: root.font; font.pixelSize: Style.font.body; font.bold: true }
                  Text { id: heroMeta; visible: false; textFormat: Text.PlainText; text: "W"; font.family: root.font; font.pixelSize: Style.font.caption; font.bold: true }
                  Button {
                    id: infoButton
                    radius: root.corners.control
                    x: 0
                    y: gearButton.y
                    height: gearButton.height
                    width: height
                    iconText: "\u{F02FC}"
                    bordered: true
                    iconSize: Style.font.body
                    horizontalPadding: Style.space(4)
                    verticalPadding: Style.space(1)
                    foreground: root.fg
                    fontFamily: root.font
                    tooltipText: root.t("information")
                    onClicked: root.infoOpen = true
                  }
                  Button {
                    id: helpButton
                    radius: root.corners.control
                    x: infoButton.x + infoButton.width + Style.space(6)
                    y: gearButton.y
                    height: gearButton.height
                    width: height
                    iconText: "?"
                    bordered: true
                    iconSize: Style.font.body
                    horizontalPadding: Style.space(4)
                    verticalPadding: Style.space(1)
                    foreground: root.fg
                    fontFamily: root.font
                    tooltipText: root.t("helpGuide")
                    onClicked: { helpPage.selectedIndex = -1; root.helpOpen = true }
                  }
                  Button {
                    id: aiButton
                    visible: root.askAiSetting
                    radius: root.corners.control
                    x: helpButton.x + helpButton.width + Style.space(6)
                    y: gearButton.y
                    height: gearButton.height
                    width: height
                    iconText: "✦"
                    bordered: true
                    iconSize: Style.font.body
                    horizontalPadding: Style.space(4)
                    verticalPadding: Style.space(1)
                    foreground: root.accentColor
                    fontFamily: root.font
                    tooltipText: root.t("askAi")
                    onClicked: root.aiOpen = true
                  }
                  Button {
                    id: gearButton
                    radius: root.corners.control
                    x: (aiButton.visible ? (aiButton.x + aiButton.width) : (helpButton.x + helpButton.width)) + Style.space(6)
                    y: Math.round((heroTitle.implicitHeight - height) / 2)
                    height: heroBody.implicitHeight + Style.space(4)
                    width: height
                    iconText: "\udb81\udc93"
                    bordered: true
                    iconSize: Style.font.body
                    horizontalPadding: Style.space(4)
                    verticalPadding: Style.space(1)
                    foreground: root.fg
                    fontFamily: root.font
                    tooltipText: root.t("settings")
                    onClicked: { root.confirmUnpair = false; root.confirmAllOnPending = false; root.settingsOpen = true }
                  }
                }
              }
              iconComponent: Component {
                Text {
                  textFormat: Text.PlainText
                  text: root.barGlyph(Number(root.stats.on_count || 0) > 0)
                  color: Number(root.stats.on_count || 0) > 0 ? root.accentColor : root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.display
                }
              }
            }

            Item {
              visible: errorLine.text !== ""
              width: parent.width
              height: Math.max(errorLine.implicitHeight, retryBtn.implicitHeight)
              Text {
                id: errorLine
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: retryBtn.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                text: root.hostWidget ? root.hostWidget.errorText() : String(root.stats.error || "")
                color: Commons.Color.urgent
                font.family: root.font
                font.pixelSize: Style.font.caption
              }
              Button {
                id: retryBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                radius: root.corners.control
                text: root.t("retry")
                bordered: true
                foreground: root.fg
                fontFamily: root.font
                onClicked: root.send({ cmd: "refresh" })
              }
            }

            // ---------------------------------------------------------------- ask ai (optional, off by default)
            Column {
              id: askAiPage
              visible: root.aiOpen && root.askAiSetting
              width: parent.width
              spacing: Style.space(10)

              PanelSeparator { width: parent.width; foreground: root.fg }

              Row {
                spacing: Style.space(12)
                Button {
                  radius: root.corners.control
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.t("back") + " · ⌫"
                  iconText: "󰁍"
                  bordered: true
                  foreground: root.fg
                  fontFamily: root.font
                  tooltipText: root.t("backTip")
                  onClicked: root.aiOpen = false
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "✦  " + root.t("askAi").toUpperCase()
                  color: root.fg
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                }
              }

              PanelSeparator { width: parent.width; foreground: root.fg }

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.t("askAiSubtitle")
                color: root.dim
                font.family: root.font
                font.pixelSize: Style.font.caption
              }

              Item {
                width: parent.width
                height: Math.max(aiPromptField.implicitHeight, aiSendButton.implicitHeight)
                KeyTextField {
                  id: aiPromptField
                  radius: root.corners.control
                  maximumLength: 500
                  anchors.left: parent.left
                  anchors.right: aiSendButton.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: root.t("askAiPlaceholder")
                  foreground: root.fg
                  accent: root.accentColor
                  font: Qt.font({ family: root.font, pixelSize: Style.font.bodySmall })
                  onAccepted: root.submitAiPrompt()
                  Keys.onEscapePressed: root.aiOpen = false
                }
                Button {
                  id: aiSendButton
                  radius: root.corners.control
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.t("askAiSend")
                  iconText: "✦"
                  bordered: true
                  foreground: root.accentColor
                  fontFamily: root.font
                  enabled: root.aiState.busy !== true && aiPromptField.text.trim() !== ""
                  onClicked: root.submitAiPrompt()
                }
              }

              // 4 clickable quick example chips
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.t("askAiExamples")
                color: root.dim
                font.family: root.font
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Flow {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: ["askAiChip1", "askAiChip2", "askAiChip3", "askAiChip4"]
                  delegate: Button {
                    required property string modelData
                    radius: root.corners.pill > 0 ? root.corners.pill : root.corners.control
                    text: root.t(modelData)
                    bordered: true
                    foreground: root.fg
                    fontFamily: root.font
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(3)
                    enabled: root.aiState.busy !== true
                    onClicked: root.submitAiPrompt(root.t(modelData))
                  }
                }
              }

              // Live status / response / actions / error card
              Rectangle {
                readonly property bool hasActions: Array.isArray(root.aiState.last_actions) && root.aiState.last_actions.length > 0
                readonly property bool hasContent: root.aiState.busy === true
                  || String(root.aiState.last_reply || "") !== ""
                  || String(root.aiState.error || "") !== ""
                  || hasActions
                visible: hasContent
                width: parent.width
                height: aiStatusCol.implicitHeight + Style.space(16)
                radius: root.corners.radius
                color: root.skinCardFill
                border.width: 1
                border.color: String(root.aiState.error || "") !== ""
                  ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.45)
                  : root.skinCardBorder

                Column {
                  id: aiStatusCol
                  x: Style.space(10)
                  y: Style.space(8)
                  width: parent.width - Style.space(20)
                  spacing: Style.space(6)

                  // Header row: busy or engine label + Clear button
                  Item {
                    width: parent.width
                    height: Math.max(aiEngineText.implicitHeight, aiClearBtn.implicitHeight)
                    Text {
                      id: aiEngineText
                      anchors.left: parent.left
                      anchors.right: aiClearBtn.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      text: root.aiState.busy === true
                        ? ("✦ " + root.t("askAiThinking"))
                        : (String(root.aiState.engine || "") === "ollama"
                            ? ("✦ " + root.t("askAiEngineOllama"))
                            : (String(root.aiState.engine || "") !== "" ? ("✦ " + root.t("askAiEngineBuiltin")) : ""))
                      color: root.accentColor
                      font.family: root.font
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    Button {
                      id: aiClearBtn
                      radius: root.corners.control
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.t("askAiClear")
                      bordered: true
                      foreground: root.fg
                      fontFamily: root.font
                      fontSize: Style.font.caption
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(2)
                      onClicked: {
                        aiPromptField.clear()
                        root.send({ cmd: "ai_clear" })
                      }
                    }
                  }

                  Text {
                    visible: String(root.aiState.last_prompt || "") !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: "“" + String(root.aiState.last_prompt || "") + "”"
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    visible: String(root.aiState.last_reply || "") !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: String(root.aiState.last_reply || "")
                    color: root.fg
                    font.family: root.font
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    visible: String(root.aiState.error || "") !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: String(root.aiState.error || "")
                    color: Commons.Color.urgent
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }

                  Column {
                    visible: Array.isArray(root.aiState.last_actions) && root.aiState.last_actions.length > 0
                    width: parent.width
                    spacing: Style.space(3)
                    Text {
                      textFormat: Text.PlainText
                      text: root.t("askAiActions")
                      color: root.dim
                      font.family: root.font
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    Repeater {
                      model: Array.isArray(root.aiState.last_actions) ? root.aiState.last_actions : []
                      delegate: Text {
                        required property var modelData
                        width: aiStatusCol.width
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: "• " + String(modelData)
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }
              }
            }

            // ---------------------------------------------------------------- help & guide
            HelpPage {
              id: helpPage
              visible: root.helpOpen
              width: parent.width
              fg: root.fg
              dim: root.dim
              accentColor: root.accentColor
              hasSkin: root.hasSkin
              fontFamily: root.font
              corners: root.corners
              lang: root.lang
              onBackRequested: {
                if (helpPage.selectedIndex >= 0) helpPage.selectedIndex = -1
                else root.helpOpen = false
              }
              onTryFeature: function(target) {
                helpPage.selectedIndex = -1
                root.helpOpen = false
                root.infoOpen = false
                root.aiOpen = false
                root.confirmAllOnPending = false
                root.openLightMenu = ""
                root.lightDialog = ""
                root.lightDialogId = ""
                if (target === "settings") {
                  root.settingsOpen = true
                } else {
                  root.settingsOpen = false
                  if (target === "map_rules") {
                    root.activeTab = "map"
                    mapTab.toolMode = "wire"
                  } else if (target === "map") {
                    root.activeTab = "map"
                    mapTab.toolMode = "select"
                  } else if (target === "schedules" || target === "synth" || target === "lights") {
                    root.activeTab = target
                  }
                }
                scroller.contentY = 0
              }
            }

            // ---------------------------------------------------------------- information
            Column {
              visible: root.infoOpen
              width: parent.width
              spacing: Style.space(12)

              PanelSeparator { width: parent.width; foreground: root.fg }

              Row {
                spacing: Style.space(12)
                Button {
                  radius: root.corners.control
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.t("back") + " · \u232b"
                  iconText: "\udb80\udc4d"
                  bordered: true
                  foreground: root.fg
                  fontFamily: root.font
                  tooltipText: root.t("backTip")
                  onClicked: root.infoOpen = false
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.t("information").toUpperCase()
                  color: root.fg
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                }
              }
              PanelSeparator { width: parent.width; foreground: root.fg }

              MorePlugins {
                tileRadius: root.corners.control
                cardRadius: root.corners.radius
                width: parent.width
                separated: false
                ownId: "ubruckhaus.lights"
                catalogScript: decodeURIComponent(Qt.resolvedUrl("plugin_catalog.py").toString().replace(/^file:\/\//, ""))
                lang: root.lang
                fg: root.fg
                dim: root.dim
                fontFamily: root.font
                onOpened: root.close()
              }
            }

            // ---------------------------------------------------------------- settings
            Column {
              visible: root.settingsOpen
              width: parent.width
              spacing: Style.space(12)

              PanelSeparator { width: parent.width; foreground: root.fg }

              Row {
                spacing: Style.space(12)
                Button {
                  radius: root.corners.control
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.t("back") + " · ⌫"
                  iconText: "󰁍"
                  bordered: true
                  foreground: root.fg
                  fontFamily: root.font
                  tooltipText: root.t("backTip")
                  onClicked: root.settingsOpen = false
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.t("settings").toUpperCase()
                  color: root.fg
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                }
              }
              PanelSeparator { width: parent.width; foreground: root.fg }

              // Language
              Row {
                spacing: Style.space(10)
                Text {
                  id: languageLabel
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.settingsLabelWidth
                  textFormat: Text.PlainText
                  text: root.t("language")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
                CompactDropdown {
                  id: languagePicker
                  popupRadius: root.corners.radius
                  controlRadius: root.corners.control
                  anchors.verticalCenter: parent.verticalCenter
                  width: fitWidth
                  fontSize: Style.font.caption
                  rowHeight: languageLabel.implicitHeight + Style.space(6)
                  popupRowHeight: languageLabel.implicitHeight + Style.space(8)
                  showLabel: false
                  fontFamily: root.font
                  accent: root.accentColor
                  options: [{ value: "auto", label: root.t("systemLanguage", [I18n.languageName(root.systemLang)]) }]
                    .concat(I18n.LANGUAGES.map(function(l) { return { value: l.code, label: l.name } }))
                  value: root.languageSetting
                  onChanged: function(picked) {
                    if (root.hostWidget) root.hostWidget.setLanguage(picked)
                    languagePicker.value = Qt.binding(function() { return root.languageSetting })
                  }
                }
              }

              // Schedule mode
              Column {
                width: parent.width
                spacing: Style.space(4)
                Row {
                  spacing: Style.space(10)
                  Text {
                    id: schedModeLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.settingsLabelWidth
                    textFormat: Text.PlainText
                    text: root.t("scheduleMode")
                    wrapMode: Text.WordWrap
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  CompactDropdown {
                    id: schedModePicker
                    popupRadius: root.corners.radius
                    controlRadius: root.corners.control
                    anchors.verticalCenter: parent.verticalCenter
                    width: fitWidth
                    fontSize: Style.font.caption
                    rowHeight: languageLabel.implicitHeight + Style.space(6)
                    popupRowHeight: languageLabel.implicitHeight + Style.space(8)
                    showLabel: false
                    fontFamily: root.font
                    accent: root.accentColor
                    options: [
                      { value: "bridge", label: root.t("schedModeBridge") },
                      { value: "local",  label: root.t("schedModeLocal") }
                    ]
                    value: root.scheduleModeSetting
                    onChanged: function(picked) {
                      if (root.hostWidget) root.hostWidget.setScheduleMode(picked)
                      schedModePicker.value = Qt.binding(function() { return root.scheduleModeSetting })
                    }
                  }
                }
                Text {
                  x: root.settingsLabelWidth + Style.space(10)
                  width: parent.width - x
                  textFormat: Text.PlainText
                  text: root.t("scheduleModeHint")
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
              }

              // Confirm before All On
              Item {
                width: parent.width
                height: Math.max(confirmAllOnLabel.implicitHeight, confirmAllOnToggle.implicitHeight)
                Text {
                  id: confirmAllOnLabel
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.settingsLabelWidth
                  textFormat: Text.PlainText
                  text: root.t("confirmAllOnSetting")
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
                ToggleSwitch {
                  id: confirmAllOnToggle
                  x: root.settingsLabelWidth + Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  cursorRing: false
                  rounded: root.corners.pill > 0
                  checked: root.confirmAllOnSetting
                  foreground: root.fg
                  accent: root.accentColor
                  onToggled: if (root.hostWidget) root.hostWidget.setConfirmAllOn(!root.confirmAllOnSetting)
                }
              }

              // App Skin
              Row {
                spacing: Style.space(10)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.settingsLabelWidth
                  textFormat: Text.PlainText
                  text: root.t("appSkin")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
                CompactDropdown {
                  id: skinPicker
                  popupRadius: root.corners.radius
                  controlRadius: root.corners.control
                  anchors.verticalCenter: parent.verticalCenter
                  width: fitWidth
                  fontSize: Style.font.caption
                  rowHeight: languageLabel.implicitHeight + Style.space(6)
                  popupRowHeight: languageLabel.implicitHeight + Style.space(8)
                  showLabel: false
                  fontFamily: root.font
                  accent: root.accentColor
                  options: [
                    { value: "native",    label: root.t("skinNative") },
                    { value: "synthwave", label: root.t("skinSynthwave") },
                    { value: "cozy",      label: root.t("skinCozy") },
                    { value: "terminal",  label: root.t("skinTerminal") },
                    { value: "disco",     label: root.t("skinDisco") },
                    { value: "zen",       label: root.t("skinZen") }
                  ]
                  value: root.skinSetting
                  onChanged: function(picked) {
                    if (root.hostWidget) root.hostWidget.setSkin(picked)
                    skinPicker.value = Qt.binding(function() { return root.skinSetting })
                  }
                }
              }

              // Bar Icon
              Row {
                spacing: Style.space(10)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.settingsLabelWidth
                  textFormat: Text.PlainText
                  text: root.t("barIcon")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
                CompactDropdown {
                  id: barIconPicker
                  popupRadius: root.corners.radius
                  controlRadius: root.corners.control
                  anchors.verticalCenter: parent.verticalCenter
                  width: fitWidth
                  fontSize: Style.font.caption
                  rowHeight: languageLabel.implicitHeight + Style.space(6)
                  popupRowHeight: languageLabel.implicitHeight + Style.space(8)
                  showLabel: false
                  fontFamily: root.font
                  accent: root.accentColor
                  options: [
                    { value: "bulb",      label: "󰛨  " + root.t("iconBulb") },
                    { value: "deskLamp",  label: "󰥟  " + root.t("iconDeskLamp") },
                    { value: "floorLamp", label: "󰣜  " + root.t("iconFloorLamp") },
                    { value: "sun",       label: "󰖙  " + root.t("iconSun") },
                    { value: "sparkles",  label: "󰦥  " + root.t("iconSparkles") },
                    { value: "bolt",      label: "󱐋  " + root.t("iconBolt") },
                    { value: "flame",     label: "󰈸  " + root.t("iconFlame") },
                    { value: "dot",       label: "●  " + root.t("iconDot") }
                  ]
                  value: root.barIconSetting
                  onChanged: function(picked) {
                    if (root.hostWidget) root.hostWidget.setBarIcon(picked)
                    barIconPicker.value = Qt.binding(function() { return root.barIconSetting })
                  }
                }
              }

              // Show lit count in bar
              Item {
                width: parent.width
                height: Math.max(showCountLabel.implicitHeight, showCountToggle.implicitHeight)
                Text {
                  id: showCountLabel
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.settingsLabelWidth
                  textFormat: Text.PlainText
                  text: root.t("showLitCount")
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
                ToggleSwitch {
                  id: showCountToggle
                  x: root.settingsLabelWidth + Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  cursorRing: false
                  rounded: root.corners.pill > 0
                  checked: root.showCountSetting
                  foreground: root.fg
                  accent: root.accentColor
                  onToggled: if (root.hostWidget) root.hostWidget.setShowCount(!root.showCountSetting)
                }
              }

              // Ask AI (Optional — off by default)
              Column {
                width: parent.width
                spacing: Style.space(4)
                Item {
                  width: parent.width
                  height: Math.max(askAiLabel.implicitHeight, askAiToggle.implicitHeight)
                  Text {
                    id: askAiLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.settingsLabelWidth
                    textFormat: Text.PlainText
                    text: root.t("askAiSetting")
                    wrapMode: Text.WordWrap
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  ToggleSwitch {
                    id: askAiToggle
                    x: root.settingsLabelWidth + Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    cursorRing: false
                    rounded: root.corners.pill > 0
                    checked: root.askAiSetting
                    foreground: root.fg
                    accent: root.accentColor
                    onToggled: {
                      var next = !root.askAiSetting
                      if (root.hostWidget) root.hostWidget.setAskAi(next)
                      if (!next) root.aiOpen = false
                    }
                  }
                }
                Text {
                  x: root.settingsLabelWidth + Style.space(10)
                  width: parent.width - x
                  textFormat: Text.PlainText
                  text: root.t("askAiSettingHint")
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
              }

              // Panel Size & Offset
              Column {
                width: parent.width
                spacing: Style.space(6)
                Row {
                  spacing: Style.space(10)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.settingsLabelWidth
                    textFormat: Text.PlainText
                    text: root.t("panelSize")
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  Flow {
                    width: parent.parent.width - root.settingsLabelWidth - Style.space(10)
                    spacing: Style.space(6)
                    // Width stepper
                    Row {
                      spacing: Style.space(4)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.t("panelWidth")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        radius: root.corners.control; text: "−"; bordered: true; foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(6); verticalPadding: Style.space(2)
                        enabled: root.panelWidthSetting > 380
                        onClicked: if (root.hostWidget) root.hostWidget.setPanelWidth(root.panelWidthSetting - 30)
                      }
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.panelWidthSetting + "px"
                        color: root.fg
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        radius: root.corners.control; text: "+"; bordered: true; foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(6); verticalPadding: Style.space(2)
                        enabled: root.panelWidthSetting < 760
                        onClicked: if (root.hostWidget) root.hostWidget.setPanelWidth(root.panelWidthSetting + 30)
                      }
                    }
                    // Height stepper
                    Row {
                      spacing: Style.space(4)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.t("panelHeight")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        radius: root.corners.control; text: "−"; bordered: true; foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(6); verticalPadding: Style.space(2)
                        onClicked: {
                          if (!root.hostWidget) return
                          var nextH = root.panelHeightSetting <= 380 ? 0 : root.panelHeightSetting - 40
                          root.hostWidget.setPanelHeight(nextH)
                        }
                      }
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.panelHeightSetting > 0 ? (root.panelHeightSetting + "px") : root.t("panelHeightAuto")
                        color: root.fg
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        radius: root.corners.control; text: "+"; bordered: true; foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(6); verticalPadding: Style.space(2)
                        enabled: root.panelHeightSetting < 900
                        onClicked: {
                          if (!root.hostWidget) return
                          var nextH = root.panelHeightSetting === 0 ? 540 : root.panelHeightSetting + 40
                          root.hostWidget.setPanelHeight(nextH)
                        }
                      }
                    }
                    // Offset X / Y steppers
                    Row {
                      spacing: Style.space(4)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.t("panelOffset") + " X"
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        radius: root.corners.control; text: "−"; bordered: true; foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(6); verticalPadding: Style.space(2)
                        enabled: root.panelOffsetX > -320
                        onClicked: if (root.hostWidget) root.hostWidget.setPanelOffsetX(root.panelOffsetX - 20)
                      }
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: (root.panelOffsetX > 0 ? "+" : "") + root.panelOffsetX + "px"
                        color: root.fg
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        radius: root.corners.control; text: "+"; bordered: true; foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(6); verticalPadding: Style.space(2)
                        enabled: root.panelOffsetX < 320
                        onClicked: if (root.hostWidget) root.hostWidget.setPanelOffsetX(root.panelOffsetX + 20)
                      }
                    }
                    Row {
                      spacing: Style.space(4)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "Y"
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        radius: root.corners.control; text: "−"; bordered: true; foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(6); verticalPadding: Style.space(2)
                        enabled: root.panelOffsetY > 0
                        onClicked: if (root.hostWidget) root.hostWidget.setPanelOffsetY(root.panelOffsetY - 12)
                      }
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "+" + root.panelOffsetY + "px"
                        color: root.fg
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        radius: root.corners.control; text: "+"; bordered: true; foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(6); verticalPadding: Style.space(2)
                        enabled: root.panelOffsetY < 240
                        onClicked: if (root.hostWidget) root.hostWidget.setPanelOffsetY(root.panelOffsetY + 12)
                      }
                    }
                    // Reset button
                    Button {
                      radius: root.corners.control
                      text: root.t("resetSize")
                      bordered: true
                      foreground: root.fg
                      fontFamily: root.font
                      fontSize: Style.font.caption
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(2)
                      enabled: root.panelWidthSetting !== 430 || root.panelHeightSetting !== 0 || root.panelOffsetX !== 0 || root.panelOffsetY !== 0
                      onClicked: if (root.hostWidget) root.hostWidget.resetPanelGeometry()
                    }
                  }
                }
                Text {
                  x: root.settingsLabelWidth + Style.space(10)
                  width: parent.width - x
                  textFormat: Text.PlainText
                  text: root.t("panelSizeHint")
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
              }

              // Corners
              Column {
                width: parent.width
                spacing: Style.space(4)
                Row {
                  spacing: Style.space(10)
                  Text {
                    id: cornersLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.settingsLabelWidth
                    textFormat: Text.PlainText
                    text: root.t("corners")
                    wrapMode: Text.WordWrap
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  CompactDropdown {
                    id: cornersPicker
                    anchors.verticalCenter: parent.verticalCenter
                    width: fitWidth
                    fontSize: Style.font.caption
                    rowHeight: cornersLabel.implicitHeight + Style.space(6)
                    popupRowHeight: cornersLabel.implicitHeight + Style.space(8)
                    controlRadius: root.corners.control
                    popupRadius: root.corners.radius
                    showLabel: false
                    fontFamily: root.font
                    accent: root.accentColor
                    options: Corners.options(root.t, Style.cornerRadius)
                    value: root.cornersSetting
                    onChanged: function(picked) {
                      if (root.hostWidget) root.hostWidget.setCorners(picked)
                      cornersPicker.value = Qt.binding(function() { return root.cornersSetting })
                    }
                  }
                }
                Text {
                  x: root.settingsLabelWidth + Style.space(10)
                  width: parent.width - x
                  textFormat: Text.PlainText
                  text: root.t("cornersHint")
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
              }

              // F12 screenshot
              Column {
                width: parent.width
                spacing: Style.space(4)
                Item {
                  width: parent.width
                  height: Math.max(shotLabel.implicitHeight, shotToggle.implicitHeight)
                  Text {
                    id: shotLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.settingsLabelWidth
                    textFormat: Text.PlainText
                    text: root.t("shotKey")
                    wrapMode: Text.WordWrap
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  ToggleSwitch {
                    id: shotToggle
                    x: root.settingsLabelWidth + Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    cursorRing: false
                    rounded: root.corners.pill > 0
                    checked: root.screenshotKey
                    foreground: root.fg
                    accent: root.accentColor
                    onToggled: if (root.hostWidget) root.hostWidget.setScreenshotKey(!root.screenshotKey)
                  }
                }
                Text {
                  x: root.settingsLabelWidth + Style.space(10)
                  width: parent.width - x
                  textFormat: Text.PlainText
                  text: root.t("shotKeyHint", ["Lights"])
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
              }

              // Bridge & Unpair (only when a real Hue Bridge is paired; otherwise offer quick Hue Bridge pairing)
              Item {
                visible: root.huePaired
                width: parent.width
                height: Math.max(bridgeText.implicitHeight, unpairButton.implicitHeight)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.settingsLabelWidth
                  textFormat: Text.PlainText
                  text: root.t("bridge")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
                Text {
                  id: bridgeText
                  anchors.left: parent.left
                  anchors.leftMargin: root.settingsLabelWidth + Style.space(10)
                  anchors.right: unpairButton.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: (root.bridge.name || "Hue Bridge") + (root.bridge.ip ? " · " + root.bridge.ip : "")
                  color: root.fg
                  font.family: root.font
                  font.pixelSize: Style.font.body
                }
                Button {
                  id: unpairButton
                  radius: root.corners.control
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.confirmUnpair ? root.t("reallyUnpair") : root.t("unpair")
                  iconText: "󰌸"
                  bordered: true
                  foreground: root.confirmUnpair ? Commons.Color.urgent : root.fg
                  fontFamily: root.font
                  tooltipText: root.t("unpairTip")
                  onClicked: {
                    if (root.confirmUnpair) { root.confirmUnpair = false; root.settingsOpen = false; root.send({ cmd: "unpair" }) }
                    else root.confirmUnpair = true
                  }
                }
              }

              // Allow pairing a Philips Hue Bridge later when running in multi-device-only mode
              Column {
                visible: !root.huePaired && root.paired
                width: parent.width
                spacing: Style.space(6)
                Item {
                  width: parent.width
                  height: Math.max(noHueLbl.implicitHeight, scanHueBtn.implicitHeight)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.settingsLabelWidth
                    textFormat: Text.PlainText
                    text: root.t("bridge")
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    id: noHueLbl
                    anchors.left: parent.left
                    anchors.leftMargin: root.settingsLabelWidth + Style.space(10)
                    anchors.right: scanHueBtn.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: root.t("noBridge")
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.body
                  }
                  Button {
                    id: scanHueBtn
                    radius: root.corners.control
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.t("pairHeader")
                    iconText: "󰌷"
                    bordered: true
                    foreground: root.accentColor
                    fontFamily: root.font
                    onClicked: {
                      root.settingsOpen = false
                      root.send({ cmd: "discover" })
                    }
                  }
                }
              }

              // Other smart lights & hubs (Multi-Device)
              PanelSeparator { width: parent.width; foreground: root.fg }
              Column {
                width: parent.width
                spacing: Style.space(8)
                Item {
                  width: parent.width
                  height: Math.max(extraDevHeader.implicitHeight, addExtraDevBtn.implicitHeight)
                  Column {
                    id: extraDevHeader
                    anchors.left: parent.left
                    anchors.right: addExtraDevBtn.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)
                    Text {
                      textFormat: Text.PlainText
                      text: root.t("otherDevices")
                      color: root.fg
                      font.family: root.font
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                    Text {
                      width: parent.width
                      wrapMode: Text.WordWrap
                      textFormat: Text.PlainText
                      text: root.t("otherDevicesHint")
                      color: root.dim
                      font.family: root.font
                      font.pixelSize: Style.font.caption
                    }
                  }
                  Button {
                    id: addExtraDevBtn
                    radius: root.corners.control
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.t("addDevice")
                    iconText: "󰐕"
                    bordered: true
                    foreground: root.fg
                    fontFamily: root.font
                    onClicked: root.openNewProvider("home_assistant")
                  }
                }

                Text {
                  visible: root.providers.length === 0 && !root.providerFormOpen
                  width: parent.width
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                  text: root.t("noExtraDevices")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: root.providers.length
                  delegate: Rectangle {
                    id: provRow
                    required property int index
                    readonly property var p: root.providers[index] || ({})
                    readonly property var info: root.providerInfo(p.kind) || ({ badge: String(p.kind || ""), color: "#888888" })
                    width: parent.width
                    height: provRowInner.implicitHeight + Style.space(12)
                    radius: root.corners.control
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
                    border.width: 1
                    border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
                    Row {
                      id: provRowInner
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.margins: Style.space(8)
                      spacing: Style.space(6)
                      Column {
                        width: parent.width - provRowCtrls.implicitWidth - Style.space(6)
                        spacing: Style.space(2)
                        Row {
                          spacing: Style.space(5)
                          Text {
                            textFormat: Text.PlainText
                            text: (!provRow.p.enabled ? "○" : (provRow.p.connected ? "●" : "◐")) + " " + String(provRow.p.name || "")
                            color: root.fg
                            font.family: root.font
                            font.pixelSize: Style.font.body
                            font.bold: true
                          }
                          Text {
                            textFormat: Text.PlainText
                            text: "[" + provRow.info.badge + "]"
                            color: provRow.info.color
                            font.family: root.font
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }
                        }
                        Text {
                          textFormat: Text.PlainText
                          text: String(provRow.p.host || "") + ":" + String(provRow.p.port || "") + (Number(provRow.p.light_count || 0) > 0 ? " · " + String(provRow.p.light_count) : "")
                          color: root.dim
                          font.family: root.font
                          font.pixelSize: Style.font.caption
                        }
                        Text {
                          visible: provRow.p.enabled === true && String(provRow.p.error || "") !== ""
                          width: parent.width
                          wrapMode: Text.WordWrap
                          textFormat: Text.PlainText
                          text: String(provRow.p.error || "")
                          color: Commons.Color.urgent
                          font.family: root.font
                          font.pixelSize: Style.font.caption
                        }
                      }
                      Row {
                        id: provRowCtrls
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(4)
                        ToggleSwitch {
                          anchors.verticalCenter: parent.verticalCenter
                          cursorRing: false
                          rounded: root.corners.pill > 0
                          checked: provRow.p.enabled !== false
                          foreground: root.fg
                          accent: root.accentColor
                          onToggled: root.send({ cmd: "toggle_provider", id: provRow.p.id, enabled: !(provRow.p.enabled !== false) })
                        }
                        Button {
                          radius: root.corners.control
                          text: root.t("editDevice")
                          bordered: true
                          foreground: root.fg
                          fontFamily: root.font
                          onClicked: root.openEditProvider(provRow.p)
                        }
                        Button {
                          radius: root.corners.control
                          text: root.provConfirmRemoveId === provRow.p.id ? root.t("reallyUnpair") : root.t("removeDevice")
                          bordered: true
                          foreground: Commons.Color.urgent
                          fontFamily: root.font
                          onClicked: {
                            if (root.provConfirmRemoveId === provRow.p.id) {
                              root.provConfirmRemoveId = ""
                              root.send({ cmd: "remove_provider", id: provRow.p.id })
                            } else {
                              root.provConfirmRemoveId = provRow.p.id
                            }
                          }
                        }
                        Button {
                          visible: root.provConfirmRemoveId === provRow.p.id
                          radius: root.corners.control
                          text: root.t("cancel")
                          bordered: true
                          foreground: root.fg
                          fontFamily: root.font
                          onClicked: root.provConfirmRemoveId = ""
                        }
                      }
                    }
                  }
                }

                Loader {
                  visible: root.providerFormOpen && root.settingsOpen
                  active: visible
                  width: parent.width
                  sourceComponent: providerEditorComponent
                }
              }
            }

            // ---------------------------------------------------------------- main view
            Column {
              visible: !root.settingsOpen && !root.infoOpen && !root.helpOpen && !root.aiOpen
              width: parent.width
              spacing: Style.space(10)

              // ---------------------------------------------------------------- pairing
              Column {
                visible: !root.paired
                width: parent.width
                spacing: Style.space(10)

                PanelSeparator { width: parent.width; foreground: root.fg }
                PanelSectionHeader { text: root.t("connectLights").toUpperCase(); foreground: root.fg; fontFamily: root.font }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: root.phase === "pairing"
                    ? root.t("pressNow", [Number(root.stats.pair_remaining || 0), root.stats.pair_ip])
                    : root.t("clickPair")
                  color: root.phase === "pairing" ? root.fg : root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: root.phase === "pairing" ? 0 : root.candidates.length
                  delegate: Item {
                    id: cand
                    required property int index
                    readonly property var bridgeInfo: root.candidates[index] || ({})
                    width: parent.width
                    height: pairButton.implicitHeight
                    Text {
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.right: pairButton.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      elide: Text.ElideRight
                      text: (cand.bridgeInfo.name || "Hue Bridge") + "  ·  " + cand.bridgeInfo.ip
                      color: root.fg
                      font.family: root.font
                      font.pixelSize: Style.font.body
                    }
                    Button {
                      id: pairButton
                      radius: root.corners.control
                      anchors.right: parent.right
                      text: root.t("pair")
                      iconText: "󰌷"
                      bordered: true
                      foreground: root.fg
                      fontFamily: root.font
                      onClicked: root.send({ cmd: "pair", ip: cand.bridgeInfo.ip })
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.phase !== "pairing" && root.candidates.length === 0
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: root.stats.discovering ? root.t("searching") : root.t("notFound")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }

                Item {
                  visible: root.phase !== "pairing"
                  width: parent.width
                  height: manualPair.implicitHeight
                  KeyTextField {
                    id: manualIp
                    radius: root.corners.control
                    maximumLength: 64
                    anchors.left: parent.left
                    anchors.right: manualPair.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: root.t("ipPlaceholder")
                    foreground: root.fg
                    accent: root.accentColor
                    onAccepted: root.send({ cmd: "pair", ip: text })
                  }
                  Button {
                    id: manualPair
                    radius: root.corners.control
                    anchors.right: parent.right
                    text: root.t("pair")
                    iconText: "󰌷"
                    bordered: true
                    foreground: root.fg
                    fontFamily: root.font
                    enabled: manualIp.text.trim() !== ""
                    onClicked: root.send({ cmd: "pair", ip: manualIp.text })
                  }
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(8)
                  Button {
                    radius: root.corners.control
                    visible: root.phase !== "pairing"
                    text: root.t("searchAgain")
                    iconText: "󰍉"
                    iconSpinning: root.stats.discovering === true
                    bordered: true
                    foreground: root.fg
                    fontFamily: root.font
                    enabled: root.stats.discovering !== true
                    onClicked: root.send({ cmd: "discover" })
                  }
                  Button {
                    radius: root.corners.control
                    visible: root.phase === "pairing"
                    text: root.t("cancel")
                    bordered: true
                    foreground: root.fg
                    fontFamily: root.font
                    onClicked: root.send({ cmd: "cancel_pair" })
                  }
                }

                // Multi-Device onboarding (works with or without a Hue Bridge)
                PanelSeparator { width: parent.width; foreground: root.fg }
                PanelSectionHeader { text: root.t("otherDevices").toUpperCase(); foreground: root.fg; fontFamily: root.font }
                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                  text: root.t("otherDevicesHint")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
                Flow {
                  width: parent.width
                  spacing: Style.space(6)
                  Repeater {
                    model: root.extraProviderCatalog.length
                    delegate: Button {
                      required property int index
                      readonly property var info: root.extraProviderCatalog[index]
                      radius: root.corners.control
                      text: info.badge
                      bordered: true
                      foreground: root.fg
                      fontFamily: root.font
                      onClicked: root.openNewProvider(info.kind)
                    }
                  }
                }
                Loader {
                  visible: root.providerFormOpen && !root.settingsOpen
                  active: visible
                  width: parent.width
                  sourceComponent: providerEditorComponent
                }
              }

              // ---------------------------------------------------------------- 5 PageTabs (when paired)
              PanelSeparator { visible: root.paired; width: parent.width; foreground: root.fg }

              Flow {
                visible: root.paired
                width: parent.width
                spacing: Style.space(4)
                PageTab {
                  icon: "󰛨"
                  label: root.t("tabLights")
                  active: root.activeTab === "lights"
                  onActivated: { root.activeTab = "lights"; root.confirmAllOnPending = false; root.openLightMenu = ""; root.lightDialog = ""; root.lightDialogId = "" }
                }
                PageTab {
                  icon: "󰍍"
                  label: root.t("tabMap")
                  active: root.activeTab === "map"
                  onActivated: { root.activeTab = "map"; root.confirmAllOnPending = false; root.openLightMenu = ""; root.lightDialog = ""; root.lightDialogId = "" }
                }
                PageTab {
                  icon: "󰃰"
                  label: root.t("tabSchedules")
                  active: root.activeTab === "schedules"
                  onActivated: { root.activeTab = "schedules"; root.confirmAllOnPending = false; root.openLightMenu = ""; root.lightDialog = ""; root.lightDialogId = "" }
                }
                PageTab {
                  icon: "󰌹"
                  label: root.t("tabRules")
                  active: root.activeTab === "rules"
                  onActivated: { root.activeTab = "rules"; root.confirmAllOnPending = false; root.openLightMenu = ""; root.lightDialog = ""; root.lightDialogId = "" }
                }
                PageTab {
                  icon: "󰎈"
                  label: root.t("tabSynth")
                  active: root.activeTab === "synth"
                  onActivated: { root.activeTab = "synth"; root.confirmAllOnPending = false; root.openLightMenu = ""; root.lightDialog = ""; root.lightDialogId = "" }
                }
              }

              // ================================================================ TAB 1: LIGHTS
              Column {
                visible: root.paired && root.activeTab === "lights"
                width: parent.width
                spacing: Style.space(8)

                // Filter pills
                Flow {
                  width: parent.width
                  spacing: Style.space(6)
                  Repeater {
                    model: [
                      { id: "all",       key: "filterAll" },
                      { id: "on",        key: "filterOn" },
                      { id: "rooms",     key: "filterRooms" },
                      { id: "zones",     key: "filterZones" },
                      { id: "favorites", key: "filterFavorites" }
                    ]
                    delegate: Button {
                      required property var modelData
                      radius: root.corners.control
                      text: root.t(modelData.key)
                      bordered: true
                      selected: root.lightFilter === modelData.id
                      accent: root.accentColor
                      foreground: root.fg
                      fontFamily: root.font
                      fontSize: Style.font.caption
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(2)
                      onClicked: root.lightFilter = modelData.id
                    }
                  }
                }

                // Favorites quick strip
                Column {
                  visible: root.favoriteItems.length > 0
                  width: parent.width
                  spacing: Style.space(4)
                  PanelSectionHeader { text: root.t("favorites").toUpperCase(); foreground: root.fg; fontFamily: root.font }
                  Flow {
                    width: parent.width
                    spacing: Style.space(6)
                    Repeater {
                      model: root.favoriteItems.length
                      delegate: Button {
                        required property int index
                        readonly property var fav: root.favoriteItems[index] || ({})
                        radius: root.corners.control
                        text: (fav.on ? "● " : "○ ") + String(fav.name || "")
                        bordered: true
                        selected: fav.on === true
                        accent: fav.on ? (fav.color || root.accentColor) : root.accentColor
                        foreground: root.fg
                        fontFamily: root.font
                        fontSize: Style.font.caption
                        horizontalPadding: Style.space(8)
                        verticalPadding: Style.space(2)
                        onClicked: {
                          if (fav.kind === "room" && fav.room) root.setRoom(fav.room, { on: !fav.on })
                          else if (fav.kind === "light") root.send({ cmd: "light", id: fav.id, on: !fav.on })
                        }
                      }
                    }
                  }
                }

                // Bridge Pro MotionAware™ Ready hint (hidden unless Pro & 0 areas & not dismissed)
                Rectangle {
                  visible: root.showMotionAwareHint
                  width: parent.width
                  height: lightsMaHintCol.implicitHeight + Style.space(16)
                  radius: root.corners.radius
                  color: Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.11)
                  border.width: 1
                  border.color: Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.45)

                  Column {
                    id: lightsMaHintCol
                    x: Style.space(10)
                    y: Style.space(8)
                    width: parent.width - Style.space(20)
                    spacing: Style.space(5)

                    Item {
                      width: parent.width
                      height: Math.max(lightsMaTitle.implicitHeight, Style.space(18))
                      Text {
                        id: lightsMaTitle
                        anchors.left: parent.left
                        anchors.right: lightsMaClose.left
                        anchors.rightMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: "●  " + root.t("motionHintTitle")
                        color: "#10B981"
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      Rectangle {
                        id: lightsMaClose
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(18)
                        height: Style.space(18)
                        radius: root.corners.small
                        color: lightsMaCloseM.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16) : "transparent"
                        Text {
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          text: "×"
                          color: lightsMaCloseM.containsMouse ? root.fg : root.dim
                          font.family: root.font
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                        MouseArea {
                          id: lightsMaCloseM
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.motionAwareHintDismissed = true
                        }
                      }
                    }

                    Text {
                      width: parent.width
                      wrapMode: Text.WordWrap
                      textFormat: Text.PlainText
                      text: root.motionAwareEligibleRooms.length > 0
                        ? root.t("motionHintEligible", [root.motionAwareEligibleRooms.join(", ")])
                        : root.t("motionHintNeed3Lights")
                      color: root.fg
                      font.family: root.font
                      font.pixelSize: Style.font.caption
                    }

                    Column {
                      width: parent.width
                      spacing: Style.space(2)
                      Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: "1. " + root.t("motionHintStep1")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Math.max(9, Style.font.caption - 1)
                      }
                      Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: "2. " + root.t("motionHintStep2")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Math.max(9, Style.font.caption - 1)
                      }
                      Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: "3. " + root.t("motionHintStep3")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Math.max(9, Style.font.caption - 1)
                      }
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.rooms.length === 0
                  text: root.phase === "ok" ? root.t("noLights") : root.t("connecting")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.rooms.length > 0 && root.filteredRooms.length === 0
                  text: root.t("noMatchingLights")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }

                Flickable {
                  id: roomScroller
                  visible: root.filteredRooms.length > 0
                  width: parent.width
                  height: Math.min(roomColumn.implicitHeight, root.maxRoomListHeight)
                  contentWidth: width
                  contentHeight: roomColumn.implicitHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  interactive: contentHeight > height

                  Column {
                    id: roomColumn
                    width: roomScroller.width
                    spacing: Style.space(8)

                    Repeater {
                      model: root.filteredRooms.length
                      delegate: Rectangle {
                        id: roomBlock
                        required property int index
                        readonly property var room: root.filteredRoomAt(index)
                        readonly property string rkey: root.roomKey(room)
                        readonly property bool isOpen: root.expanded[rkey] === true
                        readonly property bool pinned: root.isFav("room:" + rkey)
                        readonly property bool excluded: room.kind === "room" && root.isExcluded(room.id)
                        readonly property bool motionActive: root.roomMotionActive(room)
                        property bool allScenes: false
                        readonly property bool lit: room.on === true
                        readonly property color tint: lit ? (room.color || root.accentColor) : root.fg
                        readonly property real pad: Style.space(10)
                        readonly property int unreachable: {
                          var n = 0
                          var ls = room.lights || []
                          for (var i = 0; i < ls.length; i++) if (ls[i].reachable === false) n++
                          return n
                        }
                        width: roomColumn.width
                        height: cardColumn.implicitHeight + 2 * pad
                        radius: root.corners.radius
                        color: lit
                          ? Qt.rgba(tint.r, tint.g, tint.b, cardHover.hovered ? 0.17 : 0.12)
                          : (cardHover.hovered ? Qt.rgba(root.hasSkin ? root.accentColor.r : root.fg.r, root.hasSkin ? root.accentColor.g : root.fg.g, root.hasSkin ? root.accentColor.b : root.fg.b, root.hasSkin ? 0.11 : 0.07) : root.skinCardFill)
                        border.width: 1
                        border.color: lit
                          ? Qt.rgba(tint.r, tint.g, tint.b, 0.4)
                          : (root.hasSkin ? root.skinCardBorder : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08))
                        Behavior on color { ColorAnimation { duration: 200 } }

                        HoverHandler { id: cardHover }

                        Column {
                          id: cardColumn
                          x: roomBlock.pad
                          y: roomBlock.pad
                          width: roomBlock.width - 2 * roomBlock.pad
                          spacing: Style.space(8)

                          // Header: icon, name + status, pin, exclude-all-on, chevron, switch
                          Item {
                            width: parent.width
                            height: Math.max(badge.height, roomSwitch.implicitHeight)

                            Rectangle {
                              id: badge
                              anchors.left: parent.left
                              anchors.verticalCenter: parent.verticalCenter
                              width: Style.space(34)
                              height: width
                              radius: Math.min(root.corners.pill, width / 2)
                              color: roomBlock.lit ? roomBlock.tint : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                              Behavior on color { ColorAnimation { duration: 200 } }
                              Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: root.roomIcon(roomBlock.room)
                                color: roomBlock.lit ? root.onTint(roomBlock.tint) : root.dim
                                font.family: root.font
                                font.pixelSize: Style.font.body * 1.15
                              }
                            }

                            Column {
                              anchors.left: badge.right
                              anchors.leftMargin: Style.space(10)
                              anchors.right: pinBtn.left
                              anchors.rightMargin: Style.space(4)
                              anchors.verticalCenter: parent.verticalCenter
                              spacing: Style.space(1)
                              Row {
                                width: parent.width
                                spacing: Style.space(5)
                                Text {
                                  anchors.verticalCenter: parent.verticalCenter
                                  textFormat: Text.PlainText
                                  width: Math.min(implicitWidth, parent.width - (roomMotionBadge.visible ? (roomMotionBadge.width + Style.space(5)) : 0) - (roomProvBadge.visible ? (roomProvBadge.width + Style.space(5)) : 0) - (roomOfflineBadge.visible ? (roomOfflineBadge.width + Style.space(5)) : 0))
                                  elide: Text.ElideRight
                                  text: roomBlock.room.kind === "other" ? root.t("otherLights") : String(roomBlock.room.name || "")
                                  color: roomBlock.lit ? root.fg : Qt.lighter(root.dim, 1.15)
                                  font.family: root.font
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }
                                Rectangle {
                                  id: roomProvBadge
                                  readonly property var provInfo: root.providerInfo(String(roomBlock.room.provider || ""))
                                  visible: provInfo !== null
                                  anchors.verticalCenter: parent.verticalCenter
                                  width: roomProvTxt.implicitWidth + Style.space(8)
                                  height: roomProvTxt.implicitHeight + Style.space(2)
                                  radius: Math.min(root.corners.pill, height * 0.5)
                                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
                                  border.width: 1
                                  border.color: provInfo ? provInfo.color : root.dim
                                  Text {
                                    id: roomProvTxt
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: roomProvBadge.provInfo ? roomProvBadge.provInfo.badge : ""
                                    color: roomProvBadge.provInfo ? roomProvBadge.provInfo.color : root.fg
                                    font.family: root.font
                                    font.pixelSize: Math.max(9, Style.font.caption - 2)
                                    font.bold: true
                                  }
                                }
                                Rectangle {
                                  id: roomOfflineBadge
                                  // Every light in this room is unreachable
                                  readonly property var roomLights: roomBlock.room.lights || []
                                  visible: {
                                    if (roomLights.length === 0) return false
                                    for (var i = 0; i < roomLights.length; i++) if (roomLights[i].reachable !== false) return false
                                    return true
                                  }
                                  anchors.verticalCenter: parent.verticalCenter
                                  width: roomOfflineTxt.implicitWidth + Style.space(8)
                                  height: roomOfflineTxt.implicitHeight + Style.space(2)
                                  radius: Math.min(root.corners.pill, height * 0.5)
                                  color: Qt.rgba(249 / 255, 115 / 255, 22 / 255, 0.14)
                                  border.width: 1
                                  border.color: Qt.rgba(249 / 255, 115 / 255, 22 / 255, 0.35)
                                  Text {
                                    id: roomOfflineTxt
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: root.t("offlinePill")
                                    color: "#F97316"
                                    font.family: root.font
                                    font.pixelSize: Math.max(9, Style.font.caption - 2)
                                    font.bold: true
                                  }
                                }
                                Rectangle {
                                  id: roomMotionBadge
                                  visible: roomBlock.motionActive
                                  anchors.verticalCenter: parent.verticalCenter
                                  width: roomMotionTxt.implicitWidth + Style.space(8)
                                  height: roomMotionTxt.implicitHeight + Style.space(2)
                                  radius: Math.min(root.corners.pill, height * 0.5)
                                  color: Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.22)
                                  border.width: 1
                                  border.color: Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.72)
                                  Text {
                                    id: roomMotionTxt
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: "● " + root.t("motionPresence")
                                    color: "#10B981"
                                    font.family: root.font
                                    font.pixelSize: Math.max(9, Style.font.caption - 2)
                                    font.bold: true
                                  }
                                }
                              }
                              Text {
                                textFormat: Text.PlainText
                                width: parent.width
                                elide: Text.ElideRight
                                text: root.roomStatus(roomBlock.room, roomBlock.unreachable)
                                color: root.dim
                                font.family: root.font
                                font.pixelSize: Style.font.caption
                              }
                            }

                            MouseArea {
                              id: headerMouse
                              anchors.left: parent.left
                              anchors.right: pinBtn.left
                              anchors.top: parent.top
                              anchors.bottom: parent.bottom
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.toggleExpanded(roomBlock.room)
                            }

                            Button {
                              id: pinBtn
                              radius: root.corners.control
                              anchors.right: excludeBtn.visible ? excludeBtn.left : chevronBtn.left
                              anchors.rightMargin: Style.space(2)
                              anchors.verticalCenter: parent.verticalCenter
                              iconText: roomBlock.pinned ? "󰐃" : "󰤱"
                              iconSize: Style.font.caption
                              horizontalPadding: Style.space(4)
                              verticalPadding: Style.space(2)
                              foreground: roomBlock.pinned ? root.accentColor : root.dim
                              fontFamily: root.font
                              tooltipText: roomBlock.pinned ? root.t("unpinTip") : root.t("pinTip")
                              onClicked: if (root.hostWidget) root.hostWidget.toggleFavorite("room:" + roomBlock.rkey)
                            }

                            Button {
                              id: excludeBtn
                              visible: roomBlock.room.kind === "room"
                              radius: root.corners.control
                              anchors.right: chevronBtn.left
                              anchors.rightMargin: Style.space(2)
                              anchors.verticalCenter: parent.verticalCenter
                              iconText: roomBlock.excluded ? "󰂭" : "󰛨"
                              iconSize: Style.font.caption
                              horizontalPadding: Style.space(4)
                              verticalPadding: Style.space(2)
                              foreground: roomBlock.excluded ? Commons.Color.urgent : root.dim
                              fontFamily: root.font
                              tooltipText: roomBlock.excluded ? root.t("includedAllOnTip") : root.t("excludeAllOnTip")
                              onClicked: if (root.hostWidget) root.hostWidget.toggleExcludeAllOn(roomBlock.room.id)
                            }

                            Button {
                              id: chevronBtn
                              radius: root.corners.control
                              anchors.right: roomSwitch.left
                              anchors.rightMargin: Style.space(4)
                              anchors.verticalCenter: parent.verticalCenter
                              iconText: roomBlock.isOpen ? "󰅀" : "󰅂"
                              iconSize: Style.font.body
                              horizontalPadding: Style.space(3)
                              verticalPadding: Style.space(2)
                              foreground: headerMouse.containsMouse ? root.fg : root.dim
                              fontFamily: root.font
                              onClicked: root.toggleExpanded(roomBlock.room)
                            }

                            ToggleSwitch {
                              id: roomSwitch
                              rounded: root.corners.pill > 0
                              anchors.right: parent.right
                              anchors.verticalCenter: parent.verticalCenter
                              cursorRing: false
                              checked: roomBlock.lit
                              foreground: root.fg
                              accent: roomBlock.lit ? roomBlock.tint : root.accentColor
                              onToggled: root.setRoom(roomBlock.room, { on: !roomBlock.lit })
                            }
                          }

                          // Room brightness slider while lit
                          Item {
                            visible: roomBlock.lit
                            width: parent.width
                            height: roomSlider.implicitHeight
                            PanelSlider {
                              id: roomSlider
                              anchors.left: parent.left
                              anchors.right: roomPct.left
                              anchors.rightMargin: Style.space(10)
                              anchors.verticalCenter: parent.verticalCenter
                              bar: root.bar
                              minimum: 1
                              maximum: 100
                              step: 5
                              fillColor: roomBlock.tint
                              value: Math.max(1, Number(roomBlock.room.bri || 1))
                              onMoved: function(v) { root.setRoom(roomBlock.room, { bri: v }) }
                            }
                            MouseArea {
                              anchors.fill: roomSlider
                              acceptedButtons: Qt.NoButton
                              onWheel: function(wheel) { root.scrollRooms(wheel) }
                            }
                            Text {
                              id: roomPct
                              textFormat: Text.PlainText
                              anchors.right: parent.right
                              anchors.verticalCenter: parent.verticalCenter
                              width: Style.space(38)
                              horizontalAlignment: Text.AlignRight
                              text: Math.round(roomSlider.liveValue) + "%"
                              color: root.fg
                              font.family: root.font
                              font.pixelSize: Style.font.caption
                            }
                          }

                          Rectangle {
                            visible: roomBlock.isOpen
                            width: parent.width
                            height: 1
                            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1)
                          }

                          // Single lights + unified ⋯ submenu + per-light inline color/warmth/effects/themes drawer
                          Repeater {
                            model: roomBlock.isOpen ? (roomBlock.room.lights || []).length : 0
                            delegate: Column {
                              id: lightRow
                              required property int index
                              readonly property var light: (roomBlock.room.lights || [])[index] || ({})
                              readonly property bool lightOn: light.on === true
                              readonly property bool lightPinned: root.isFav("light:" + light.id)
                              readonly property bool drawerOpen: root.openLightDrawer === light.id
                              readonly property bool menuOpen: root.openLightMenu === light.id
                              readonly property string lampIcon: root.lightIconFor(light.id)
                              readonly property bool hasControls: light.supports_ct === true || light.supports_color === true || ((light.available_effects || []).length > 0) || root.themes.length > 0
                              width: cardColumn.width
                              spacing: Style.space(6)

                              Item {
                                width: parent.width
                                height: Math.max(lightBadge.height, lightSwitch.implicitHeight, lightMenuBtn.height)

                                // 1:1 custom lamp icon badge (synced with Floorplan Map)
                                Rectangle {
                                  id: lightBadge
                                  anchors.left: parent.left
                                  anchors.leftMargin: Style.space(2)
                                  anchors.verticalCenter: parent.verticalCenter
                                  width: Style.space(22)
                                  height: Style.space(22)
                                  radius: width * 0.5
                                  color: lightRow.lightOn ? (lightRow.light.color || "#ffd27a") : Qt.rgba(22 / 255, 26 / 255, 36 / 255, 0.92)
                                  opacity: lightRow.light.reachable === false ? 0.45 : 1.0
                                  border.width: 1.2
                                  border.color: lightRow.lightOn ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(1, 1, 1, 0.28)
                                  LightLampGlyph {
                                    anchors.centerIn: parent
                                    width: Style.space(13)
                                    height: Style.space(13)
                                    iconName: lightRow.lampIcon
                                    version: mapTab ? mapTab.iconVersion : 0
                                    tint: root.lightContrastTint(lightRow.light)
                                  }
                                  // Emerald MotionAware active corner dot
                                  Rectangle {
                                    visible: lightRow.light.motion_aware === true
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: -Style.space(2)
                                    anchors.topMargin: -Style.space(2)
                                    width: Style.space(7)
                                    height: Style.space(7)
                                    radius: width * 0.5
                                    color: lightRow.light.motion_active === true ? "#10B981" : Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.55)
                                    border.width: 1
                                    border.color: "#0c1018"
                                  }
                                }

                                Text {
                                  textFormat: Text.PlainText
                                  anchors.left: lightBadge.right
                                  anchors.leftMargin: Style.space(7)
                                  anchors.right: lightSlider.visible ? lightSlider.left : lightSwitch.left
                                  anchors.rightMargin: Style.space(6)
                                  anchors.verticalCenter: parent.verticalCenter
                                  elide: Text.ElideRight
                                  text: (lightRow.lightPinned ? "󰐃 " : "") + String(lightRow.light.name || "") + (lightRow.light.reachable === false ? " · " + root.t("unreachable") : "")
                                  color: lightRow.lightOn && lightRow.light.reachable !== false ? root.fg : root.dim
                                  font.family: root.font
                                  font.pixelSize: Style.font.caption
                                  font.bold: lightRow.lightOn || lightRow.menuOpen
                                }

                                PanelSlider {
                                  id: lightSlider
                                  anchors.right: lightSwitch.left
                                  anchors.rightMargin: Style.space(6)
                                  anchors.verticalCenter: parent.verticalCenter
                                  width: Style.space(76)
                                  visible: lightRow.light.dimmable === true
                                  bar: root.bar
                                  minimum: 1
                                  maximum: 100
                                  step: 5
                                  knobSize: Style.space(12)
                                  fillColor: lightRow.lightOn ? (lightRow.light.color || root.accentColor) : root.dim
                                  value: lightRow.lightOn ? Math.max(1, Number(lightRow.light.bri || 1)) : 1
                                  opacity: lightRow.lightOn ? 1 : 0.45
                                  onMoved: function(v) { root.send({ cmd: "light", id: lightRow.light.id, bri: v }) }
                                }
                                MouseArea {
                                  anchors.fill: lightSlider
                                  acceptedButtons: Qt.NoButton
                                  onWheel: function(wheel) { root.scrollRooms(wheel) }
                                }

                                ToggleSwitch {
                                  id: lightSwitch
                                  rounded: root.corners.pill > 0
                                  anchors.right: lightMenuBtn.left
                                  anchors.rightMargin: Style.space(5)
                                  anchors.verticalCenter: parent.verticalCenter
                                  cursorRing: false
                                  trackHeight: Style.space(16)
                                  checked: lightRow.lightOn
                                  foreground: root.fg
                                  accent: lightRow.lightOn ? (lightRow.light.color || root.accentColor) : root.accentColor
                                  onToggled: root.send({ cmd: "light", id: lightRow.light.id, on: !lightRow.lightOn })
                                }

                                // Unified "⋯" submenu button (matches Map sidebar)
                                Rectangle {
                                  id: lightMenuBtn
                                  anchors.right: parent.right
                                  anchors.verticalCenter: parent.verticalCenter
                                  width: Style.space(22)
                                  height: Style.space(22)
                                  radius: root.corners.small
                                  color: lightRow.menuOpen || lightDotsMouse.containsMouse
                                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                                    : "transparent"
                                  border.width: lightRow.menuOpen ? 1 : 0
                                  border.color: root.accentColor
                                  Text {
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: "⋯"
                                    color: lightRow.menuOpen || lightDotsMouse.containsMouse ? root.fg : root.dim
                                    font.family: root.font
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                  }
                                  MouseArea {
                                    id: lightDotsMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                      root.openLightMenu = (root.openLightMenu === lightRow.light.id) ? "" : lightRow.light.id
                                    }
                                  }
                                }
                              }

                              // Compact inline action submenu matching Map sidebar
                              Rectangle {
                                visible: lightRow.menuOpen
                                x: Style.space(14)
                                width: parent.width - Style.space(14)
                                height: lightSubCol.implicitHeight + Style.space(8)
                                radius: root.corners.control
                                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                                border.width: 1
                                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.34)

                                Column {
                                  id: lightSubCol
                                  x: Style.space(4)
                                  y: Style.space(4)
                                  width: parent.width - Style.space(8)
                                  spacing: Style.space(2)

                                  // 1. Brightness…
                                  Rectangle {
                                    width: parent.width; height: Style.space(24); radius: Math.max(2, root.corners.small - 1)
                                    color: lmBriM.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
                                    Text {
                                      anchors.verticalCenter: parent.verticalCenter; x: Style.space(8)
                                      width: parent.width - Style.space(16); elide: Text.ElideRight; textFormat: Text.PlainText
                                      text: root.t("mapMenuBrightness")
                                      color: root.fg; font.family: root.font; font.pixelSize: Style.font.caption
                                    }
                                    MouseArea {
                                      id: lmBriM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                      onClicked: root.openLightBrightnessDialog(lightRow.light.id)
                                    }
                                  }

                                  // 2. Color & Warmth
                                  Rectangle {
                                    visible: lightRow.hasControls
                                    width: parent.width; height: Style.space(24); radius: Math.max(2, root.corners.small - 1)
                                    color: lmColM.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
                                    Text {
                                      anchors.verticalCenter: parent.verticalCenter; x: Style.space(8)
                                      width: parent.width - Style.space(16); elide: Text.ElideRight; textFormat: Text.PlainText
                                      text: root.t("lightMenuColorWarmth")
                                      color: lightRow.drawerOpen ? root.accentColor : root.fg
                                      font.family: root.font; font.pixelSize: Style.font.caption; font.bold: lightRow.drawerOpen
                                    }
                                    MouseArea {
                                      id: lmColM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                      onClicked: {
                                        root.themeFieldFocused = false
                                        root.openLightDrawer = lightRow.drawerOpen ? "" : lightRow.light.id
                                        root.openLightMenu = ""
                                      }
                                    }
                                  }

                                  // 3. Rename…
                                  Rectangle {
                                    width: parent.width; height: Style.space(24); radius: Math.max(2, root.corners.small - 1)
                                    color: lmRenM.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
                                    Text {
                                      anchors.verticalCenter: parent.verticalCenter; x: Style.space(8)
                                      width: parent.width - Style.space(16); elide: Text.ElideRight; textFormat: Text.PlainText
                                      text: root.t("mapMenuRename")
                                      color: root.fg; font.family: root.font; font.pixelSize: Style.font.caption
                                    }
                                    MouseArea {
                                      id: lmRenM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                      onClicked: root.openLightRenameDialog(lightRow.light.id)
                                    }
                                  }

                                  // 4. Lamp icon…
                                  Rectangle {
                                    width: parent.width; height: Style.space(24); radius: Math.max(2, root.corners.small - 1)
                                    color: lmIcoM.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
                                    Text {
                                      anchors.verticalCenter: parent.verticalCenter; x: Style.space(8)
                                      width: parent.width - Style.space(16); elide: Text.ElideRight; textFormat: Text.PlainText
                                      text: root.t("mapMenuIcon")
                                      color: root.fg; font.family: root.font; font.pixelSize: Style.font.caption
                                    }
                                    MouseArea {
                                      id: lmIcoM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                      onClicked: root.openLightIconDialog(lightRow.light.id)
                                    }
                                  }

                                  // 5. Wire rule on Map
                                  Rectangle {
                                    width: parent.width; height: Style.space(24); radius: Math.max(2, root.corners.small - 1)
                                    color: lmWireM.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
                                    Text {
                                      anchors.verticalCenter: parent.verticalCenter; x: Style.space(8)
                                      width: parent.width - Style.space(16); elide: Text.ElideRight; textFormat: Text.PlainText
                                      text: root.t("lightMenuWireOnMap")
                                      color: root.fg; font.family: root.font; font.pixelSize: Style.font.caption
                                    }
                                    MouseArea {
                                      id: lmWireM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                      onClicked: root.wireLightOnMap(lightRow.light.id)
                                    }
                                  }

                                  // 6. Pin / Unpin Favorite
                                  Rectangle {
                                    width: parent.width; height: Style.space(24); radius: Math.max(2, root.corners.small - 1)
                                    color: lmPinM.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
                                    Text {
                                      anchors.verticalCenter: parent.verticalCenter; x: Style.space(8)
                                      width: parent.width - Style.space(16); elide: Text.ElideRight; textFormat: Text.PlainText
                                      text: lightRow.lightPinned ? root.t("lightMenuUnpinFav") : root.t("lightMenuPinFav")
                                      color: lightRow.lightPinned ? root.accentColor : root.fg
                                      font.family: root.font; font.pixelSize: Style.font.caption
                                    }
                                    MouseArea {
                                      id: lmPinM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                      onClicked: {
                                        if (root.hostWidget) root.hostWidget.toggleFavorite("light:" + lightRow.light.id)
                                        root.openLightMenu = ""
                                      }
                                    }
                                  }
                                }
                              }

                              // Inline Color / Warmth / Effects / Light Themes Drawer
                              Rectangle {
                                visible: lightRow.drawerOpen
                                width: parent.width
                                height: drawerCol.implicitHeight + Style.space(16)
                                radius: root.corners.control
                                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
                                border.width: 1
                                border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

                                Column {
                                  id: drawerCol
                                  x: Style.space(8)
                                  y: Style.space(8)
                                  width: parent.width - Style.space(16)
                                  spacing: Style.space(8)

                                  // Warmth (4 presets)
                                  Column {
                                    visible: lightRow.light.supports_ct === true
                                    width: parent.width
                                    spacing: Style.space(4)
                                    Text {
                                      textFormat: Text.PlainText
                                      text: root.t("warmth")
                                      color: root.dim
                                      font.family: root.font
                                      font.pixelSize: Style.font.caption
                                    }
                                    Flow {
                                      width: parent.width
                                      spacing: Style.space(5)
                                      Repeater {
                                        model: lightRow.drawerOpen && lightRow.light.supports_ct === true ? root.warmthPresets.length : 0
                                        delegate: Button {
                                          required property int index
                                          readonly property var preset: root.warmthPresets[index]
                                          radius: root.corners.control
                                          text: root.t(preset.key)
                                          bordered: true
                                          selected: lightRow.light.mirek !== null && lightRow.light.mirek !== undefined
                                            && Math.abs(Number(lightRow.light.mirek) - preset.mirek) <= 25
                                          accent: preset.color
                                          foreground: root.fg
                                          fontFamily: root.font
                                          fontSize: Style.font.caption
                                          horizontalPadding: Style.space(7)
                                          verticalPadding: Style.space(2)
                                          onClicked: root.send({ cmd: "light", id: lightRow.light.id, mirek: root.clampMirek(lightRow.light, preset.mirek) })
                                        }
                                      }
                                    }
                                  }

                                  // Color (8 swatches)
                                  Column {
                                    visible: lightRow.light.supports_color === true
                                    width: parent.width
                                    spacing: Style.space(4)
                                    Text {
                                      textFormat: Text.PlainText
                                      text: root.t("color")
                                      color: root.dim
                                      font.family: root.font
                                      font.pixelSize: Style.font.caption
                                    }
                                    Flow {
                                      width: parent.width
                                      spacing: Style.space(6)
                                      Repeater {
                                        model: lightRow.drawerOpen && lightRow.light.supports_color === true ? root.colorPresets.length : 0
                                        delegate: Rectangle {
                                          required property int index
                                          readonly property var cp: root.colorPresets[index]
                                          width: Style.space(22)
                                          height: width
                                          radius: Math.min(root.corners.pill, width / 2)
                                          color: cp.color
                                          border.width: swatchMouse.containsMouse ? 2 : 1
                                          border.color: swatchMouse.containsMouse ? root.fg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)
                                          MouseArea {
                                            id: swatchMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.send({ cmd: "light", id: lightRow.light.id, xy: cp.xy })
                                          }
                                        }
                                      }
                                    }
                                  }

                                  // Native Effects
                                  Column {
                                    visible: (lightRow.light.available_effects || []).length > 0
                                    width: parent.width
                                    spacing: Style.space(4)
                                    Text {
                                      textFormat: Text.PlainText
                                      text: root.t("effects")
                                      color: root.dim
                                      font.family: root.font
                                      font.pixelSize: Style.font.caption
                                    }
                                    Flow {
                                      width: parent.width
                                      spacing: Style.space(5)
                                      Repeater {
                                        model: lightRow.drawerOpen ? (lightRow.light.available_effects || []).length : 0
                                        delegate: Button {
                                          required property int index
                                          readonly property string eff: (lightRow.light.available_effects || [])[index] || "no_effect"
                                          radius: root.corners.control
                                          text: root.effectLabel(eff)
                                          bordered: true
                                          selected: (lightRow.light.effect || "no_effect") === eff
                                          accent: root.accentColor
                                          foreground: root.fg
                                          fontFamily: root.font
                                          fontSize: Style.font.caption
                                          horizontalPadding: Style.space(7)
                                          verticalPadding: Style.space(2)
                                          onClicked: root.send({ cmd: "light", id: lightRow.light.id, effect: eff })
                                        }
                                      }
                                    }
                                  }

                                  // Light Themes (8 built-in + custom with delete + Save current)
                                  Column {
                                    width: parent.width
                                    spacing: Style.space(6)
                                    Text {
                                      textFormat: Text.PlainText
                                      text: root.t("lightThemes")
                                      color: root.dim
                                      font.family: root.font
                                      font.pixelSize: Style.font.caption
                                    }
                                    Flow {
                                      width: parent.width
                                      spacing: Style.space(5)
                                      Repeater {
                                        model: lightRow.drawerOpen ? root.themes.length : 0
                                        delegate: Rectangle {
                                          id: themeChip
                                          required property int index
                                          readonly property var th: root.themes[index] || ({})
                                          readonly property bool custom: th.built_in !== true
                                          height: themeChipRow.implicitHeight + Style.space(6)
                                          width: themeChipRow.implicitWidth + Style.space(12)
                                          radius: root.corners.control
                                          color: themeMouse.containsMouse
                                            ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
                                            : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                                          border.width: 1
                                          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)

                                          MouseArea {
                                            id: themeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.send({ cmd: "theme_apply", theme_id: themeChip.th.id, light_id: lightRow.light.id })
                                          }

                                          Row {
                                            id: themeChipRow
                                            anchors.centerIn: parent
                                            spacing: Style.space(5)
                                            Rectangle {
                                              anchors.verticalCenter: parent.verticalCenter
                                              width: Style.space(8); height: width
                                              radius: Math.min(root.corners.pill, width / 2)
                                              color: themeChip.th.hex || "#ffd27a"
                                            }
                                            Text {
                                              anchors.verticalCenter: parent.verticalCenter
                                              textFormat: Text.PlainText
                                              text: root.themeLabel(themeChip.th)
                                              color: root.fg
                                              font.family: root.font
                                              font.pixelSize: Style.font.caption
                                            }
                                            Text {
                                              visible: themeChip.custom
                                              anchors.verticalCenter: parent.verticalCenter
                                              textFormat: Text.PlainText
                                              text: "×"
                                              color: delThemeMouse.containsMouse ? Commons.Color.urgent : root.dim
                                              font.family: root.font
                                              font.pixelSize: Style.font.bodySmall
                                              font.bold: true
                                              MouseArea {
                                                id: delThemeMouse
                                                anchors.fill: parent
                                                anchors.margins: -Style.space(3)
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.send({ cmd: "theme_delete", id: themeChip.th.id })
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }

                                    // Inline "Save current as theme"
                                    Item {
                                      width: parent.width
                                      height: Math.max(saveThemeField.implicitHeight, saveThemeBtn.implicitHeight)
                                      KeyTextField {
                                        id: saveThemeField
                                        radius: root.corners.control
                                        maximumLength: 40
                                        anchors.left: parent.left
                                        anchors.right: saveThemeBtn.left
                                        anchors.rightMargin: Style.space(6)
                                        anchors.verticalCenter: parent.verticalCenter
                                        font: Qt.font({ family: root.font, pixelSize: Style.font.caption })
                                        placeholderText: root.t("saveThemePlaceholder")
                                        foreground: root.fg
                                        accent: root.accentColor
                                        onActiveFocusChanged: root.themeFieldFocused = activeFocus
                                        onAccepted: saveThemeBtn.saveCurrent()
                                      }
                                      Button {
                                        id: saveThemeBtn
                                        radius: root.corners.control
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.t("saveTheme")
                                        bordered: true
                                        foreground: root.fg
                                        fontFamily: root.font
                                        fontSize: Style.font.caption
                                        horizontalPadding: Style.space(8)
                                        verticalPadding: Style.space(3)
                                        enabled: saveThemeField.text.trim() !== ""
                                        function saveCurrent() {
                                          var nm = saveThemeField.text.trim()
                                          if (!nm) return
                                          root.send({
                                            cmd: "theme_save",
                                            theme: {
                                              name: nm,
                                              hex: lightRow.light.color || "#ffd27a",
                                              mirek: lightRow.light.mirek !== undefined ? lightRow.light.mirek : null,
                                              bri: Math.max(1, Math.min(100, Math.round(Number(lightRow.light.bri || 80)))),
                                              effect: lightRow.light.effect || "no_effect"
                                            }
                                          })
                                          saveThemeField.clear()
                                        }
                                        onClicked: saveCurrent()
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }

                          // Room scenes
                          Flow {
                            visible: roomBlock.isOpen && (roomBlock.room.scenes || []).length > 0
                            width: parent.width
                            topPadding: Style.space(2)
                            spacing: Style.space(6)
                            readonly property int limit: 6
                            readonly property int total: (roomBlock.room.scenes || []).length
                            Repeater {
                              model: roomBlock.isOpen
                                ? (roomBlock.allScenes ? parent.total : Math.min(parent.total, parent.limit)) : 0
                              delegate: Button {
                                radius: root.corners.control
                                required property int index
                                readonly property var scene: (roomBlock.room.scenes || [])[index] || ({})
                                text: scene.name || ""
                                bordered: true
                                selected: scene.active === true
                                accent: root.accentColor
                                foreground: root.fg
                                fontFamily: root.font
                                fontSize: Style.font.caption
                                horizontalPadding: Style.space(8)
                                verticalPadding: Style.space(2)
                                tooltipText: root.t("recallScene")
                                onClicked: root.send({ cmd: "scene", id: scene.id })
                              }
                            }
                            Button {
                              radius: root.corners.control
                              visible: parent.total > parent.limit
                              text: roomBlock.allScenes ? root.t("less") : root.t("more", [parent.total - parent.limit])
                              foreground: root.dim
                              fontFamily: root.font
                              fontSize: Style.font.caption
                              horizontalPadding: Style.space(8)
                              verticalPadding: Style.space(2)
                              onClicked: roomBlock.allScenes = !roomBlock.allScenes
                            }
                          }
                        }
                      }
                    }
                  }
                }

                PanelSeparator { width: parent.width; foreground: root.fg }

                // Action bar: All On, All Off, Refresh
                Flow {
                  width: parent.width
                  spacing: Style.space(8)
                  Button {
                    radius: root.corners.control
                    text: root.confirmAllOnPending ? root.t("confirmAllOnBtn") : root.t("allOn")
                    iconText: "󰛨"
                    bordered: true
                    foreground: root.confirmAllOnPending ? Commons.Color.urgent : root.fg
                    fontFamily: root.font
                    enabled: root.rooms.length > 0
                    tooltipText: root.t("allOnTip")
                    onClicked: {
                      if (root.confirmAllOnSetting && !root.confirmAllOnPending) {
                        root.confirmAllOnPending = true
                      } else {
                        root.confirmAllOnPending = false
                        root.send({ cmd: "all_on", exclude_rooms: root.excludeAllOn })
                      }
                    }
                  }
                  Button {
                    radius: root.corners.control
                    text: root.t("allOff")
                    iconText: "󰐥"
                    bordered: true
                    foreground: root.fg
                    fontFamily: root.font
                    enabled: Number(root.stats.on_count || 0) > 0
                    tooltipText: root.t("allOffTip")
                    onClicked: { root.confirmAllOnPending = false; root.send({ cmd: "all_off" }) }
                  }
                  Button {
                    radius: root.corners.control
                    text: root.t("refresh")
                    iconText: "󰑐"
                    bordered: true
                    foreground: root.fg
                    fontFamily: root.font
                    onClicked: { root.confirmAllOnPending = false; root.send({ cmd: "refresh" }) }
                  }
                }
              }

              // ================================================================ TAB 2: MAP (FLOORPLAN STUDIO)
              MapTab {
                id: mapTab
                visible: root.paired && root.activeTab === "map"
                width: parent.width
                huePaired: root.huePaired
                bar: root.bar
                rooms: root.rooms
                rules: root.rules
                schedules: root.schedules
                synth: root.synth
                floorplan: root.floorplan
                entertainmentAreas: root.entertainmentAreas
                sensors: root.sensors
                motionAreas: root.motionAreas
                showMotionAwareHint: root.showMotionAwareHint
                motionAwareEligibleRooms: root.motionAwareEligibleRooms
                fg: root.fg
                dim: root.dim
                accentColor: root.accentColor
                hasSkin: root.hasSkin
                fontFamily: root.font
                corners: root.corners
                lang: root.lang
                panelHeight: root.effectivePanelHeight
                onSendCommand: function(obj) { root.send(obj) }
                onScheduleSceneRequested: function(roomKind, roomId, sceneId, sceneName) {
                  root.openSceneSchedule(roomKind, roomId, sceneId, sceneName)
                }
                onReturnFocusRequested: keyCatcher.forceActiveFocus()
                onDismissMotionAwareHint: root.motionAwareHintDismissed = true
              }

              // ================================================================ TAB 3: SCHEDULES
              Column {
                visible: root.paired && root.activeTab === "schedules"
                width: parent.width
                spacing: Style.space(8)

                Item {
                  width: parent.width
                  height: Math.max(schedHeader.implicitHeight, newSchedBtn.implicitHeight)
                  PanelSectionHeader {
                    id: schedHeader
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.t("schedulesHeader").toUpperCase()
                    foreground: root.fg
                    fontFamily: root.font
                  }
                  Button {
                    id: newSchedBtn
                    radius: root.corners.control
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.showNewSchedule ? root.t("cancel") : ("+ " + root.t("newSchedule"))
                    bordered: true
                    foreground: root.fg
                    fontFamily: root.font
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(3)
                    onClicked: {
                      root.showNewSchedule = !root.showNewSchedule
                      if (root.showNewSchedule && !root.schedTargetKey && root.scheduleTargetOptions.length > 0)
                        root.schedTargetKey = root.scheduleTargetOptions[0].value
                    }
                  }
                }

                // Inline New Schedule builder
                Rectangle {
                  visible: root.showNewSchedule
                  width: parent.width
                  height: schedForm.implicitHeight + Style.space(18)
                  radius: root.corners.radius
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
                  border.width: 1
                  border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)

                  Column {
                    id: schedForm
                    x: Style.space(10)
                    y: Style.space(9)
                    width: parent.width - Style.space(20)
                    spacing: Style.space(8)

                    KeyTextField {
                      id: schedNameField
                      width: parent.width
                      radius: root.corners.control
                      maximumLength: 60
                      font: Qt.font({ family: root.font, pixelSize: Style.font.caption })
                      placeholderText: root.t("scheduleNamePlaceholder")
                      foreground: root.fg
                      accent: root.accentColor
                    }

                    // Target picker
                    Row {
                      width: parent.width
                      spacing: Style.space(8)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(66)
                        textFormat: Text.PlainText
                        text: root.t("target")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      CompactDropdown {
                        id: schedTargetPicker
                        width: parent.width - Style.space(74)
                        popupRadius: root.corners.radius
                        controlRadius: root.corners.control
                        fontSize: Style.font.caption
                        rowHeight: Style.space(26)
                        popupRowHeight: Style.space(28)
                        showLabel: false
                        fontFamily: root.font
                        accent: root.accentColor
                        options: root.scheduleTargetOptions
                        value: root.validOptionValue(root.scheduleTargetOptions, root.schedTargetKey, 0)
                        onChanged: function(v) {
                          root.schedTargetKey = v
                          schedTargetPicker.value = Qt.binding(function() { return root.validOptionValue(root.scheduleTargetOptions, root.schedTargetKey, 0) })
                        }
                      }
                    }

                    // Trigger type: Time / Sunrise / Sunset
                    Row {
                      width: parent.width
                      spacing: Style.space(8)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(66)
                        textFormat: Text.PlainText
                        text: root.t("trigger")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Flow {
                        width: parent.width - Style.space(74)
                        spacing: Style.space(5)
                        Repeater {
                          model: [
                            { id: "time",    key: "triggerTime" },
                            { id: "sunrise", key: "triggerSunrise" },
                            { id: "sunset",  key: "triggerSunset" }
                          ]
                          delegate: Button {
                            required property var modelData
                            radius: root.corners.control
                            text: root.t(modelData.key)
                            bordered: true
                            selected: root.schedTrigger === modelData.id
                            enabled: modelData.id === "time" || root.scheduleModeSetting !== "local"
                            accent: root.accentColor
                            foreground: root.fg
                            fontFamily: root.font
                            fontSize: Style.font.caption
                            horizontalPadding: Style.space(7)
                            verticalPadding: Style.space(2)
                            onClicked: root.schedTrigger = modelData.id
                          }
                        }
                      }
                    }

                    Text {
                      visible: root.scheduleModeSetting === "local"
                      width: parent.width
                      wrapMode: Text.WordWrap
                      textFormat: Text.PlainText
                      text: root.t("localSolarHint")
                      color: root.dim
                      font.family: root.font
                      font.pixelSize: Style.font.caption
                    }

                    // Time input OR Solar offset stepper
                    Row {
                      visible: root.schedTrigger === "time" || root.scheduleModeSetting === "local"
                      width: parent.width
                      spacing: Style.space(8)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(66)
                        textFormat: Text.PlainText
                        text: root.t("triggerTime")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      KeyTextField {
                        id: schedTimeField
                        width: Style.space(120)
                        radius: root.corners.control
                        maximumLength: 5
                        text: "07:30"
                        font: Qt.font({ family: root.font, pixelSize: Style.font.caption })
                        placeholderText: root.t("timePlaceholder")
                        foreground: root.fg
                        accent: root.accentColor
                      }
                    }

                    Row {
                      visible: root.schedTrigger !== "time" && root.scheduleModeSetting !== "local"
                      width: parent.width
                      spacing: Style.space(8)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(66)
                        textFormat: Text.PlainText
                        text: root.t("offsetMinLabel")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        radius: root.corners.control; text: "−5"; bordered: true; foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(6); verticalPadding: Style.space(2)
                        onClicked: root.schedOffsetMin = Math.max(-120, root.schedOffsetMin - 5)
                      }
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: (root.schedOffsetMin > 0 ? "+" : "") + root.schedOffsetMin + " min"
                        color: root.fg
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        radius: root.corners.control; text: "+5"; bordered: true; foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(6); verticalPadding: Style.space(2)
                        onClicked: root.schedOffsetMin = Math.min(120, root.schedOffsetMin + 5)
                      }
                    }

                    // Weekday pills
                    Row {
                      width: parent.width
                      spacing: Style.space(8)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(66)
                        textFormat: Text.PlainText
                        text: root.t("days")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Flow {
                        width: parent.width - Style.space(74)
                        spacing: Style.space(4)
                        Repeater {
                          model: root.dayCodes
                          delegate: Button {
                            required property string modelData
                            readonly property bool chosen: root.schedDays.indexOf(modelData) >= 0
                            radius: root.corners.control
                            text: root.dayLabel(modelData)
                            bordered: true
                            selected: chosen
                            accent: root.accentColor
                            foreground: root.fg
                            fontFamily: root.font
                            fontSize: Style.font.caption
                            horizontalPadding: Style.space(6)
                            verticalPadding: Style.space(2)
                            onClicked: {
                              var next = root.schedDays.slice()
                              var idx = next.indexOf(modelData)
                              if (idx >= 0) next.splice(idx, 1)
                              else next.push(modelData)
                              root.schedDays = next
                            }
                          }
                        }
                      }
                    }

                    // Action (On / Off)
                    Row {
                      width: parent.width
                      spacing: Style.space(8)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(66)
                        textFormat: Text.PlainText
                        text: root.t("action")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Row {
                        spacing: Style.space(6)
                        Button {
                          radius: root.corners.control; text: root.t("actionOn"); bordered: true
                          selected: root.schedAction === "on"; accent: root.accentColor
                          foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                          horizontalPadding: Style.space(8); verticalPadding: Style.space(2)
                          onClicked: root.schedAction = "on"
                        }
                        Button {
                          radius: root.corners.control; text: root.t("actionOff"); bordered: true
                          selected: root.schedAction === "off"; accent: root.accentColor
                          foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                          horizontalPadding: Style.space(8); verticalPadding: Style.space(2)
                          onClicked: root.schedAction = "off"
                        }
                        Button {
                          radius: root.corners.control; text: root.t("actionScene"); bordered: true
                          selected: root.schedAction === "scene"; accent: root.accentColor
                          enabled: root.scheduleSceneOptions.length > 0
                          foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                          horizontalPadding: Style.space(8); verticalPadding: Style.space(2)
                          onClicked: {
                            root.schedAction = "scene"
                            if (!root.schedSceneId && root.scheduleSceneOptions.length > 0)
                              root.schedSceneId = root.scheduleSceneOptions[0].value
                          }
                        }
                      }
                    }

                    // Scene picker (when Action == Scene)
                    Row {
                      visible: root.schedAction === "scene"
                      width: parent.width
                      spacing: Style.space(8)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(66)
                        textFormat: Text.PlainText
                        text: root.t("sceneLabel")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      CompactDropdown {
                        id: schedScenePicker
                        width: parent.width - Style.space(74)
                        popupRadius: root.corners.radius
                        controlRadius: root.corners.control
                        fontSize: Style.font.caption
                        rowHeight: Style.space(26)
                        popupRowHeight: Style.space(28)
                        showLabel: false
                        fontFamily: root.font
                        accent: root.accentColor
                        options: root.scheduleSceneOptions
                        value: root.validOptionValue(root.scheduleSceneOptions, root.schedSceneId, 0)
                        onChanged: function(v) {
                          root.schedSceneId = v
                          schedScenePicker.value = Qt.binding(function() { return root.validOptionValue(root.scheduleSceneOptions, root.schedSceneId, 0) })
                        }
                      }
                    }

                    // Brightness slider (when Action == On)
                    Item {
                      visible: root.schedAction === "on"
                      width: parent.width
                      height: Math.max(schedBriLbl.implicitHeight, schedBriSlider.implicitHeight)
                      Text {
                        id: schedBriLbl
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(66)
                        textFormat: Text.PlainText
                        text: root.t("brightness")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      PanelSlider {
                        id: schedBriSlider
                        anchors.left: schedBriLbl.right
                        anchors.leftMargin: Style.space(8)
                        anchors.right: schedBriPct.left
                        anchors.rightMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                        bar: root.bar
                        minimum: 1; maximum: 100; step: 5
                        fillColor: root.accentColor
                        value: root.schedBri
                        onMoved: function(v) { root.schedBri = Math.round(v) }
                      }
                      Text {
                        id: schedBriPct
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(34)
                        horizontalAlignment: Text.AlignRight
                        textFormat: Text.PlainText
                        text: Math.round(schedBriSlider.liveValue) + "%"
                        color: root.fg
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                    }

                    // Fade pills
                    Row {
                      width: parent.width
                      spacing: Style.space(8)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(66)
                        textFormat: Text.PlainText
                        text: root.t("fade")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Flow {
                        width: parent.width - Style.space(74)
                        spacing: Style.space(5)
                        Repeater {
                          model: [0, 5, 15, 30]
                          delegate: Button {
                            required property int modelData
                            radius: root.corners.control
                            text: modelData === 0 ? root.t("fadeInstant") : root.t("fadeMin", [modelData])
                            bordered: true
                            selected: root.schedFadeMin === modelData
                            accent: root.accentColor
                            foreground: root.fg
                            fontFamily: root.font
                            fontSize: Style.font.caption
                            horizontalPadding: Style.space(7)
                            verticalPadding: Style.space(2)
                            onClicked: root.schedFadeMin = modelData
                          }
                        }
                      }
                    }

                    // Submit row
                    Row {
                      spacing: Style.space(8)
                      Button {
                        radius: root.corners.control
                        text: root.t("createSchedule")
                        iconText: "󰄬"
                        bordered: true
                        foreground: root.fg
                        fontFamily: root.font
                        fontSize: Style.font.caption
                        enabled: {
                          var tkey = root.validOptionValue(root.scheduleTargetOptions, root.schedTargetKey, 0)
                          if (!tkey) return false
                          if (root.schedAction === "scene" && !root.validOptionValue(root.scheduleSceneOptions, root.schedSceneId, 0)) return false
                          var trig = root.scheduleModeSetting === "local" ? "time" : root.schedTrigger
                          if (trig === "time" && !root.validHHMM(schedTimeField.text)) return false
                          return true
                        }
                        onClicked: {
                          var tkey = root.validOptionValue(root.scheduleTargetOptions, root.schedTargetKey, 0)
                          var idx = tkey.indexOf(":")
                          if (idx < 0) return
                          var tkind = tkey.slice(0, idx)
                          var tid = tkey.slice(idx + 1)
                          var trig = root.scheduleModeSetting === "local" ? "time" : root.schedTrigger
                          var sid = root.schedAction === "scene" ? root.validOptionValue(root.scheduleSceneOptions, root.schedSceneId, 0) : ""
                          root.send({
                            cmd: "schedule_create",
                            source: root.scheduleModeSetting,
                            name: schedNameField.text.trim() || root.t("schedulesHeader"),
                            target_kind: tkind,
                            target_id: tid,
                            trigger_kind: trig,
                            time: schedTimeField.text.trim(),
                            offset_min: root.schedOffsetMin,
                            days: root.schedDays,
                            action: root.schedAction,
                            scene_id: sid,
                            bri: root.schedAction === "on" ? root.schedBri : null,
                            fade_min: root.schedFadeMin,
                            enabled: true
                          })
                          schedNameField.clear()
                          root.schedSceneId = ""
                          root.schedDays = []
                          root.showNewSchedule = false
                        }
                      }
                    }
                  }
                }

                Text {
                  visible: root.schedules.length === 0 && !root.showNewSchedule
                  textFormat: Text.PlainText
                  text: root.t("noSchedules")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }

                // Schedule cards
                Repeater {
                  model: root.schedules.length
                  delegate: Rectangle {
                    id: schedCard
                    required property int index
                    readonly property var sched: root.schedules[index] || ({})
                    readonly property bool isOn: sched.enabled === true
                    readonly property bool isLocal: sched.source === "local"
                    width: parent.width
                    height: schedCardRow.implicitHeight + Style.space(16)
                    radius: root.corners.radius
                    color: isOn ? (root.hasSkin ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.11) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)) : (root.hasSkin ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.05) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03))
                    border.width: 1
                    border.color: isOn ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, root.hasSkin ? 0.50 : 0.35) : root.skinCardBorder

                    Item {
                      id: schedCardRow
                      x: Style.space(10)
                      y: Style.space(8)
                      width: parent.width - Style.space(20)
                      implicitHeight: Math.max(schedInfoCol.implicitHeight, schedSwitch.implicitHeight)
                      height: implicitHeight

                      Column {
                        id: schedInfoCol
                        anchors.left: parent.left
                        anchors.right: schedSwitch.left
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(3)
                        Row {
                          spacing: Style.space(6)
                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: String(schedCard.sched.name || "")
                            color: schedCard.isOn ? root.fg : root.dim
                            font.family: root.font
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                          }
                          Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: badgeTxt.implicitWidth + Style.space(8)
                            height: badgeTxt.implicitHeight + Style.space(2)
                            radius: root.corners.small
                            color: schedCard.isLocal
                              ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                              : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
                            Text {
                              id: badgeTxt
                              anchors.centerIn: parent
                              textFormat: Text.PlainText
                              text: schedCard.isLocal ? root.t("badgeLocal") : root.t("badgeBridge")
                              color: schedCard.isLocal ? root.accentColor : root.dim
                              font.family: root.font
                              font.pixelSize: Math.max(9, Style.font.caption - 1)
                            }
                          }
                        }
                        Text {
                          width: parent.width
                          wrapMode: Text.WordWrap
                          textFormat: Text.PlainText
                          text: root.formatScheduleSummary(schedCard.sched)
                          color: root.dim
                          font.family: root.font
                          font.pixelSize: Style.font.caption
                        }
                      }

                      ToggleSwitch {
                        id: schedSwitch
                        anchors.right: schedDelBtn.left
                        anchors.rightMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                        cursorRing: false
                        rounded: root.corners.pill > 0
                        trackHeight: Style.space(16)
                        checked: schedCard.isOn
                        foreground: root.fg
                        accent: root.accentColor
                        onToggled: root.send({ cmd: "schedule_toggle", id: schedCard.sched.id, enabled: !schedCard.isOn })
                      }

                      Button {
                        id: schedDelBtn
                        radius: root.corners.control
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property bool confirming: root.confirmDeleteSchedule !== "" && root.confirmDeleteSchedule === schedCard.sched.id
                        iconText: confirming ? "" : "󰆴"
                        text: confirming ? root.t("confirmDelete") : ""
                        iconSize: Style.font.caption
                        horizontalPadding: Style.space(4)
                        verticalPadding: Style.space(2)
                        foreground: confirming ? Commons.Color.urgent : root.dim
                        bordered: confirming
                        fontFamily: root.font
                        tooltipText: confirming ? root.t("confirmDeleteTip") : root.t("deleteTip")
                        onClicked: {
                          if (confirming) {
                            root.confirmDeleteSchedule = ""
                            root.send({ cmd: "schedule_delete", id: schedCard.sched.id })
                          } else {
                            root.confirmDeleteSchedule = String(schedCard.sched.id || "")
                            confirmDeleteTimer.restart()
                          }
                        }
                      }
                    }
                  }
                }
              }

              // ================================================================ TAB 3: RULES
              Column {
                visible: root.paired && root.activeTab === "rules"
                width: parent.width
                spacing: Style.space(8)

                Item {
                  width: parent.width
                  height: Math.max(rulesHeader.implicitHeight, newRuleBtn.implicitHeight)
                  PanelSectionHeader {
                    id: rulesHeader
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.t("rulesHeader").toUpperCase()
                    foreground: root.fg
                    fontFamily: root.font
                  }
                  Button {
                    id: newRuleBtn
                    radius: root.corners.control
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.showNewRule ? root.t("cancel") : ("+ " + root.t("newRule"))
                    bordered: true
                    foreground: root.fg
                    fontFamily: root.font
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(3)
                    onClicked: {
                      root.showNewRule = !root.showNewRule
                      if (root.showNewRule && root.ruleTriggerOptions.length >= 1 && root.ruleEntityOptions.length >= 1) {
                        if (!root.ruleTriggerKey) {
                          root.ruleTriggerKey = root.ruleTriggerOptions[0].value
                          var tk0 = root.triggerKindOf(root.ruleTriggerKey)
                          root.ruleTriggerState = root.triggerStateChoices(tk0)[0].id
                        }
                        if (!root.ruleTargetKey || root.ruleTargetKey === root.ruleTriggerKey) {
                          for (var ti = 0; ti < root.ruleEntityOptions.length; ti++) {
                            if (root.ruleEntityOptions[ti].value !== root.ruleTriggerKey) {
                              root.ruleTargetKey = root.ruleEntityOptions[ti].value
                              break
                            }
                          }
                        }
                      }
                    }
                  }
                }

                // Pause all rules toggle
                Item {
                  width: parent.width
                  height: Math.max(pauseLbl.implicitHeight, pauseToggle.implicitHeight)
                  Text {
                    id: pauseLbl
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.t("pauseRules")
                    color: root.rulesPaused ? Commons.Color.urgent : root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  ToggleSwitch {
                    id: pauseToggle
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    cursorRing: false
                    rounded: root.corners.pill > 0
                    trackHeight: Style.space(16)
                    checked: root.rulesPaused
                    foreground: root.fg
                    accent: Commons.Color.urgent
                    onToggled: root.send({ cmd: "rules_pause", paused: !root.rulesPaused })
                  }
                }

                // Inline New Rule builder
                Rectangle {
                  visible: root.showNewRule
                  width: parent.width
                  height: ruleForm.implicitHeight + Style.space(18)
                  radius: root.corners.radius
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
                  border.width: 1
                  border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)

                  Column {
                    id: ruleForm
                    x: Style.space(10)
                    y: Style.space(9)
                    width: parent.width - Style.space(20)
                    spacing: Style.space(8)

                    KeyTextField {
                      id: ruleNameField
                      width: parent.width
                      radius: root.corners.control
                      maximumLength: 60
                      font: Qt.font({ family: root.font, pixelSize: Style.font.caption })
                      placeholderText: root.t("ruleNamePlaceholder")
                      foreground: root.fg
                      accent: root.accentColor
                    }

                    // Type: Follow / Exclusive / Companion
                    Row {
                      width: parent.width
                      spacing: Style.space(8)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(56)
                        textFormat: Text.PlainText
                        text: root.t("ruleType")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Flow {
                        width: parent.width - Style.space(64)
                        spacing: Style.space(5)
                        Repeater {
                          model: [
                            { id: "follow",    key: "ruleFollow" },
                            { id: "exclusive", key: "ruleExclusive" },
                            { id: "companion", key: "ruleCompanion" }
                          ]
                          delegate: Button {
                            required property var modelData
                            radius: root.corners.control
                            text: root.t(modelData.key)
                            bordered: true
                            selected: root.ruleKind === modelData.id
                            accent: root.accentColor
                            foreground: root.fg
                            fontFamily: root.font
                            fontSize: Style.font.caption
                            horizontalPadding: Style.space(7)
                            verticalPadding: Style.space(2)
                            onClicked: {
                              root.ruleKind = modelData.id
                              root.ruleMirrorOff = (modelData.id === "follow")
                              root.ruleOnlyIfOff = (modelData.id === "companion")
                            }
                          }
                        }
                      }
                    }

                    // Trigger picker (rooms, lights, MotionAware areas, sensors)
                    Row {
                      width: parent.width
                      spacing: Style.space(8)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(56)
                        textFormat: Text.PlainText
                        text: root.t("ruleTrigger")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      CompactDropdown {
                        id: ruleTriggerPicker
                        width: parent.width - Style.space(64)
                        popupRadius: root.corners.radius
                        controlRadius: root.corners.control
                        fontSize: Style.font.caption
                        rowHeight: Style.space(26)
                        popupRowHeight: Style.space(28)
                        showLabel: false
                        fontFamily: root.font
                        accent: root.accentColor
                        options: root.ruleTriggerOptions
                        value: root.validOptionValue(root.ruleTriggerOptions, root.ruleTriggerKey, 0)
                        onChanged: function(v) {
                          root.ruleTriggerKey = v
                          var tk = root.triggerKindOf(v)
                          var choices = root.triggerStateChoices(tk)
                          root.ruleTriggerState = choices.length > 0 ? choices[0].id : "on"
                          if (tk === "motion" || tk === "motion_area" || tk === "contact" || tk === "button") {
                            root.ruleMatchBri = false
                            if (tk === "button") root.ruleMirrorOff = false
                          }
                          ruleTriggerPicker.value = Qt.binding(function() { return root.validOptionValue(root.ruleTriggerOptions, root.ruleTriggerKey, 0) })
                        }
                      }
                    }

                    // Context-aware Trigger State ("When")
                    Row {
                      width: parent.width
                      spacing: Style.space(8)
                      readonly property string curTrigKind: root.triggerKindOf(root.validOptionValue(root.ruleTriggerOptions, root.ruleTriggerKey, 0))
                      readonly property var stateChoices: root.triggerStateChoices(curTrigKind)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(56)
                        textFormat: Text.PlainText
                        text: root.t("mapTriggerState")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Flow {
                        width: parent.width - Style.space(64)
                        spacing: Style.space(5)
                        Repeater {
                          model: parent.parent.stateChoices
                          delegate: Button {
                            required property var modelData
                            radius: root.corners.control
                            text: root.t(modelData.key)
                            bordered: true
                            selected: root.ruleTriggerState === modelData.id
                            accent: root.accentColor
                            foreground: root.fg
                            fontFamily: root.font
                            fontSize: Style.font.caption
                            horizontalPadding: Style.space(7)
                            verticalPadding: Style.space(2)
                            onClicked: root.ruleTriggerState = modelData.id
                          }
                        }
                      }
                    }

                    // Target picker
                    Row {
                      width: parent.width
                      spacing: Style.space(8)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(56)
                        textFormat: Text.PlainText
                        text: root.t("ruleTarget")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      CompactDropdown {
                        id: ruleTargetPicker
                        width: parent.width - Style.space(64)
                        popupRadius: root.corners.radius
                        controlRadius: root.corners.control
                        fontSize: Style.font.caption
                        rowHeight: Style.space(26)
                        popupRowHeight: Style.space(28)
                        showLabel: false
                        fontFamily: root.font
                        accent: root.accentColor
                        options: root.ruleEntityOptions
                        value: root.validOptionValue(root.ruleEntityOptions, root.ruleTargetKey, 1)
                        onChanged: function(v) {
                          root.ruleTargetKey = v
                          ruleTargetPicker.value = Qt.binding(function() { return root.validOptionValue(root.ruleEntityOptions, root.ruleTargetKey, 1) })
                        }
                      }
                    }

                    // Options: mirrorOff, matchBri, onlyIfOff (context-aware for sensors)
                    Flow {
                      readonly property string curTrigKind: root.triggerKindOf(root.validOptionValue(root.ruleTriggerOptions, root.ruleTriggerKey, 0))
                      readonly property bool isSensorTrig: curTrigKind === "motion" || curTrigKind === "motion_area" || curTrigKind === "contact" || curTrigKind === "button"
                      width: parent.width
                      spacing: Style.space(6)
                      Button {
                        visible: parent.curTrigKind !== "button"
                        radius: root.corners.control
                        text: (root.ruleMirrorOff ? "✓ " : "") + root.t("mirrorOff")
                        bordered: true; selected: root.ruleMirrorOff; accent: root.accentColor
                        foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
                        onClicked: root.ruleMirrorOff = !root.ruleMirrorOff
                      }
                      Button {
                        visible: !parent.isSensorTrig
                        radius: root.corners.control
                        text: (root.ruleMatchBri ? "✓ " : "") + root.t("matchBri")
                        bordered: true; selected: root.ruleMatchBri; accent: root.accentColor
                        foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
                        onClicked: root.ruleMatchBri = !root.ruleMatchBri
                      }
                      Button {
                        radius: root.corners.control
                        text: (root.ruleOnlyIfOff ? "✓ " : "") + root.t("onlyIfOff")
                        bordered: true; selected: root.ruleOnlyIfOff; accent: root.accentColor
                        foreground: root.fg; fontFamily: root.font; fontSize: Style.font.caption
                        horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
                        onClicked: root.ruleOnlyIfOff = !root.ruleOnlyIfOff
                      }
                    }

                    // Optional time window
                    Column {
                      width: parent.width
                      spacing: Style.space(4)
                      Text {
                        textFormat: Text.PlainText
                        text: root.t("timeWindow")
                        color: root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.caption
                      }
                      Row {
                        spacing: Style.space(6)
                        KeyTextField {
                          id: ruleStartField
                          width: Style.space(104)
                          radius: root.corners.control
                          maximumLength: 5
                          font: Qt.font({ family: root.font, pixelSize: Style.font.caption })
                          placeholderText: root.t("timeStartPlaceholder")
                          foreground: root.fg
                          accent: root.accentColor
                        }
                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          textFormat: Text.PlainText
                          text: "–"
                          color: root.dim
                          font.family: root.font
                          font.pixelSize: Style.font.caption
                        }
                        KeyTextField {
                          id: ruleEndField
                          width: Style.space(104)
                          radius: root.corners.control
                          maximumLength: 5
                          font: Qt.font({ family: root.font, pixelSize: Style.font.caption })
                          placeholderText: root.t("timeEndPlaceholder")
                          foreground: root.fg
                          accent: root.accentColor
                        }
                      }
                    }

                    Button {
                      radius: root.corners.control
                      text: root.t("saveRule")
                      iconText: "󰄬"
                      bordered: true
                      foreground: root.fg
                      fontFamily: root.font
                      fontSize: Style.font.caption
                      enabled: {
                        var trk = root.validOptionValue(root.ruleTriggerOptions, root.ruleTriggerKey, 0)
                        var tgk = root.validOptionValue(root.ruleEntityOptions, root.ruleTargetKey, 1)
                        if (!trk || !tgk || trk === tgk) return false
                        var ts = ruleStartField.text.trim()
                        var te = ruleEndField.text.trim()
                        if (ts !== "" || te !== "") return root.validHHMM(ts) && root.validHHMM(te)
                        return true
                      }
                      onClicked: {
                        var trk = root.validOptionValue(root.ruleTriggerOptions, root.ruleTriggerKey, 0)
                        var tgk = root.validOptionValue(root.ruleEntityOptions, root.ruleTargetKey, 1)
                        var i1 = trk.indexOf(":"), i2 = tgk.indexOf(":")
                        if (i1 < 0 || i2 < 0 || trk === tgk) return
                        var tk = trk.slice(0, i1)
                        var isSensor = tk === "motion" || tk === "motion_area" || tk === "contact" || tk === "button"
                        var choices = root.triggerStateChoices(tk)
                        var validSt = choices.length > 0 ? choices[0].id : "on"
                        for (var ci = 0; ci < choices.length; ci++) {
                          if (choices[ci].id === root.ruleTriggerState) { validSt = choices[ci].id; break }
                        }
                        root.send({
                          cmd: "rule_save",
                          rule: {
                            name: ruleNameField.text.trim() || root.ruleKindLabel(root.ruleKind),
                            enabled: true,
                            kind: root.ruleKind,
                            trigger_kind: tk,
                            trigger_id: trk.slice(i1 + 1),
                            trigger_state: validSt,
                            targets: [{
                              kind: tgk.slice(0, i2),
                              id: tgk.slice(i2 + 1),
                              action: root.ruleKind === "exclusive" ? "off" : "on",
                              bri: null,
                              scene_id: ""
                            }],
                            mirror_off: tk === "button" ? false : root.ruleMirrorOff,
                            match_bri: isSensor ? false : root.ruleMatchBri,
                            only_if_off: root.ruleOnlyIfOff,
                            time_start: ruleStartField.text.trim(),
                            time_end: ruleEndField.text.trim()
                          }
                        })
                        ruleNameField.clear()
                        ruleStartField.clear()
                        ruleEndField.clear()
                        root.showNewRule = false
                      }
                    }
                  }
                }

                Text {
                  visible: root.rules.length === 0 && !root.showNewRule
                  textFormat: Text.PlainText
                  text: root.t("noRules")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }

                // Rule cards
                Repeater {
                  model: root.rules.length
                  delegate: Rectangle {
                    id: ruleCard
                    required property int index
                    readonly property var rule: root.rules[index] || ({})
                    readonly property bool isOn: rule.enabled === true && !root.rulesPaused
                    width: parent.width
                    height: ruleCardRow.implicitHeight + Style.space(16)
                    radius: root.corners.radius
                    color: isOn ? (root.hasSkin ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.11) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)) : (root.hasSkin ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.05) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03))
                    border.width: 1
                    border.color: isOn ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, root.hasSkin ? 0.50 : 0.35) : root.skinCardBorder

                    Item {
                      id: ruleCardRow
                      x: Style.space(10)
                      y: Style.space(8)
                      width: parent.width - Style.space(20)
                      implicitHeight: Math.max(ruleInfoCol.implicitHeight, ruleSwitch.implicitHeight)
                      height: implicitHeight

                      Column {
                        id: ruleInfoCol
                        anchors.left: parent.left
                        anchors.right: ruleSwitch.left
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(3)
                        Row {
                          spacing: Style.space(6)
                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: String(ruleCard.rule.name || "")
                            color: ruleCard.isOn ? root.fg : root.dim
                            font.family: root.font
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                          }
                          Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: rKindTxt.implicitWidth + Style.space(8)
                            height: rKindTxt.implicitHeight + Style.space(2)
                            radius: root.corners.small
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.2)
                            Text {
                              id: rKindTxt
                              anchors.centerIn: parent
                              textFormat: Text.PlainText
                              text: root.ruleKindLabel(ruleCard.rule.kind)
                              color: root.accentColor
                              font.family: root.font
                              font.pixelSize: Math.max(9, Style.font.caption - 1)
                            }
                          }
                        }
                        Text {
                          width: parent.width
                          wrapMode: Text.WordWrap
                          textFormat: Text.PlainText
                          text: root.formatRuleSummary(ruleCard.rule)
                          color: root.dim
                          font.family: root.font
                          font.pixelSize: Style.font.caption
                        }
                      }

                      ToggleSwitch {
                        id: ruleSwitch
                        anchors.right: ruleDelBtn.left
                        anchors.rightMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                        cursorRing: false
                        rounded: root.corners.pill > 0
                        trackHeight: Style.space(16)
                        checked: ruleCard.rule.enabled === true
                        foreground: root.fg
                        accent: root.accentColor
                        onToggled: root.send({ cmd: "rule_toggle", id: ruleCard.rule.id, enabled: ruleCard.rule.enabled !== true })
                      }

                      Button {
                        id: ruleDelBtn
                        radius: root.corners.control
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property bool confirming: root.confirmDeleteRule !== "" && root.confirmDeleteRule === ruleCard.rule.id
                        iconText: confirming ? "" : "󰆴"
                        text: confirming ? root.t("confirmDelete") : ""
                        iconSize: Style.font.caption
                        horizontalPadding: Style.space(4)
                        verticalPadding: Style.space(2)
                        foreground: confirming ? Commons.Color.urgent : root.dim
                        bordered: confirming
                        fontFamily: root.font
                        tooltipText: confirming ? root.t("confirmDeleteTip") : root.t("deleteTip")
                        onClicked: {
                          if (confirming) {
                            root.confirmDeleteRule = ""
                            root.send({ cmd: "rule_delete", id: ruleCard.rule.id })
                          } else {
                            root.confirmDeleteRule = String(ruleCard.rule.id || "")
                            confirmDeleteTimer.restart()
                          }
                        }
                      }
                    }
                  }
                }

                // Recent activity log
                PanelSeparator { width: parent.width; foreground: root.fg }
                PanelSectionHeader { text: root.t("recentActivity").toUpperCase(); foreground: root.fg; fontFamily: root.font }

                Text {
                  visible: root.ruleLog.length === 0
                  textFormat: Text.PlainText
                  text: root.t("noActivity")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }

                Column {
                  visible: root.ruleLog.length > 0
                  width: parent.width
                  spacing: Style.space(4)
                  Repeater {
                    model: Math.min(root.ruleLog.length, 8)
                    delegate: Text {
                      required property int index
                      readonly property var entry: root.ruleLog[root.ruleLog.length - 1 - index] || ({})
                      width: parent.width
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      text: root.formatLogTime(entry.ts) + " · " + String(entry.rule_name || "") + " · " + String(entry.detail || "")
                      color: root.dim
                      font.family: root.font
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }

              // ================================================================ TAB 4: SYNTH
              Column {
                visible: root.paired && root.activeTab === "synth"
                width: parent.width
                spacing: Style.space(10)

                // Header + Beat indicator + Start/Stop button
                Item {
                  width: parent.width
                  height: Math.max(synthHdr.implicitHeight, synthToggleBtn.implicitHeight)
                  PanelSectionHeader {
                    id: synthHdr
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.t("synthHeader").toUpperCase()
                    foreground: root.fg
                    fontFamily: root.font
                  }
                  Rectangle {
                    id: beatPill
                    anchors.right: synthToggleBtn.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    width: beatTxt.implicitWidth + Style.space(12)
                    height: beatTxt.implicitHeight + Style.space(6)
                    radius: Math.min(root.corners.pill, height / 2)
                    color: (root.synth.running && root.synth.beat)
                      ? root.accentColor
                      : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1)
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text {
                      id: beatTxt
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: "● " + root.t("synthBeat")
                      color: (root.synth.running && root.synth.beat) ? root.onTint(root.accentColor) : root.dim
                      font.family: root.font
                      font.pixelSize: Style.font.caption
                      font.bold: root.synth.running && root.synth.beat
                    }
                  }
                  Button {
                    id: synthToggleBtn
                    radius: root.corners.control
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.synth.running ? root.t("synthStop") : root.t("synthStart")
                    iconText: root.synth.running ? "󰓛" : "󰐊"
                    bordered: true
                    selected: root.synth.running === true
                    accent: root.accentColor
                    foreground: root.fg
                    fontFamily: root.font
                    fontSize: Style.font.caption
                    onClicked: root.send({ cmd: "synth_toggle" })
                  }
                }

                // Live Bass / Mids / Treble meters
                Rectangle {
                  width: parent.width
                  height: metersCol.implicitHeight + Style.space(16)
                  radius: root.corners.radius
                  color: root.skinCardFill
                  border.width: 1
                  border.color: root.skinCardBorder
                  Column {
                    id: metersCol
                    x: Style.space(10)
                    y: Style.space(8)
                    width: parent.width - Style.space(20)
                    spacing: Style.space(6)
                    Meter { label: root.t("synthBass");   ratio: Number(root.synth.bass || 0);   fillColor: "#ff2e93" }
                    Meter { label: root.t("synthMids");   ratio: Number(root.synth.mids || 0);   fillColor: root.accentColor }
                    Meter { label: root.t("synthTreble"); ratio: Number(root.synth.treble || 0); fillColor: "#00d2ff" }
                  }
                }

                // Source pills
                Column {
                  width: parent.width
                  spacing: Style.space(4)
                  Text {
                    textFormat: Text.PlainText
                    text: root.t("synthSource")
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  Flow {
                    width: parent.width
                    spacing: Style.space(6)
                    Repeater {
                      model: [
                        { id: "system", key: "srcSystem" },
                        { id: "mic",    key: "srcMic" },
                        { id: "demo",   key: "srcDemo" }
                      ]
                      delegate: Button {
                        required property var modelData
                        radius: root.corners.control
                        text: root.t(modelData.key)
                        bordered: true
                        selected: root.synth.source === modelData.id
                        accent: root.accentColor
                        foreground: root.fg
                        fontFamily: root.font
                        fontSize: Style.font.caption
                        horizontalPadding: Style.space(8)
                        verticalPadding: Style.space(2)
                        onClicked: root.send({ cmd: "synth_config", source: modelData.id })
                      }
                    }
                  }
                }

                // Mode pills
                Column {
                  width: parent.width
                  spacing: Style.space(4)
                  Text {
                    textFormat: Text.PlainText
                    text: root.t("synthMode")
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  Flow {
                    width: parent.width
                    spacing: Style.space(6)
                    Repeater {
                      model: [
                        { id: "club",    key: "modeClub" },
                        { id: "chill",   key: "modeChill" },
                        { id: "ambient", key: "modeAmbient" },
                        { id: "strobe",  key: "modeStrobe" }
                      ]
                      delegate: Button {
                        required property var modelData
                        radius: root.corners.control
                        text: root.t(modelData.key)
                        bordered: true
                        selected: root.synth.mode === modelData.id
                        accent: root.accentColor
                        foreground: root.fg
                        fontFamily: root.font
                        fontSize: Style.font.caption
                        horizontalPadding: Style.space(8)
                        verticalPadding: Style.space(2)
                        onClicked: root.send({ cmd: "synth_config", mode: modelData.id })
                      }
                    }
                  }
                }

                // Palette pills
                Column {
                  width: parent.width
                  spacing: Style.space(4)
                  Text {
                    textFormat: Text.PlainText
                    text: root.t("synthPalette")
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  Flow {
                    width: parent.width
                    spacing: Style.space(6)
                    Repeater {
                      model: root.synthPaletteDefs.length
                      delegate: Rectangle {
                        id: palChip
                        required property int index
                        readonly property var pal: root.synthPaletteDefs[index]
                        readonly property bool chosen: root.synth.palette === pal.id
                        height: palRow.implicitHeight + Style.space(6)
                        width: palRow.implicitWidth + Style.space(12)
                        radius: root.corners.control
                        color: chosen
                          ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                          : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, palMouse.containsMouse ? 0.12 : 0.05)
                        border.width: 1
                        border.color: chosen ? root.accentColor : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15)
                        MouseArea {
                          id: palMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.send({ cmd: "synth_config", palette: palChip.pal.id })
                        }
                        Row {
                          id: palRow
                          anchors.centerIn: parent
                          spacing: Style.space(4)
                          Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.space(2)
                            Repeater {
                              model: palChip.pal.colors
                              delegate: Rectangle {
                                required property string modelData
                                width: Style.space(6); height: width
                                radius: Math.min(root.corners.pill, width / 2)
                                color: modelData
                              }
                            }
                          }
                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: root.t(palChip.pal.key)
                            color: root.fg
                            font.family: root.font
                            font.pixelSize: Style.font.caption
                          }
                        }
                      }
                    }
                  }
                }

                // Target room dropdown
                Row {
                  width: parent.width
                  spacing: Style.space(10)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(96)
                    textFormat: Text.PlainText
                    text: root.t("synthTargetRoom")
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  CompactDropdown {
                    id: synthRoomPicker
                    popupRadius: root.corners.radius
                    controlRadius: root.corners.control
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(fitWidth, parent.width - Style.space(106))
                    fontSize: Style.font.caption
                    rowHeight: Style.space(26)
                    popupRowHeight: Style.space(28)
                    showLabel: false
                    fontFamily: root.font
                    accent: root.accentColor
                    options: root.synthRoomOptions
                    value: String(root.synth.room_id || "")
                    onChanged: function(picked) {
                      root.send({ cmd: "synth_config", room_id: picked })
                      synthRoomPicker.value = Qt.binding(function() { return String(root.synth.room_id || "") })
                    }
                  }
                }

                // Sensitivity slider
                Item {
                  width: parent.width
                  height: Math.max(sensLbl.implicitHeight, sensSlider.implicitHeight)
                  Text {
                    id: sensLbl
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(96)
                    textFormat: Text.PlainText
                    text: root.t("synthSensitivity")
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  PanelSlider {
                    id: sensSlider
                    anchors.left: sensLbl.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: sensVal.left
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    bar: root.bar
                    minimum: 0.2; maximum: 3.0; step: 0.1
                    fillColor: root.accentColor
                    value: Number(root.synth.sensitivity || 1.0)
                    onMoved: function(v) { root.send({ cmd: "synth_config", sensitivity: Math.round(v * 10) / 10 }) }
                  }
                  Text {
                    id: sensVal
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(38)
                    horizontalAlignment: Text.AlignRight
                    textFormat: Text.PlainText
                    text: sensSlider.liveValue.toFixed(1) + "×"
                    color: root.fg
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                }

                // Smoothness slider
                Item {
                  width: parent.width
                  height: Math.max(smoothLbl.implicitHeight, smoothSlider.implicitHeight)
                  Text {
                    id: smoothLbl
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(96)
                    textFormat: Text.PlainText
                    text: root.t("synthSmoothness")
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                  PanelSlider {
                    id: smoothSlider
                    anchors.left: smoothLbl.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: smoothVal.left
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    bar: root.bar
                    minimum: 0.0; maximum: 0.95; step: 0.05
                    fillColor: root.accentColor
                    value: Number(root.synth.smoothness || 0.45)
                    onMoved: function(v) { root.send({ cmd: "synth_config", smoothness: Math.round(v * 20) / 20 }) }
                  }
                  Text {
                    id: smoothVal
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(38)
                    horizontalAlignment: Text.AlignRight
                    textFormat: Text.PlainText
                    text: Math.round(smoothSlider.liveValue * 100) + "%"
                    color: root.fg
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                }

                // Synth error caption
                Text {
                  visible: String(root.synth.error || "") !== ""
                  width: parent.width
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                  text: String(root.synth.error || "")
                  color: Commons.Color.urgent
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        // =====================================================================
        // LIGHTS TAB MODAL DIALOG OVERLAY (Brightness, Rename, 12-Icon Picker)
        // =====================================================================
        Item {
          id: lightModalOverlay
          anchors.fill: parent
          visible: root.lightDialog !== ""
          z: 90

          Keys.onEscapePressed: function(ev) {
            root.closeLightDialog()
            ev.accepted = true
          }

          Rectangle {
            anchors.fill: parent
            radius: root.corners.radius
            color: Qt.rgba(0, 0, 0, 0.56)
            MouseArea {
              anchors.fill: parent
              onClicked: root.closeLightDialog()
            }
          }

          // 1. Brightness modal dialog
          Rectangle {
            visible: root.lightDialog === "brightness"
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.space(20), Style.space(310))
            height: lightBriDlgCol.implicitHeight + Style.space(24)
            radius: root.corners.radius
            color: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 0.97)
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)

            MouseArea { anchors.fill: parent }

            Column {
              id: lightBriDlgCol
              x: Style.space(12); y: Style.space(12)
              width: parent.width - Style.space(24)
              spacing: Style.space(12)

              Item {
                width: parent.width
                height: Math.max(Style.space(26), lightBriSwitch.implicitHeight)
                Row {
                  anchors.left: parent.left
                  anchors.right: lightBriSwitch.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)
                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(24); height: Style.space(24); radius: width * 0.5
                    color: (root.lightDialogTarget && root.lightDialogTarget.on) ? (root.lightDialogTarget.color || "#ffd27a") : Qt.rgba(22 / 255, 26 / 255, 36 / 255, 0.92)
                    border.width: 1.2
                    border.color: (root.lightDialogTarget && root.lightDialogTarget.on) ? "#ffffff" : Qt.rgba(1, 1, 1, 0.32)
                    LightLampGlyph {
                      anchors.centerIn: parent
                      width: Style.space(14); height: Style.space(14)
                      iconName: root.lightIconFor(root.lightDialogId)
                      version: mapTab ? mapTab.iconVersion : 0
                      tint: root.lightContrastTint(root.lightDialogTarget)
                    }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(32)
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: root.lightDialogTarget ? String(root.lightDialogTarget.name || "") : ""
                    color: root.fg
                    font.family: root.font
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }
                ToggleSwitch {
                  id: lightBriSwitch
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  cursorRing: false
                  rounded: root.corners.pill > 0
                  trackHeight: Style.space(18)
                  checked: root.lightDialogTarget ? root.lightDialogTarget.on === true : false
                  foreground: root.fg
                  accent: root.accentColor
                  onToggled: if (root.lightDialogTarget) root.send({ cmd: "light", id: root.lightDialogTarget.id, on: !root.lightDialogTarget.on })
                }
              }

              Item {
                width: parent.width
                height: Math.max(lightDlgBriLbl.implicitHeight, lightDlgBriSlider.implicitHeight)
                Text {
                  id: lightDlgBriLbl
                  anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(66)
                  textFormat: Text.PlainText
                  text: root.t("brightness")
                  color: root.dim
                  font.family: root.font; font.pixelSize: Style.font.caption
                }
                PanelSlider {
                  id: lightDlgBriSlider
                  anchors.left: lightDlgBriLbl.right; anchors.leftMargin: Style.space(6)
                  anchors.right: lightDlgBriPct.left; anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  bar: root.bar
                  minimum: 1; maximum: 100; step: 1
                  fillColor: (root.lightDialogTarget && root.lightDialogTarget.on) ? (root.lightDialogTarget.color || root.accentColor) : root.accentColor
                  value: root.lightDialogTarget ? Math.max(1, Math.round(Number(root.lightDialogTarget.bri || 50))) : 50
                  onMoved: function(v) {
                    if (root.lightDialogTarget) root.send({ cmd: "light", id: root.lightDialogTarget.id, on: true, bri: Math.round(v) })
                  }
                }
                Text {
                  id: lightDlgBriPct
                  anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(34); horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                  text: Math.round(lightDlgBriSlider.liveValue) + "%"
                  color: root.fg
                  font.family: root.font; font.pixelSize: Style.font.caption
                }
              }

              Item {
                width: parent.width
                height: lightBriDoneBtn.implicitHeight
                Button {
                  id: lightBriDoneBtn
                  anchors.right: parent.right
                  radius: root.corners.control
                  text: root.t("shotDone")
                  bordered: true
                  selected: true
                  accent: root.accentColor
                  foreground: root.fg
                  fontFamily: root.font
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(12); verticalPadding: Style.space(3)
                  onClicked: root.closeLightDialog()
                }
              }
            }
          }

          // 2. Rename modal dialog (uses KeyTextField)
          Rectangle {
            visible: root.lightDialog === "rename"
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.space(20), Style.space(300))
            height: lightRenDlgCol.implicitHeight + Style.space(24)
            radius: root.corners.radius
            color: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 0.97)
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)

            MouseArea { anchors.fill: parent }

            Column {
              id: lightRenDlgCol
              x: Style.space(12); y: Style.space(12)
              width: parent.width - Style.space(24)
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                text: root.t("mapRename")
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              KeyTextField {
                id: lightRenameField
                width: parent.width
                radius: root.corners.control
                maximumLength: 32
                font: Qt.font({ family: root.font, pixelSize: Style.font.caption })
                placeholderText: root.t("mapRenamePlaceholder")
                foreground: root.fg
                accent: root.accentColor
                Keys.onEscapePressed: root.closeLightDialog()
                onAccepted: {
                  if (root.lightDialogId && text.trim().length > 0) {
                    root.send({ cmd: "light_rename", id: root.lightDialogId, name: text.trim() })
                    root.closeLightDialog()
                  }
                }
              }

              Item {
                width: parent.width
                height: lightRenBtnRow.implicitHeight
                Row {
                  id: lightRenBtnRow
                  anchors.right: parent.right
                  spacing: Style.space(6)
                  Button {
                    radius: root.corners.control
                    text: root.t("cancel")
                    bordered: true
                    foreground: root.dim
                    fontFamily: root.font
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(10); verticalPadding: Style.space(3)
                    onClicked: root.closeLightDialog()
                  }
                  Button {
                    radius: root.corners.control
                    text: root.t("mapRename")
                    bordered: true
                    selected: true
                    accent: root.accentColor
                    foreground: root.fg
                    fontFamily: root.font
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(10); verticalPadding: Style.space(3)
                    enabled: root.lightDialogId !== "" && lightRenameField.text.trim().length > 0
                    onClicked: {
                      root.send({ cmd: "light_rename", id: root.lightDialogId, name: lightRenameField.text.trim() })
                      root.closeLightDialog()
                    }
                  }
                }
              }
            }
          }

          // 3. Lamp Icon 12-icon picker modal dialog (saves to floorplan -> 1:1 sync with Map)
          Rectangle {
            visible: root.lightDialog === "icon"
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.space(20), Style.space(336))
            height: lightIconDlgCol.implicitHeight + Style.space(24)
            radius: root.corners.radius
            color: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 0.97)
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)

            MouseArea { anchors.fill: parent }

            Column {
              id: lightIconDlgCol
              x: Style.space(12); y: Style.space(12)
              width: parent.width - Style.space(24)
              spacing: Style.space(10)

              Row {
                width: parent.width
                spacing: Style.space(10)
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(32); height: Style.space(32); radius: width * 0.5
                  color: (root.lightDialogTarget && root.lightDialogTarget.on) ? (root.lightDialogTarget.color || "#ffd27a") : Qt.rgba(22 / 255, 26 / 255, 36 / 255, 0.92)
                  border.width: 1.8
                  border.color: root.accentColor
                  LightLampGlyph {
                    anchors.centerIn: parent
                    width: Style.space(19); height: Style.space(19)
                    iconName: root.lightIconFor(root.lightDialogId)
                    version: mapTab ? mapTab.iconVersion : 0
                    tint: root.lightContrastTint(root.lightDialogTarget)
                  }
                }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(42)
                  spacing: Style.space(1)
                  Text {
                    width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                    text: root.lightDialogTarget ? String(root.lightDialogTarget.name || "") : root.t("mapLampIconTitle")
                    color: root.fg
                    font.family: root.font
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: root.t("mapLampIconTitle") + " · " + (mapTab ? mapTab.lampIconLabel(root.lightIconFor(root.lightDialogId)) : "")
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Grid {
                id: lightIconGrid
                width: parent.width
                columns: 4
                spacing: Style.space(6)
                readonly property real cellW: Math.floor((width - spacing * 3) / 4)

                Repeater {
                  model: mapTab ? mapTab.lampIconList : []
                  delegate: Rectangle {
                    id: lightIcoBtn
                    required property var modelData
                    readonly property bool active: root.lightIconFor(root.lightDialogId) === modelData.id
                    width: lightIconGrid.cellW
                    height: Style.space(48)
                    radius: root.corners.control
                    color: active
                      ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.24)
                      : (lightIcoBtnM.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.11) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04))
                    border.width: active ? 1.6 : 1
                    border.color: active ? root.accentColor : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)

                    Column {
                      anchors.centerIn: parent
                      spacing: Style.space(3)
                      LightLampGlyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Style.space(20); height: Style.space(20)
                        iconName: lightIcoBtn.modelData.id
                        version: mapTab ? mapTab.iconVersion : 0
                        tint: lightIcoBtn.active ? root.accentColor : root.fg
                      }
                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: lightIcoBtn.width - Style.space(6)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: root.t(lightIcoBtn.modelData.key)
                        color: lightIcoBtn.active ? root.fg : root.dim
                        font.family: root.font
                        font.pixelSize: Math.max(9, Style.font.caption - 2)
                        font.bold: lightIcoBtn.active
                      }
                    }

                    MouseArea {
                      id: lightIcoBtnM
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.lightDialogId && mapTab) mapTab.setLampIcon(root.lightDialogId, lightIcoBtn.modelData.id)
                    }
                  }
                }
              }

              Item {
                width: parent.width
                height: lightIconDoneBtn.implicitHeight
                Button {
                  id: lightIconDoneBtn
                  anchors.right: parent.right
                  radius: root.corners.control
                  text: root.t("shotDone")
                  bordered: true
                  selected: true
                  accent: root.accentColor
                  foreground: root.fg
                  fontFamily: root.font
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(12); verticalPadding: Style.space(3)
                  onClicked: root.closeLightDialog()
                }
              }
            }
          }
        }
      }

      // Interactive bottom-right resize grip (saves panelWidth & panelHeight to shell.json)
      Item {
        id: resizeGrip
        visible: !shot.overlayOpen
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Style.space(16)
        height: Style.space(16)
        z: 50

        property point startPt: Qt.point(0, 0)
        property real startW: 430
        property real startH: 480

        Text {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          textFormat: Text.PlainText
          text: "⌟"
          color: gripMouse.containsMouse || root.resizing ? root.accentColor : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35)
          font.family: root.font
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: gripMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.SizeFDiagCursor
          onPressed: function(mouse) {
            var scale = Math.max(0.5, Style.effectiveSpacingScale)
            resizeGrip.startPt = resizeGrip.mapToItem(null, mouse.x, mouse.y)
            resizeGrip.startW = Math.round(panel.contentWidth / scale)
            resizeGrip.startH = Math.round(panel.contentHeight / scale)
            root.dragWidth = Math.max(380, Math.min(760, resizeGrip.startW))
            root.dragHeight = Math.max(360, Math.min(900, resizeGrip.startH))
            root.resizing = true
          }
          onPositionChanged: function(mouse) {
            if (!root.resizing) return
            var scale = Math.max(0.5, Style.effectiveSpacingScale)
            var cur = resizeGrip.mapToItem(null, mouse.x, mouse.y)
            var dx = (cur.x - resizeGrip.startPt.x) / scale
            var dy = (cur.y - resizeGrip.startPt.y) / scale
            root.dragWidth = Math.max(380, Math.min(760, Math.round(resizeGrip.startW + dx)))
            root.dragHeight = Math.max(360, Math.min(900, Math.round(resizeGrip.startH + dy)))
          }
          onReleased: {
            if (!root.resizing) return
            root.resizing = false
            if (root.hostWidget) {
              root.hostWidget.setPanelGeometry(root.dragWidth, root.dragHeight, root.panelOffsetX, root.panelOffsetY)
            }
          }
          onCanceled: root.resizing = false
        }
      }
    }
  }

  Component {
    id: providerEditorComponent
    Rectangle {
      id: editorBox
      readonly property var kindInfo: root.providerInfo(root.provKind) || root.extraProviderCatalog[0]
      readonly property bool hostValid: root.provHost.trim() !== ""
      readonly property bool sameSavedTarget: root.provHasSavedToken
        && root.provKind === root.provOriginalKind
        && root.provHost.trim().toLowerCase() === root.provOriginalHost.trim().toLowerCase()
        && root.provPort.trim() === root.provOriginalPort.trim()
      readonly property bool tokValid: !kindInfo.reqTok || root.provToken.trim() !== "" || root.provPairId !== "" || sameSavedTarget
      width: parent ? parent.width : 360
      height: editorCol.implicitHeight + Style.space(18)
      radius: root.corners.control
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
      border.width: 1
      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16)

      Column {
        id: editorCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(9)
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: Math.max(edTitle.implicitHeight, edCancel.implicitHeight)
          Text {
            id: edTitle
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.provEditId === "" ? root.t("addDeviceTitle") : root.t("editDeviceTitle")
            color: root.fg
            font.family: root.font
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Button {
            id: edCancel
            anchors.right: parent.right
            radius: root.corners.control
            text: root.t("cancel")
            bordered: true
            foreground: root.fg
            fontFamily: root.font
            onClicked: root.providerFormOpen = false
          }
        }

        Flow {
          visible: root.provEditId === ""
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: root.extraProviderCatalog.length
            delegate: Button {
              required property int index
              readonly property var item: root.extraProviderCatalog[index]
              readonly property bool selected: root.provKind === item.kind
              radius: root.corners.control
              text: item.badge
              bordered: true
              foreground: selected ? item.color : root.fg
              fontFamily: root.font
              onClicked: {
                root.provKind = item.kind
                root.provPort = String(item.port)
                root.provHttps = (item.kind === "dirigera")
                root.provToken = ""
                root.provPairId = ""
                root.provHasSavedToken = false
              }
            }
          }
        }

        Text {
          visible: text !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.providerSetupHint(root.provKind)
          color: root.dim
          font.family: root.font
          font.pixelSize: Style.font.caption
        }

        Item {
          visible: root.provEditId === ""
          width: parent.width
          height: Math.max(discLbl.implicitHeight, scanLanBtn.implicitHeight)
          Text {
            id: discLbl
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.t("discoveredLan")
            color: root.dim
            font.family: root.font
            font.pixelSize: Style.font.caption
          }
          Button {
            id: addAllBtn
            visible: root.addableDiscovered.length >= 2
            anchors.right: scanLanBtn.left
            anchors.rightMargin: Style.space(4)
            radius: root.corners.control
            text: root.t("addAllFound")
            bordered: true
            foreground: root.accentColor
            fontFamily: root.font
            onClicked: root.addAllDiscovered()
          }
          Button {
            id: scanLanBtn
            anchors.right: parent.right
            radius: root.corners.control
            text: root.discoveringProviders ? root.t("scanning") : root.t("scanLan")
            bordered: true
            foreground: root.fg
            fontFamily: root.font
            enabled: !root.discoveringProviders
            onClicked: root.send({ cmd: "discover_providers" })
          }
        }

        Text {
          visible: root.provEditId === "" && root.discoveredProviders.length === 0 && !root.discoveringProviders
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.t("nothingFoundLan")
          color: root.dim
          font.family: root.font
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.provEditId === "" ? root.discoveredProviders.length : 0
          delegate: Item {
            required property int index
            readonly property var dev: root.discoveredProviders[index] || ({})
            readonly property bool already: root.existingProviderTargets[root.providerTargetKey(dev.kind, dev.host, dev.port)] === true
            width: parent.width
            height: useDiscBtn.implicitHeight
            Text {
              anchors.left: parent.left
              anchors.right: useDiscBtn.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: "[" + String(dev.badge || dev.kind || "") + "] " + String(dev.name || "") + " · " + String(dev.host || "") + ":" + String(dev.port || "")
              color: root.fg
              font.family: root.font
              font.pixelSize: Style.font.caption
            }
            Button {
              id: useDiscBtn
              anchors.right: parent.right
              radius: root.corners.control
              text: already ? root.t("deviceAdded") : root.t("useDevice")
              bordered: true
              foreground: already ? root.dim : root.fg
              fontFamily: root.font
              enabled: !already
              onClicked: {
                root.provKind = String(dev.kind || "wled")
                root.provName = String(dev.name || "")
                root.provHost = String(dev.host || "")
                root.provPort = String(dev.port || "")
                root.provHttps = (root.provKind === "dirigera")
                root.provToken = ""
                root.provPairId = ""
                root.provHasSavedToken = false
              }
            }
          }
        }

        KeyTextField {
          width: parent.width
          radius: root.corners.control
          maximumLength: 40
          text: root.provName
          placeholderText: editorBox.kindInfo.name
          foreground: root.fg
          accent: root.accentColor
          onTextChanged: root.provName = text
        }

        Row {
          width: parent.width
          spacing: Style.space(6)
          KeyTextField {
            width: parent.width - Style.space(86)
            radius: root.corners.control
            maximumLength: 120
            text: root.provHost
            placeholderText: root.t("localHostPlaceholder")
            foreground: root.fg
            accent: root.accentColor
            onTextChanged: root.provHost = text
          }
          KeyTextField {
            width: Style.space(80)
            radius: root.corners.control
            maximumLength: 6
            text: root.provPort
            placeholderText: String(editorBox.kindInfo.port)
            foreground: root.fg
            accent: root.accentColor
            onTextChanged: root.provPort = text
          }
        }

        KeyTextField {
          visible: root.provKind !== "home_assistant" && root.provKind !== "dirigera"
          width: parent.width
          radius: root.corners.control
          maximumLength: 40
          text: root.provRoom
          placeholderText: root.t("roomNameOptional")
          foreground: root.fg
          accent: root.accentColor
          onTextChanged: root.provRoom = text
        }

        Item {
          visible: root.provKind === "home_assistant"
          width: parent.width
          height: Math.max(httpsLbl.implicitHeight, httpsSw.implicitHeight)
          Text {
            id: httpsLbl
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.t("useHttpsLan")
            color: root.dim
            font.family: root.font
            font.pixelSize: Style.font.caption
          }
          ToggleSwitch {
            id: httpsSw
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            cursorRing: false
            rounded: root.corners.pill > 0
            checked: root.provHttps
            foreground: root.fg
            accent: root.accentColor
            onToggled: root.provHttps = !root.provHttps
          }
        }

        KeyTextField {
          visible: editorBox.kindInfo.reqTok
          width: parent.width
          radius: root.corners.control
          maximumLength: 512
          password: true
          text: root.provToken
          placeholderText: root.provPairId !== "" ? root.t("pairedPressSave")
            : editorBox.sameSavedTarget ? root.t("savedTokenPlaceholder")
            : root.provKind === "home_assistant" ? root.t("pasteHaToken")
            : root.t("accessToken")
          foreground: root.fg
          accent: root.accentColor
          onTextChanged: root.provToken = text
        }

        Text {
          visible: editorBox.kindInfo.reqTok && root.provEditId !== "" && !editorBox.sameSavedTarget
            && root.provToken.trim() === "" && root.provPairId === ""
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.t("hostChangedNeedToken")
          color: root.dim
          font.family: root.font
          font.pixelSize: Style.font.caption
        }

        Button {
          readonly property var savedDev: {
            var list = root.providers || []
            for (var i = 0; i < list.length; i++) if (list[i].id === root.provEditId) return list[i]
            return null
          }
          readonly property bool certError: savedDev !== null && String(savedDev.error || "").toLowerCase().indexOf("certificate") >= 0
          visible: root.provEditId !== "" && (root.provKind === "dirigera" || root.provHttps) && (root.provHasCertFp || certError)
          radius: root.corners.control
          text: root.t("trustNewCert")
          bordered: true
          foreground: root.fg
          fontFamily: root.font
          onClicked: {
            root.provHasCertFp = false
            root.send({ cmd: "trust_provider_cert", id: root.provEditId })
          }
        }

        Button {
          visible: editorBox.kindInfo.pair
          radius: root.corners.control
          text: root.provKind === "nanoleaf" ? root.t("pairPowerBtn") : root.t("pairActionBtn")
          bordered: true
          foreground: root.fg
          fontFamily: root.font
          enabled: editorBox.hostValid && !root.providerAction.running
          onClicked: root.send({
            cmd: "pair_provider",
            kind: root.provKind,
            host: root.provHost.trim(),
            port: parseInt(root.provPort.trim(), 10) || editorBox.kindInfo.port
          })
        }

        Text {
          visible: root.providerAction.running === true || String(root.providerAction.message || "") !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.providerAction.running === true ? root.t("working") : ((root.providerAction.ok ? "✓ " : "") + String(root.providerAction.message || ""))
          color: root.providerAction.running === true ? root.dim : (root.providerAction.ok ? "#10B981" : Commons.Color.urgent)
          font.family: root.font
          font.pixelSize: Style.font.caption
        }

        Item {
          width: parent.width
          height: Math.max(testDevBtn.implicitHeight, saveDevBtn.implicitHeight)
          Button {
            id: testDevBtn
            radius: root.corners.control
            text: root.t("testConnection")
            bordered: true
            foreground: root.fg
            fontFamily: root.font
            enabled: editorBox.hostValid && editorBox.tokValid && !root.providerAction.running
            onClicked: root.send({ cmd: "test_provider", provider: root.buildProviderPayload() })
          }
          Button {
            id: saveDevBtn
            anchors.right: parent.right
            radius: root.corners.control
            text: root.t("saveDevice")
            bordered: true
            foreground: root.accentColor
            fontFamily: root.font
            enabled: editorBox.hostValid && editorBox.tokValid && !root.providerAction.running
            onClicked: {
              root.provAwaitingSave = true
              root.send({ cmd: "save_provider", provider: root.buildProviderPayload() })
            }
          }
        }
      }
    }
  }
}
