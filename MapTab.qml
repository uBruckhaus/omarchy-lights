pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "I18n.js" as I18n

// Interactive 2D Visual Floorplan & Spatial Light Studio ("Map" tab).
// Uses KeyTextField for all text inputs and Text.PlainText on every Text item.
Item {
  id: mapRoot

  implicitHeight: Math.max(mainCol.implicitHeight, modalMinHeight)

  // Inputs bound from Panel.qml
  property var bar: null
  property var rooms: []
  property var rules: []
  property var schedules: []
  property var synth: ({})
  property var floorplan: null
  property var entertainmentAreas: []
  property var sensors: []
  property var motionAreas: []
  property bool showMotionAwareHint: false
  property var motionAwareEligibleRooms: []
  property color fg: Commons.Color.popups.text
  property color dim: Qt.darker(fg, 1.45)
  property color accentColor: Commons.Color.accent
  property bool hasSkin: false
  property string fontFamily: Style.font.family
  property var corners: ({ radius: Style.cornerRadius, control: Style.cornerRadius, small: 4, pill: 999 })
  property string lang: "en"
  property int panelHeight: 0
  // Hue Bridge paired? Without it, Sync All and pending-sync counts are hidden (extra providers only).
  property bool huePaired: true

  signal sendCommand(var obj)
  signal scheduleSceneRequested(string roomKind, string roomId, string sceneId, string sceneName)
  signal returnFocusRequested()
  signal dismissMotionAwareHint()

  function t(key, args) { return I18n.tr(lang, key, args) }

  // Block PanelKeyCatcher whenever any text field or dropdown popup is active
  readonly property bool inputBlocked: bgPathField.activeFocus
    || lampSearchField.activeFocus
    || lampRenameField.activeFocus
    || roomRenameField.activeFocus
    || sceneNameField.activeFocus
    || mapRuleStartField.activeFocus
    || mapRuleEndField.activeFocus
    || mapRuleNameField.activeFocus
    || floorRenameField.activeFocus
    || plannedNameField.activeFocus
    || plannedPriceField.activeFocus
    || entPicker.popupOpen
    || boxArchPicker.popupOpen
    || boxEntPicker.popupOpen

  // Local working copy of floorplan for 60fps drag/resize before committing floorplan_save
  property var workingFp: defaultFloorplan()
  property bool isDragging: false
  property int bgReloadTick: 0
  property int iconVersion: 0

  // Tool & UI state
  property string toolMode: "select"       // select (Map) | plan (Plan) | wire (Rules)
  readonly property bool editMode: toolMode === "select" || toolMode === "plan"
  property string ambient: "day"           // day | dusk | night (local view only, never saved)
  readonly property real ambientDim: ambient === "night" ? 0.56 : (ambient === "dusk" ? 0.28 : 0.0)
  readonly property real glowBoost: ambient === "night" ? 1.48 : (ambient === "dusk" ? 1.22 : 1.0)
  property bool showGallery: false
  property bool galleryIncludePlan: false
  property string confirmTemplateId: ""
  property bool showPlanAdd: false
  property bool showPlanList: false
  property var undoFp: null
  property bool floorRenameOpen: false
  property bool showSidebar: width >= Style.space(520)
  property bool sidebarUserSet: false
  property bool showAddMenu: false
  property bool showViewMenu: false
  property bool showBgBar: false
  property string selectedKind: ""         // "" | "lamp" | "sensor" | "box" | "stamp"
  property string selectedId: ""
  property string hoverLampId: ""
  property string hoverSensorId: ""
  property string hoverRuleId: ""
  property string openMenuLampId: ""
  property string openMenuSensorId: ""
  property bool confirmBridgeDelete: false

  // Focused modal dialogs: "" | "brightness" | "rename" | "icon" | "rule"
  property string activeDialog: ""
  property string dialogLampId: ""

  // Rule dialog state (New & Edit)
  property string ruleEditId: ""
  property bool ruleEditEnabled: true
  property string ruleEditFromKind: "light"
  property string ruleEditFromId: ""
  property string ruleEditToKind: "light"
  property string ruleEditToId: ""
  property string ruleEditKind: "follow"          // follow | exclusive | companion
  property string ruleEditTriggerState: "on"      // on | off
  property bool ruleEditMirrorOff: true
  property bool ruleEditMatchBri: false
  property bool ruleEditOnlyIfOff: false
  property var ruleEditExtraTargets: []

  // Wire creation state (Rules sub-tab)
  property string wireFromKind: "light"
  property string wireFromId: ""
  property real wireCursorX: 0
  property real wireCursorY: 0
  property bool wireDragging: false

  // Viewport zoom & pan (relative to fit-to-viewport)
  property real userZoom: 1.0
  property real userPanX: 0.0
  property real userPanY: 0.0

  // Cached background path
  property string lastSyncedBgPath: ""

  readonly property real modalMinHeight: {
    if (activeDialog === "rule") return ruleDlgCol.implicitHeight + Style.space(52)
    if (activeDialog === "icon") return iconDlgCol.implicitHeight + Style.space(52)
    if (activeDialog === "brightness") return briDlgCol.implicitHeight + Style.space(52)
    if (activeDialog === "rename") return renDlgCol.implicitHeight + Style.space(52)
    return 0
  }

  readonly property color cardBorderColor: hasSkin
    ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.30)
    : Qt.rgba(fg.r, fg.g, fg.b, 0.14)

  readonly property var lampIconList: [
    { id: "bulb",    key: "lampIconBulb" },
    { id: "spot",    key: "lampIconSpot" },
    { id: "strip",   key: "lampIconStrip" },
    { id: "floor",   key: "lampIconFloor" },
    { id: "table",   key: "lampIconTable" },
    { id: "pendant", key: "lampIconPendant" },
    { id: "ceiling", key: "lampIconCeiling" },
    { id: "wall",    key: "lampIconWall" },
    { id: "bar",     key: "lampIconBar" },
    { id: "desk",    key: "lampIconDesk" },
    { id: "outdoor", key: "lampIconOutdoor" },
    { id: "candle",  key: "lampIconCandle" }
  ]

  readonly property var stampKindList: [
    { id: "door",    key: "stampDoor",    w: 52,  h: 52 },
    { id: "window",  key: "stampWindow",  w: 160, h: 12 },
    { id: "sofa",    key: "stampSofa",    w: 170, h: 72 },
    { id: "tv",      key: "stampTv",      w: 150, h: 18 },
    { id: "desk",    key: "stampDesk",    w: 160, h: 72 },
    { id: "bed",     key: "stampBed",     w: 190, h: 150 },
    { id: "dining",  key: "stampDining",  w: 150, h: 90 },
    { id: "kitchen", key: "stampKitchen", w: 220, h: 52 },
    { id: "stairs",  key: "fpStairs",     w: 96,  h: 130 }
  ]

  // Floorplan Studio v2: room shape starters (backend accepts free polygons with 3..32 corners)
  readonly property var roomShapeList: [
    { id: "rectangle",  key: "fpShapeRect" },
    { id: "l_shape",    key: "fpShapeL" },
    { id: "bay_window", key: "fpShapeBay" },
    { id: "t_shape",    key: "fpShapeT" },
    { id: "corridor",   key: "fpShapeHall" },
    { id: "trapezoid",  key: "fpShapeAngled" }
  ]

  // Future Lighting Planner presets (same values as Maprisma Lights)
  readonly property var plannedPresetList: [
    { id: "ceiling", key: "fpPresetCeiling", icon: "ceiling", lumens: 2400, beam: 3.6, kelvin: 3000, price: 129, strip: false },
    { id: "pendant", key: "fpPresetPendant", icon: "pendant", lumens: 1200, beam: 2.6, kelvin: 2700, price: 179, strip: false },
    { id: "spot",    key: "fpPresetSpot",    icon: "spot",    lumens: 450,  beam: 1.8, kelvin: 3000, price: 39,  strip: false },
    { id: "floor",   key: "fpPresetFloor",   icon: "floor",   lumens: 1050, beam: 2.8, kelvin: 2700, price: 149, strip: false },
    { id: "table",   key: "fpPresetTable",   icon: "table",   lumens: 550,  beam: 2.0, kelvin: 2400, price: 69,  strip: false },
    { id: "strip",   key: "fpPresetStrip",   icon: "strip",   lumens: 1600, beam: 2.2, kelvin: 2700, price: 79,  strip: true },
    { id: "wall",    key: "fpPresetWall",    icon: "wall",    lumens: 650,  beam: 2.1, kelvin: 2700, price: 89,  strip: false },
    { id: "outdoor", key: "fpPresetOutdoor", icon: "outdoor", lumens: 1400, beam: 3.8, kelvin: 3000, price: 119, strip: false }
  ]

  readonly property var templateOptions: [
    { value: "auto_bridge",      label: mapRoot.t("fpTplAuto") },
    { value: "studio_loft",      label: mapRoot.t("fpTplLoft") },
    { value: "one_bed_apt",      label: mapRoot.t("fpTplTwoRoom") },
    { value: "three_room_apt",   label: mapRoot.t("fpTplAltbau") },
    { value: "family_house",     label: mapRoot.t("fpTplHouse") },
    { value: "bungalow_l_shape", label: mapRoot.t("fpTplBungalow") },
    { value: "desk_studio",      label: mapRoot.t("fpTplDesk") }
  ]

  readonly property var archetypeOptions: [
    { value: "living_room",  label: mapRoot.t("archLiving") },
    { value: "bedroom",      label: mapRoot.t("archBedroom") },
    { value: "kids_bedroom", label: mapRoot.t("archKids") },
    { value: "kitchen",      label: mapRoot.t("archKitchen") },
    { value: "dining",       label: mapRoot.t("archDining") },
    { value: "office",       label: mapRoot.t("archOffice") },
    { value: "bathroom",     label: mapRoot.t("archBathroom") },
    { value: "toilet",       label: mapRoot.t("archToilet") },
    { value: "hallway",      label: mapRoot.t("archHallway") },
    { value: "balcony",      label: mapRoot.t("archBalcony") },
    { value: "terrace",      label: mapRoot.t("archTerrace") },
    { value: "garden",       label: mapRoot.t("archGarden") },
    { value: "lounge",       label: mapRoot.t("archLounge") },
    { value: "tv",           label: mapRoot.t("archTv") },
    { value: "studio",       label: mapRoot.t("archStudio") },
    { value: "reading",      label: mapRoot.t("archReading") },
    { value: "garage",       label: mapRoot.t("archGarage") },
    { value: "other",        label: mapRoot.t("archOther") }
  ]

  readonly property var entertainmentOptions: {
    var out = [{ value: "", label: mapRoot.t("mapEntertainmentNone") }]
    var list = mapRoot.entertainmentAreas || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id) out.push({ value: String(list[i].id), label: String(list[i].name || list[i].id) })
    }
    return out
  }

  function defaultFloorplan() {
    return {
      version: 2,
      bridge_id: "",
      template_id: "auto_bridge",
      entertainment_id: null,
      canvas: { width: 1400, height: 900, grid: 20, snap: true, zoom: 1.0, pan_x: 0, pan_y: 0 },
      show_wires: true,
      show_glows: true,
      show_furniture: true,
      auto_sync: false,
      auto_sync_rooms: false,
      background: { path: "", opacity: 0.35, fit: "contain" },
      px_per_meter: 50.0,
      floors: [{ id: "eg", name: "Ground Floor", level: 0 }],
      active_floor_id: "eg",
      boxes: [],
      stamps: [],
      lamps: ({}),
      sensors: ({}),
      planned_lights: []
    }
  }

  function cloneFp(fp) {
    try { return JSON.parse(JSON.stringify(fp || defaultFloorplan())) } catch (e) { return defaultFloorplan() }
  }

  onFloorplanChanged: {
    if (!isDragging && floorplan && typeof floorplan === "object") {
      var prevBg = lastSyncedBgPath
      workingFp = cloneFp(floorplan)
      iconVersion += 1
      var nextBg = String((workingFp.background && workingFp.background.path) || "")
      if (nextBg !== prevBg) {
        lastSyncedBgPath = nextBg
        bgReloadTick += 1
      }
      mapCanvas.requestPaint()
    }
  }

  onWidthChanged: {
    if (!sidebarUserSet) showSidebar = width >= Style.space(520)
  }

  onRoomsChanged: mapCanvas.requestPaint()
  onRulesChanged: mapCanvas.requestPaint()
  onSynthChanged: mapCanvas.requestPaint()
  onSensorsChanged: mapCanvas.requestPaint()
  onMotionAreasChanged: mapCanvas.requestPaint()
  onToolModeChanged: mapCanvas.requestPaint()
  onAmbientChanged: mapCanvas.requestPaint()
  onWorkingFpChanged: mapCanvas.requestPaint()
  onSelectedIdChanged: mapCanvas.requestPaint()
  onSelectedKindChanged: mapCanvas.requestPaint()

  function closeDialog() {
    activeDialog = ""
    dialogLampId = ""
    ruleEditId = ""
    returnFocusRequested()
  }

  // Close topmost transient UI (modal dialog -> lamp submenu -> toolbar popover -> armed wire -> selection).
  // Returns true if something was closed so PanelKeyCatcher does not close the entire panel.
  function closeTransient() {
    if (activeDialog !== "") {
      closeDialog()
      return true
    }
    if (openMenuLampId !== "" || openMenuSensorId !== "") {
      openMenuLampId = ""
      openMenuSensorId = ""
      return true
    }
    if (floorRenameOpen) {
      floorRenameOpen = false
      return true
    }
    if (showAddMenu || showViewMenu || showBgBar || showGallery || showPlanAdd || showPlanList) {
      closeMenus()
      return true
    }
    if (wireFromId !== "") {
      wireFromKind = "light"
      wireFromId = ""
      wireDragging = false
      mapCanvas.requestPaint()
      return true
    }
    if (selectedKind !== "") {
      selectedKind = ""
      selectedId = ""
      confirmBridgeDelete = false
      mapCanvas.requestPaint()
      return true
    }
    return false
  }

  function resetTransient() {
    activeDialog = ""
    dialogLampId = ""
    ruleEditId = ""
    openMenuLampId = ""
    openMenuSensorId = ""
    hoverLampId = ""
    hoverSensorId = ""
    hoverRuleId = ""
    selectedKind = ""
    selectedId = ""
    wireFromKind = "light"
    wireFromId = ""
    wireDragging = false
    showAddMenu = false
    showViewMenu = false
    showBgBar = false
    showGallery = false
    showPlanAdd = false
    showPlanList = false
    confirmTemplateId = ""
    floorRenameOpen = false
    confirmBridgeDelete = false
  }

  function closeMenus() {
    showAddMenu = false
    showViewMenu = false
    showBgBar = false
    showGallery = false
    showPlanAdd = false
    showPlanList = false
    confirmTemplateId = ""
  }

  function commitFp(nextFp, triggerAutoSync) {
    workingFp = nextFp
    sendCommand({ cmd: "floorplan_save", floorplan: nextFp })
    if (triggerAutoSync && nextFp.auto_sync) {
      sendCommand({ cmd: "floorplan_sync_all" })
    }
    mapCanvas.requestPaint()
  }

  // Derived floorplan fields
  readonly property var fpCanvas: (workingFp && workingFp.canvas) ? workingFp.canvas : ({ width: 1400, height: 900, grid: 20, snap: true })
  readonly property real canvasW: Math.max(400, Number(fpCanvas.width || 1400))
  readonly property real canvasH: Math.max(300, Number(fpCanvas.height || 900))
  readonly property int canvasGrid: Math.max(5, Math.round(Number(fpCanvas.grid || 20)))
  readonly property bool canvasSnap: fpCanvas.snap !== false
  readonly property bool showWires: workingFp ? (workingFp.show_wires !== false) : true
  readonly property bool wiresVisible: toolMode === "wire" || showWires
  readonly property bool showGlows: workingFp ? (workingFp.show_glows !== false) : true
  readonly property bool showFurniture: workingFp ? (workingFp.show_furniture !== false) : true
  readonly property bool autoSync: workingFp ? (workingFp.auto_sync === true) : false
  readonly property var fpBoxes: (workingFp && Array.isArray(workingFp.boxes)) ? workingFp.boxes : []
  readonly property var fpStamps: (workingFp && Array.isArray(workingFp.stamps)) ? workingFp.stamps : []
  readonly property var fpLamps: (workingFp && workingFp.lamps && typeof workingFp.lamps === "object") ? workingFp.lamps : ({})
  readonly property var fpSensors: (workingFp && workingFp.sensors && typeof workingFp.sensors === "object") ? workingFp.sensors : ({})
  readonly property var fpBg: (workingFp && workingFp.background) ? workingFp.background : ({ path: "", opacity: 0.35, fit: "contain" })
  readonly property string bgPath: String(fpBg.path || "")
  readonly property real bgOpacity: Math.max(0.05, Math.min(1.0, Number(fpBg.opacity || 0.35)))
  readonly property string bgFit: String(fpBg.fit || "contain") === "cover" ? "cover" : "contain"

  // ---- Floorplan Studio v2: floors, polygons, planner ----
  readonly property var fpFloors: (workingFp && Array.isArray(workingFp.floors) && workingFp.floors.length > 0)
    ? workingFp.floors : [{ id: "eg", name: "Ground Floor", level: 0 }]
  readonly property string defaultFloorId: String(fpFloors[0].id || "eg")
  readonly property string activeFloorId: {
    var want = workingFp ? String(workingFp.active_floor_id || "") : ""
    for (var i = 0; i < fpFloors.length; i++) if (fpFloors[i].id === want) return want
    return defaultFloorId
  }
  readonly property var fpPlanned: (workingFp && Array.isArray(workingFp.planned_lights)) ? workingFp.planned_lights : []
  readonly property real pxPerMeter: Math.max(10, Number((workingFp && workingFp.px_per_meter) || 50))
  readonly property var activePlanned: {
    var out = []
    var list = mapRoot.fpPlanned
    for (var i = 0; i < list.length; i++) if (list[i] && mapRoot.floorOf(list[i]) === mapRoot.activeFloorId) out.push({ idx: i, pl: list[i] })
    return out
  }
  readonly property var selectedPlanned: {
    if (selectedKind !== "planned") return null
    for (var i = 0; i < fpPlanned.length; i++) if (fpPlanned[i] && fpPlanned[i].id === selectedId) return fpPlanned[i]
    return null
  }

  readonly property var plannedStripVerts: {
    var out = []
    var aps = mapRoot.activePlanned || []
    for (var i = 0; i < aps.length; i++) {
      var sp = aps[i].pl && Array.isArray(aps[i].pl.strip_points) ? aps[i].pl.strip_points : []
      if (sp.length < 2) continue
      for (var k = 0; k < sp.length; k++) out.push({ idx: aps[i].idx, pid: String(aps[i].pl.id || ""), vi: k, x: Number(sp[k].x), y: Number(sp[k].y) })
    }
    return out
  }

  function floorOf(obj) {
    var f = obj ? String(obj.floor_id || "") : ""
    return f !== "" ? f : defaultFloorId
  }
  function onActiveFloor(obj) { return floorOf(obj) === activeFloorId }
  function floorNameOf(fid) {
    for (var i = 0; i < fpFloors.length; i++) if (fpFloors[i].id === fid) return fpFloors[i].name
    return ""
  }

  // Built-in floor names are stored in English; show them translated.
  function floorLabel(name) {
    var n = String(name || "")
    if (n === "Ground Floor") return t("fpGroundFloor")
    if (n === "Upper Floor") return t("fpUpperFloor")
    if (n === "Attic") return t("fpAttic")
    if (n === "Basement") return t("fpBasement")
    var m = /^Floor (-?\d+)$/.exec(n)
    if (m) return t("fpFloorN", [m[1]])
    return n
  }

  function isPolygon(b) { return !!(b && Array.isArray(b.points) && b.points.length >= 3) }
  function boxPoints(b) {
    if (isPolygon(b)) return b.points
    return [{ x: b.x, y: b.y }, { x: b.x + b.w, y: b.y }, { x: b.x + b.w, y: b.y + b.h }, { x: b.x, y: b.y + b.h }]
  }
  // Same rule as the backend (_point_in_box): bounding box, then 1.5 px wall tolerance, then even-odd.
  function boxContains(b, px, py) {
    if (!b) return false
    if (px < b.x - 0.5 || px > b.x + b.w + 0.5 || py < b.y - 0.5 || py > b.y + b.h + 0.5) return false
    if (!isPolygon(b)) return px >= b.x && px <= b.x + b.w && py >= b.y && py <= b.y + b.h
    var pts = b.points
    var n = pts.length
    for (var i = 0; i < n; i++) {
      var a = pts[i], c = pts[(i + 1) % n]
      var dx = c.x - a.x, dy = c.y - a.y
      var lsq = dx * dx + dy * dy
      var tt = lsq < 1e-9 ? 0 : Math.max(0, Math.min(1, ((px - a.x) * dx + (py - a.y) * dy) / lsq))
      if (Math.hypot(px - (a.x + tt * dx), py - (a.y + tt * dy)) <= 1.5) return true
    }
    var inside = false
    for (var k = 0, j = n - 1; k < n; j = k++) {
      var xi = pts[k].x, yi = pts[k].y, xj = pts[j].x, yj = pts[j].y
      var den = Math.abs(yj - yi) < 1e-9 ? 1e-9 : (yj - yi)
      if (((yi > py) !== (yj > py)) && (px < (xj - xi) * (py - yi) / den + xi)) inside = !inside
    }
    return inside
  }
  function boxAreaPx(b) {
    if (!isPolygon(b)) return Math.max(1, b.w * b.h)
    var pts = b.points, sum = 0
    for (var i = 0; i < pts.length; i++) {
      var a = pts[i], c = pts[(i + 1) % pts.length]
      sum += a.x * c.y - c.x * a.y
    }
    return Math.max(1, Math.abs(sum) * 0.5)
  }
  function boxAreaM2(b) { return boxAreaPx(b) / (pxPerMeter * pxPerMeter) }
  function syncBounds(b) {
    if (!isPolygon(b)) return
    var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9
    for (var i = 0; i < b.points.length; i++) {
      var p = b.points[i]
      minX = Math.min(minX, p.x); minY = Math.min(minY, p.y)
      maxX = Math.max(maxX, p.x); maxY = Math.max(maxY, p.y)
    }
    b.x = Math.round(minX * 10) / 10
    b.y = Math.round(minY * 10) / 10
    b.w = Math.max(60, Math.round((maxX - minX) * 10) / 10)
    b.h = Math.max(60, Math.round((maxY - minY) * 10) / 10)
  }
  function shapePoints(shape, x, y, w, h) {
    function P(px, py) { return { x: Math.round(px * 10) / 10, y: Math.round(py * 10) / 10 } }
    if (shape === "l_shape") return [P(x, y), P(x + w, y), P(x + w, y + h * 0.56), P(x + w * 0.56, y + h * 0.56), P(x + w * 0.56, y + h), P(x, y + h)]
    if (shape === "bay_window") return [P(x, y + h * 0.16), P(x + w * 0.24, y + h * 0.16), P(x + w * 0.34, y), P(x + w * 0.66, y), P(x + w * 0.76, y + h * 0.16), P(x + w, y + h * 0.16), P(x + w, y + h), P(x, y + h)]
    if (shape === "t_shape") return [P(x, y), P(x + w, y), P(x + w, y + h * 0.45), P(x + w * 0.72, y + h * 0.45), P(x + w * 0.72, y + h), P(x + w * 0.28, y + h), P(x + w * 0.28, y + h * 0.45), P(x, y + h * 0.45)]
    if (shape === "corridor") return [P(x, y), P(x + w * 0.42, y), P(x + w * 0.42, y + h * 0.62), P(x + w, y + h * 0.62), P(x + w, y + h), P(x, y + h)]
    if (shape === "trapezoid") return [P(x + w * 0.14, y), P(x + w, y), P(x + w, y + h), P(x, y + h)]
    return []
  }
  function applyShape(b, shape) {
    b.points = shapePoints(shape, b.x, b.y, b.w, b.h)
    syncBounds(b)
  }
  function shapeIdOf(b) {
    if (!isPolygon(b)) return "rectangle"
    for (var i = 1; i < roomShapeList.length; i++) {
      var ref = shapePoints(roomShapeList[i].id, b.x, b.y, b.w, b.h)
      if (ref.length !== b.points.length) continue
      var same = true
      for (var k = 0; k < ref.length && same; k++) same = Math.abs(ref[k].x - b.points[k].x) < 1.5 && Math.abs(ref[k].y - b.points[k].y) < 1.5
      if (same) return roomShapeList[i].id
    }
    return ""
  }
  function plannedAnchor(pl) {
    var sp = (pl && Array.isArray(pl.strip_points)) ? pl.strip_points : []
    if (sp.length >= 2) {
      var sx = 0, sy = 0
      for (var i = 0; i < sp.length; i++) { sx += sp[i].x; sy += sp[i].y }
      return { x: sx / sp.length, y: sy / sp.length }
    }
    return { x: Number(pl ? pl.x : 0), y: Number(pl ? pl.y : 0) }
  }
  function kelvinToHex(k) {
    var kk = Math.max(1800, Math.min(6500, Number(k) || 2700))
    if (kk <= 2400) return "#ffb454"
    if (kk <= 3000) return "#ffd27a"
    if (kk <= 4000) return "#ffe8b8"
    if (kk <= 5200) return "#f7f9ff"
    return "#dbeeff"
  }
  function targetLux(arch) {
    var a = String(arch || "")
    if (a === "office" || a === "computer" || a === "studio") return 400
    if (a === "kitchen") return 300
    if (a === "bathroom" || a === "toilet") return 250
    if (a === "dining") return 200
    if (a === "living_room" || a === "lounge" || a === "tv") return 150
    if (a === "bedroom" || a === "guest_room" || a === "kids_bedroom") return 120
    if (a === "hallway" || a === "staircase") return 100
    if (a === "terrace" || a === "balcony" || a === "garden") return 60
    return 150
  }
  // Lit real + planned lights inside a box on its floor: average colour and estimated lumens.
  function boxLightInfo(b) {
    var info = { count: 0, r: 0, g: 0, b: 0, lumens: 0 }
    if (!b) return info
    var bf = floorOf(b)
    var lamps = fpLamps || ({})
    for (var lid in lamps) {
      var pos = lamps[lid]
      if (!pos || floorOf(pos) !== bf) continue
      var lt = lightById[lid]
      if (!lt || !lt.on || !boxContains(b, Number(pos.x), Number(pos.y))) continue
      var c = Qt.color(lt.color || "#ffd27a")
      info.r += c.r; info.g += c.g; info.b += c.b
      info.count += 1
      info.lumens += 800 * Math.max(0.05, Math.min(1, Number(lt.bri || 0) / 100))
    }
    var pl = fpPlanned || []
    for (var i = 0; i < pl.length; i++) {
      var p = pl[i]
      if (!p || p.on === false || floorOf(p) !== bf) continue
      var an = plannedAnchor(p)
      if (!boxContains(b, an.x, an.y)) continue
      var pc = Qt.color(p.color || "#ffd27a")
      info.r += pc.r; info.g += pc.g; info.b += pc.b
      info.count += 1
      info.lumens += Number(p.lumens || 0)
    }
    if (info.count > 0) { info.r /= info.count; info.g /= info.count; info.b /= info.count }
    return info
  }
  function floorLitCount(fid) {
    var n = 0
    var lamps = fpLamps || ({})
    for (var lid in lamps) {
      var lt = lightById[lid]
      if (lt && lt.on && floorOf(lamps[lid]) === fid) n += 1
    }
    return n
  }
  // Non-Hue lights / rooms from extra providers carry "provider:device" style ids.
  function isHueId(id) { return String(id || "").indexOf(":") < 0 }
  // Short brand tag for lights of extra local providers ("" for Philips Hue)
  function providerTag(kind) {
    var k = String(kind || "hue")
    if (k === "hue") return ""
    var tags = { home_assistant: "HA", wled: "WLED", wiz: "WiZ", lifx: "LIFX", govee: "Govee", nanoleaf: "Nanoleaf", shelly: "Shelly", dirigera: "IKEA" }
    return tags[k] || k
  }

  // Flatten all unique Hue lights from rooms
  readonly property var allLights: {
    var rs = mapRoot.rooms || []
    var seen = ({})
    var out = []
    for (var i = 0; i < rs.length; i++) {
      var r = rs[i]
      if (!r) continue
      var ls = r.lights || []
      for (var j = 0; j < ls.length; j++) {
        var l = ls[j]
        if (!l || !l.id) continue
        if (seen[l.id]) {
          if (r.kind === "room" && seen[l.id].room_kind !== "room") {
            seen[l.id].room_id = r.id || ""
            seen[l.id].room_name = r.name || ""
            seen[l.id].room_kind = r.kind
          }
          continue
        }
        var rec = {
          id: String(l.id),
          name: String(l.name || ""),
          on: l.on === true,
          bri: Number(l.bri || 0),
          color: String(l.color || "#ffd27a"),
          device_id: String(l.device_id || ""),
          reachable: l.reachable !== false,
          motion_aware: l.motion_aware === true,
          motion_active: l.motion_active === true,
          provider: String(l.provider || r.provider || "hue"),
          room_id: r.kind === "room" ? String(r.id || "") : "",
          room_name: r.kind === "room" ? String(r.name || "") : "",
          room_kind: String(r.kind || "")
        }
        seen[l.id] = rec
        out.push(rec)
      }
    }
    return out
  }

  readonly property var lightById: {
    var m = ({})
    var list = mapRoot.allLights || []
    for (var i = 0; i < list.length; i++) m[list[i].id] = list[i]
    return m
  }

  readonly property var placedLampList: {
    var out = []
    var all = mapRoot.allLights || []
    var map = mapRoot.fpLamps || ({})
    var q = String(lampSearchField.text || "").trim().toLowerCase()
    for (var i = 0; i < all.length; i++) {
      var l = all[i]
      if (!map[l.id]) continue
      if (q && l.name.toLowerCase().indexOf(q) < 0 && l.room_name.toLowerCase().indexOf(q) < 0) continue
      out.push({ light: l, pos: map[l.id] })
    }
    return out
  }

  readonly property var unplacedLampList: {
    var out = []
    var all = mapRoot.allLights || []
    var map = mapRoot.fpLamps || ({})
    var q = String(lampSearchField.text || "").trim().toLowerCase()
    for (var i = 0; i < all.length; i++) {
      var l = all[i]
      if (map[l.id]) continue
      if (q && l.name.toLowerCase().indexOf(q) < 0 && l.room_name.toLowerCase().indexOf(q) < 0) continue
      out.push(l)
    }
    return out
  }

  // All placed lamps (unfiltered) for canvas rendering
  readonly property var canvasPlacedLamps: {
    var out = []
    var all = mapRoot.allLights || []
    var map = mapRoot.fpLamps || ({})
    for (var i = 0; i < all.length; i++) {
      var l = all[i]
      if (map[l.id]) out.push({ light: l, pos: map[l.id] })
    }
    return out
  }

  // Placed lamps on the active floor only (canvas drawing + hit tests)
  readonly property var floorPlacedLamps: {
    var out = []
    var list = mapRoot.canvasPlacedLamps || []
    for (var i = 0; i < list.length; i++) if (mapRoot.floorOf(list[i].pos) === mapRoot.activeFloorId) out.push(list[i])
    return out
  }

  // Physical Hue Sensors & Bridge Pro MotionAware lookups
  readonly property var sensorById: {
    var m = ({})
    var list = mapRoot.sensors || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id) m[list[i].id] = list[i]
    }
    return m
  }

  readonly property var motionAreaById: {
    var m = ({})
    var list = mapRoot.motionAreas || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id) m[list[i].id] = list[i]
    }
    return m
  }

  function motionAreaForRoom(hueRoomId) {
    if (!hueRoomId) return null
    var list = mapRoot.motionAreas || []
    var fallback = null
    for (var i = 0; i < list.length; i++) {
      var a = list[i]
      if (!a || a.room_id !== hueRoomId) continue
      if (a.enabled === true && a.motion === true) return a
      if (!fallback || (a.enabled === true && !fallback.enabled)) fallback = a
    }
    return fallback
  }

  function sensorStatusText(s) {
    if (!s) return ""
    var parts = []
    if (s.kind === "motion") {
      if (s.enabled === false) parts.push(t("motionDisabled"))
      else parts.push(s.motion ? t("motionPresence") : t("motionClear"))
    } else if (s.kind === "contact") {
      if (s.enabled === false) parts.push(t("motionDisabled"))
      else parts.push(s.open ? t("sensorOpen") : t("sensorClosed"))
    } else if (s.kind === "button") {
      if (s.last_event) parts.push(String(s.last_event).replace(/_/g, " "))
      else parts.push(t("sensorKindButton"))
    }
    if (s.temperature !== null && s.temperature !== undefined) {
      parts.push(Number(s.temperature).toFixed(1) + "°C")
    }
    if (s.battery !== null && s.battery !== undefined) {
      parts.push(Math.round(Number(s.battery)) + "%")
    }
    return parts.join(" · ")
  }

  readonly property var placedSensorList: {
    var out = []
    var list = mapRoot.sensors || []
    var map = mapRoot.fpSensors || ({})
    var q = String(lampSearchField.text || "").trim().toLowerCase()
    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      if (!s || !s.id || !map[s.id]) continue
      if (q && String(s.name || "").toLowerCase().indexOf(q) < 0) continue
      out.push({ sensor: s, pos: map[s.id] })
    }
    return out
  }

  readonly property var unplacedSensorList: {
    var out = []
    var list = mapRoot.sensors || []
    var map = mapRoot.fpSensors || ({})
    var q = String(lampSearchField.text || "").trim().toLowerCase()
    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      if (!s || !s.id || map[s.id]) continue
      if (q && String(s.name || "").toLowerCase().indexOf(q) < 0) continue
      out.push(s)
    }
    return out
  }

  readonly property var canvasPlacedSensors: {
    var out = []
    var list = mapRoot.sensors || []
    var map = mapRoot.fpSensors || ({})
    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      if (s && s.id && map[s.id]) out.push({ sensor: s, pos: map[s.id] })
    }
    return out
  }
  readonly property var floorPlacedSensors: {
    var out = []
    var list = mapRoot.canvasPlacedSensors || []
    for (var i = 0; i < list.length; i++) if (mapRoot.floorOf(list[i].pos) === mapRoot.activeFloorId) out.push(list[i])
    return out
  }


  // Compute pending Bridge sync count (new boxes, renamed rooms/zones, moved lamps).
  // Hue resources only (extra-provider rooms/lights are never synced) and same floor only.
  readonly property int pendingSyncCount: {
    if (!mapRoot.huePaired) return 0
    var count = 0
    var boxes = mapRoot.fpBoxes || []
    var rs = mapRoot.rooms || []
    var byId = ({})
    for (var i = 0; i < rs.length; i++) {
      var rr = rs[i]
      if (!rr || !rr.id || !mapRoot.isHueId(rr.id)) continue
      if (rr.provider && rr.provider !== "hue") continue
      byId[rr.id] = rr
    }
    var roomBoxes = []
    for (var b = 0; b < boxes.length; b++) {
      var bx = boxes[b]
      if (!bx) continue
      if (bx.kind === "room") roomBoxes.push(bx)
      if (!bx.hue_id) {
        count += 1
      } else if (mapRoot.isHueId(bx.hue_id) && byId[bx.hue_id]) {
        var existing = byId[bx.hue_id]
        if (String(bx.name || "").trim() !== String(existing.name || "").trim()) count += 1
        else if (bx.archetype && existing.archetype && bx.archetype !== existing.archetype) count += 1
      }
    }
    var placed = mapRoot.canvasPlacedLamps || []
    for (var p = 0; p < placed.length; p++) {
      var lt = placed[p].light
      var pos = placed[p].pos
      if (!lt || !mapRoot.isHueId(lt.id)) continue
      var lf = mapRoot.floorOf(pos)
      var best = null
      var bestArea = 1e18
      for (var k = 0; k < roomBoxes.length; k++) {
        var rb = roomBoxes[k]
        if (mapRoot.floorOf(rb) !== lf) continue
        if (mapRoot.boxContains(rb, Number(pos.x), Number(pos.y))) {
          var area = mapRoot.boxAreaPx(rb)
          if (area < bestArea || (area === bestArea && rb.hue_id === lt.room_id)) {
            best = rb
            bestArea = area
          }
        }
      }
      if (best && best.hue_id && !mapRoot.isHueId(best.hue_id)) continue
      if (best && String(best.hue_id || "") !== String(lt.room_id || "")) count += 1
    }
    return count
  }

  // Helpers for room schedules, scenes, selection & entity lookups
  function findRoomByHueId(hueId) {
    if (!hueId) return null
    var rs = mapRoot.rooms || []
    for (var i = 0; i < rs.length; i++) {
      if (rs[i] && rs[i].id === hueId) return rs[i]
    }
    return null
  }

  function roomSchedules(hueId) {
    if (!hueId) return []
    var sc = mapRoot.schedules || []
    var out = []
    for (var i = 0; i < sc.length; i++) {
      if (sc[i] && sc[i].target_id === hueId) out.push(sc[i])
    }
    return out
  }

  function findBoxById(bid) {
    var bs = mapRoot.fpBoxes || []
    for (var i = 0; i < bs.length; i++) if (bs[i] && bs[i].id === bid) return bs[i]
    return null
  }

  function findStampById(sid) {
    var st = mapRoot.fpStamps || []
    for (var i = 0; i < st.length; i++) if (st[i] && st[i].id === sid) return st[i]
    return null
  }

  function entityName(kind, id) {
    if (kind === "light") {
      var l = lightById[id]
      if (l) return l.name
    } else if (kind === "room" || kind === "zone") {
      var rm = findRoomByHueId(id)
      if (rm) return rm.name
    } else if (kind === "motion" || kind === "contact" || kind === "button") {
      var sn = sensorById[id]
      if (sn) return sn.name
    } else if (kind === "motion_area") {
      var ma = motionAreaById[id]
      if (ma) return ma.name
    }
    return String(id || "").slice(0, 8)
  }

  function entityDotColor(kind, id) {
    if (kind === "light") {
      var l = lightById[id]
      if (l) return l.on ? (l.color || "#ffd27a") : Qt.rgba(fg.r, fg.g, fg.b, 0.35)
    } else if (kind === "room" || kind === "zone") {
      var rm = findRoomByHueId(id)
      if (rm) return rm.on ? (rm.color || "#ffd27a") : Qt.rgba(fg.r, fg.g, fg.b, 0.35)
    } else if (kind === "motion" || kind === "motion_area") {
      return "#10B981"
    } else if (kind === "contact") {
      return "#F59E0B"
    } else if (kind === "button") {
      return accentColor
    }
    return accentColor
  }

  function lampIconFor(lid) {
    var map = mapRoot.fpLamps || ({})
    return (map[lid] && map[lid].icon) ? String(map[lid].icon) : "bulb"
  }

  function lampIconLabel(iconId) {
    for (var i = 0; i < lampIconList.length; i++) {
      if (lampIconList[i].id === iconId) return t(lampIconList[i].key)
    }
    return t("lampIconBulb")
  }

  function contrastTintForLight(lt) {
    if (!lt || !lt.on) return Qt.rgba(1, 1, 1, 0.72)
    var c = Qt.color(lt.color || "#ffd27a")
    var luma = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    return luma > 0.56 ? "#141820" : "#ffffff"
  }

  function validHHMM(str) {
    return /^([01]\d|2[0-3]):([0-5]\d)$/.test(String(str || "").trim())
  }

  function autoRuleName() {
    var a = entityName(ruleEditFromKind, ruleEditFromId)
    var b = entityName(ruleEditToKind, ruleEditToId)
    return (a + " → " + b).slice(0, 56)
  }

  readonly property var selectedBox: selectedKind === "box" ? findBoxById(selectedId) : null
  readonly property var selectedHueRoom: selectedBox && selectedBox.hue_id ? findRoomByHueId(selectedBox.hue_id) : null
  readonly property var selectedRoomMotionArea: (selectedBox && selectedBox.hue_id) ? motionAreaForRoom(selectedBox.hue_id) : null
  readonly property var selectedStamp: selectedKind === "stamp" ? findStampById(selectedId) : null
  readonly property var dialogLight: dialogLampId ? (lightById[dialogLampId] || null) : null

  function selectItem(kind, id) {
    var target = null
    if (kind === "lamp") target = fpLamps[id]
    else if (kind === "sensor") target = fpSensors[id]
    else if (kind === "box") target = findBoxById(id)
    if (target && !onActiveFloor(target)) selectFloor(floorOf(target))
    selectedKind = kind
    selectedId = id
    confirmBridgeDelete = false
    if (kind === "planned") {
      var pl = selectedPlanned
      plannedNameField.text = pl ? String(pl.name || "") : ""
      plannedPriceField.text = pl && Number(pl.price) > 0 ? String(pl.price) : ""
    }
    if (kind === "box") {
      var b = findBoxById(id)
      if (b) roomRenameField.text = b.name
    }
    mapCanvas.requestPaint()
  }

  function snapVal(v) {
    if (!canvasSnap) return Math.round(v * 10) / 10
    return Math.round(v / canvasGrid) * canvasGrid
  }

  function fileUrlToPath(url) {
    var s = String(url || "").replace(/^file:\/\//, "")
    try { return decodeURIComponent(s) } catch (e) { return s }
  }

  function pathToFileUrl(p) {
    if (!p) return ""
    var encoded = String(p).replace(/%/g, "%25").replace(/#/g, "%23").replace(/\?/g, "%3F")
    return "file://" + encoded
  }

  function validOption(options, current, fallbackIdx) {
    if (!options || options.length === 0) return ""
    for (var i = 0; i < options.length; i++) if (options[i].value === current) return current
    var idx = fallbackIdx || 0
    return idx < options.length ? options[idx].value : options[0].value
  }

  function roomIconGlyph(arch, kind) {
    if (kind === "zone") return "󰌨"
    switch (arch) {
    case "living_room": case "lounge": case "tv": return "󰒹"
    case "kitchen": case "dining": return "󰩰"
    case "bedroom": case "kids_bedroom": case "guest_room": case "nursery": return "󰋣"
    case "bathroom": case "toilet": return "󰦠"
    case "office": case "computer": case "studio": return "󰌢"
    case "hallway": case "staircase": return "󰓍"
    case "garage": case "carport": return "󰛙"
    case "garden": case "terrace": case "balcony": case "porch": return "󰔱"
    default: return "󰋜"
    }
  }

  function stampLabel(kind) {
    switch (kind) {
    case "door": return t("stampDoor")
    case "window": return t("stampWindow")
    case "sofa": return t("stampSofa")
    case "tv": return t("stampTv")
    case "desk": return t("stampDesk")
    case "bed": return t("stampBed")
    case "dining": return t("stampDining")
    case "kitchen": return t("stampKitchen")
    case "stairs": return t("fpStairs")
    default: return kind
    }
  }

  // Bold, high-contrast filled vector silhouettes for all 12 allowlisted LAMP_ICONS
  function drawLampIcon(ctx, icon, cx, cy, sz, col) {
    var r = sz * 0.44
    ctx.save()
    ctx.translate(cx, cy)
    ctx.strokeStyle = col
    ctx.fillStyle = col
    ctx.lineWidth = Math.max(1.5, sz * 0.12)
    ctx.lineCap = "round"
    ctx.lineJoin = "round"

    if (icon === "spot") {
      // Bold filled angled spotlight head + 3 crisp rays
      ctx.beginPath()
      ctx.moveTo(-r * 0.72, -r * 0.78)
      ctx.lineTo(r * 0.24, -r * 0.78)
      ctx.lineTo(r * 0.56, -r * 0.02)
      ctx.lineTo(-r * 0.38, -r * 0.02)
      ctx.closePath()
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(-r * 0.22, r * 0.22)
      ctx.lineTo(-r * 0.54, r * 0.86)
      ctx.moveTo(r * 0.08, r * 0.22)
      ctx.lineTo(r * 0.08, r * 0.90)
      ctx.moveTo(r * 0.38, r * 0.22)
      ctx.lineTo(r * 0.72, r * 0.86)
      ctx.stroke()
    } else if (icon === "strip") {
      // Bold LED strip wave + 3 large emitter dots
      ctx.lineWidth = Math.max(1.8, sz * 0.14)
      ctx.beginPath()
      ctx.moveTo(-r * 0.88, r * 0.28)
      ctx.bezierCurveTo(-r * 0.36, -r * 0.72, r * 0.36, r * 0.72, r * 0.88, -r * 0.28)
      ctx.stroke()
      var pts = [[-r * 0.58, r * 0.08], [0, 0], [r * 0.58, -r * 0.08]]
      for (var i = 0; i < pts.length; i++) {
        ctx.beginPath()
        ctx.arc(pts[i][0], pts[i][1], Math.max(1.8, r * 0.24), 0, Math.PI * 2)
        ctx.fill()
      }
    } else if (icon === "floor") {
      // Tall floor lamp: filled trapezoid shade + thick pole + base
      ctx.beginPath()
      ctx.moveTo(-r * 0.44, -r * 0.88)
      ctx.lineTo(r * 0.44, -r * 0.88)
      ctx.lineTo(r * 0.68, -r * 0.14)
      ctx.lineTo(-r * 0.68, -r * 0.14)
      ctx.closePath()
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(0, -r * 0.16)
      ctx.lineTo(0, r * 0.86)
      ctx.moveTo(-r * 0.52, r * 0.86)
      ctx.lineTo(r * 0.52, r * 0.86)
      ctx.stroke()
    } else if (icon === "table") {
      // Table lamp: filled dome shade + thick stem + wide base
      ctx.beginPath()
      ctx.arc(0, r * 0.04, r * 0.70, Math.PI, 0)
      ctx.closePath()
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(0, r * 0.02)
      ctx.lineTo(0, r * 0.78)
      ctx.moveTo(-r * 0.54, r * 0.78)
      ctx.lineTo(r * 0.54, r * 0.78)
      ctx.stroke()
    } else if (icon === "pendant") {
      // Hanging pendant cord + filled dome + bulb dot
      ctx.beginPath()
      ctx.moveTo(0, -r * 0.94)
      ctx.lineTo(0, -r * 0.26)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(0, r * 0.30, r * 0.68, Math.PI, 0)
      ctx.closePath()
      ctx.fill()
      ctx.beginPath()
      ctx.arc(0, r * 0.56, Math.max(1.7, r * 0.22), 0, Math.PI * 2)
      ctx.fill()
    } else if (icon === "ceiling") {
      // Flush ceiling mount + filled dome + 3 bold rays
      ctx.beginPath()
      ctx.moveTo(-r * 0.88, -r * 0.60)
      ctx.lineTo(r * 0.88, -r * 0.60)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(0, -r * 0.60, r * 0.58, 0, Math.PI)
      ctx.closePath()
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(0, r * 0.22)
      ctx.lineTo(0, r * 0.84)
      ctx.moveTo(-r * 0.50, r * 0.14)
      ctx.lineTo(-r * 0.78, r * 0.66)
      ctx.moveTo(r * 0.50, r * 0.14)
      ctx.lineTo(r * 0.78, r * 0.66)
      ctx.stroke()
    } else if (icon === "wall") {
      // Wall plate + bracket + filled sconce cup + upward glow
      ctx.beginPath()
      ctx.moveTo(-r * 0.78, -r * 0.78)
      ctx.lineTo(-r * 0.78, r * 0.78)
      ctx.moveTo(-r * 0.78, r * 0.18)
      ctx.lineTo(-r * 0.22, r * 0.18)
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(-r * 0.26, -r * 0.26)
      ctx.lineTo(r * 0.72, -r * 0.26)
      ctx.lineTo(r * 0.48, r * 0.50)
      ctx.lineTo(-r * 0.06, r * 0.50)
      ctx.closePath()
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(r * 0.22, -r * 0.48)
      ctx.lineTo(r * 0.22, -r * 0.86)
      ctx.moveTo(-r * 0.08, -r * 0.46)
      ctx.lineTo(-r * 0.24, -r * 0.78)
      ctx.moveTo(r * 0.52, -r * 0.46)
      ctx.lineTo(r * 0.68, -r * 0.78)
      ctx.stroke()
    } else if (icon === "bar") {
      // Vertical Hue Play bar: bold filled vertical capsule + stand base + side ticks
      var bw = r * 0.30
      ctx.beginPath()
      ctx.arc(0, -r * 0.56, bw, Math.PI, 0)
      ctx.lineTo(bw, r * 0.34)
      ctx.arc(0, r * 0.34, bw, 0, Math.PI)
      ctx.closePath()
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(0, r * 0.58)
      ctx.lineTo(0, r * 0.86)
      ctx.moveTo(-r * 0.48, r * 0.86)
      ctx.lineTo(r * 0.48, r * 0.86)
      ctx.stroke()
      ctx.lineWidth = Math.max(1.2, sz * 0.09)
      ctx.beginPath()
      ctx.moveTo(-r * 0.56, -r * 0.40); ctx.lineTo(-r * 0.80, -r * 0.40)
      ctx.moveTo(-r * 0.56, 0);          ctx.lineTo(-r * 0.84, 0)
      ctx.moveTo(r * 0.56, -r * 0.40);   ctx.lineTo(r * 0.80, -r * 0.40)
      ctx.moveTo(r * 0.56, 0);           ctx.lineTo(r * 0.84, 0)
      ctx.stroke()
    } else if (icon === "desk") {
      // Articulated desk lamp: base + arm + bold filled cone shade
      ctx.beginPath()
      ctx.moveTo(-r * 0.62, r * 0.84)
      ctx.lineTo(r * 0.44, r * 0.84)
      ctx.moveTo(-r * 0.22, r * 0.84)
      ctx.lineTo(-r * 0.60, 0.0)
      ctx.lineTo(r * 0.08, -r * 0.68)
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(r * 0.04, -r * 0.74)
      ctx.lineTo(r * 0.78, -r * 0.16)
      ctx.lineTo(r * 0.22, r * 0.18)
      ctx.closePath()
      ctx.fill()
    } else if (icon === "outdoor") {
      // Outdoor sun: bold filled disc + 8 crisp rays
      ctx.beginPath()
      ctx.arc(0, 0, r * 0.42, 0, Math.PI * 2)
      ctx.fill()
      ctx.beginPath()
      for (var k = 0; k < 8; k++) {
        var ang = k * Math.PI * 0.25
        ctx.moveTo(Math.cos(ang) * r * 0.64, Math.sin(ang) * r * 0.64)
        ctx.lineTo(Math.cos(ang) * r * 0.94, Math.sin(ang) * r * 0.94)
      }
      ctx.stroke()
    } else if (icon === "candle") {
      // Filled candle body + bold filled flame
      ctx.fillRect(-r * 0.30, -r * 0.02, r * 0.60, r * 0.88)
      ctx.beginPath()
      ctx.moveTo(0, -r * 0.94)
      ctx.quadraticCurveTo(r * 0.40, -r * 0.34, 0, -r * 0.14)
      ctx.quadraticCurveTo(-r * 0.40, -r * 0.34, 0, -r * 0.94)
      ctx.fill()
    } else {
      // Default: bold filled classic lightbulb + screw base bars
      ctx.beginPath()
      ctx.arc(0, -r * 0.22, r * 0.58, Math.PI * 0.76, Math.PI * 0.24, false)
      ctx.lineTo(r * 0.28, r * 0.40)
      ctx.lineTo(-r * 0.28, r * 0.40)
      ctx.closePath()
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(-r * 0.26, r * 0.64)
      ctx.lineTo(r * 0.26, r * 0.64)
      ctx.moveTo(-r * 0.16, r * 0.86)
      ctx.lineTo(r * 0.16, r * 0.86)
      ctx.stroke()
    }
    ctx.restore()
  }

  // Crisp pure-vector icons for physical Hue sensors (motion, contact, button) & MotionAware radar
  function drawSensorIcon(ctx, kind, cx, cy, sz, col) {
    var r = sz * 0.44
    ctx.save()
    ctx.translate(cx, cy)
    ctx.strokeStyle = col
    ctx.fillStyle = col
    ctx.lineWidth = Math.max(1.4, sz * 0.11)
    ctx.lineCap = "round"
    ctx.lineJoin = "round"

    if (kind === "motion") {
      // Radar core + concentric signal waves
      ctx.beginPath()
      ctx.arc(0, 0, Math.max(1.6, r * 0.24), 0, Math.PI * 2)
      ctx.fill()
      ctx.beginPath()
      ctx.arc(0, 0, r * 0.56, -Math.PI * 0.36, Math.PI * 0.36)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(0, 0, r * 0.56, Math.PI * 0.64, Math.PI * 1.36)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(0, 0, r * 0.88, -Math.PI * 0.32, Math.PI * 0.32)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(0, 0, r * 0.88, Math.PI * 0.68, Math.PI * 1.32)
      ctx.stroke()
    } else if (kind === "contact") {
      // Split magnetic door/window contact sensor halves
      ctx.fillRect(-r * 0.78, -r * 0.72, r * 0.54, r * 1.44)
      ctx.strokeRect(r * 0.18, -r * 0.72, r * 0.56, r * 1.44)
      ctx.beginPath()
      ctx.moveTo(-r * 0.12, -r * 0.18); ctx.lineTo(r * 0.08, -r * 0.18)
      ctx.moveTo(-r * 0.12, r * 0.18);  ctx.lineTo(r * 0.08, r * 0.18)
      ctx.stroke()
    } else {
      // Tactile Hue switch / button pad
      ctx.strokeRect(-r * 0.66, -r * 0.78, r * 1.32, r * 1.56)
      ctx.beginPath()
      ctx.arc(0, -r * 0.28, Math.max(1.5, r * 0.20), 0, Math.PI * 2)
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(-r * 0.34, r * 0.32)
      ctx.lineTo(r * 0.34, r * 0.32)
      ctx.stroke()
    }
    ctx.restore()
  }

  component SensorGlyph: Canvas {
    id: sGlyph
    property string sensorKind: "motion"
    property color tint: mapRoot.fg
    width: Style.space(15)
    height: Style.space(15)
    onSensorKindChanged: requestPaint()
    onTintChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onAvailableChanged: if (available) requestPaint()
    Component.onCompleted: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      mapRoot.drawSensorIcon(ctx, sensorKind, width * 0.5, height * 0.5, Math.min(width, height), tint)
    }
  }

  // Reusable Canvas glyph (auto-repaints on iconName, tint, version, size, or availability changes)
  component LampGlyph: Canvas {
    id: glyph
    property string iconName: "bulb"
    property color tint: mapRoot.fg
    property int version: mapRoot.iconVersion
    width: Style.space(16)
    height: Style.space(16)
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
      mapRoot.drawLampIcon(ctx, iconName, width / 2, height / 2, Math.min(width, height), tint)
    }
  }

  // Actions: add room / zone / stamp / place lamp / set icon / open dialogs
  function addBox(kind, shape) {
    var fp = cloneFp(workingFp)
    if (!Array.isArray(fp.boxes)) fp.boxes = []
    if (fp.boxes.length >= 40) return
    var id = "box-" + Date.now() + "-" + (fp.boxes.length + 1)
    var offset = (fp.boxes.length % 5) * 30
    var bx = snapVal(Math.min(canvasW - 320, 120 + offset))
    var by = snapVal(Math.min(canvasH - 240, 120 + offset))
    var box = {
      id: id,
      kind: kind === "zone" ? "zone" : "room",
      hue_id: null,
      name: kind === "zone" ? (t("zone") + " " + (fp.boxes.length + 1)) : (t("mapRoom") + " " + (fp.boxes.length + 1)),
      archetype: "other",
      x: Math.max(0, bx),
      y: Math.max(0, by),
      w: shape ? 340 : 300,
      h: shape ? 260 : 220,
      entertainment_area_id: null,
      points: [],
      floor_id: activeFloorId
    }
    if (shape) applyShape(box, shape)
    fp.boxes.push(box)
    showAddMenu = false
    commitFp(fp, true)
    selectItem("box", id)
  }

  function addStamp(kind) {
    var fp = cloneFp(workingFp)
    if (!Array.isArray(fp.stamps)) fp.stamps = []
    if (fp.stamps.length >= 80) return
    var def = stampKindList[0]
    for (var i = 0; i < stampKindList.length; i++) if (stampKindList[i].id === kind) { def = stampKindList[i]; break }
    var id = "st-" + Date.now() + "-" + (fp.stamps.length + 1)
    var sx = snapVal(canvasW * 0.5 - def.w * 0.5)
    var sy = snapVal(canvasH * 0.5 - def.h * 0.5)
    if (selectedBox) {
      sx = snapVal(selectedBox.x + selectedBox.w * 0.5 - def.w * 0.5)
      sy = snapVal(selectedBox.y + selectedBox.h * 0.5 - def.h * 0.5)
    }
    fp.stamps.push({
      id: id,
      kind: def.id,
      x: Math.max(0, Math.min(canvasW - def.w, sx)),
      y: Math.max(0, Math.min(canvasH - def.h, sy)),
      w: def.w,
      h: def.h,
      rot: 0,
      floor_id: activeFloorId
    })
    showAddMenu = false
    commitFp(fp, false)
    selectItem("stamp", id)
  }

  // ---- Floorplan Studio v2 actions: floors, gallery, polygon corners, planner ----
  function selectFloor(fid) {
    if (fid === activeFloorId) return
    for (var i = 0; i < fpFloors.length; i++) {
      if (fpFloors[i].id !== fid) continue
      var fp = cloneFp(workingFp)
      fp.active_floor_id = fid
      selectedKind = ""
      selectedId = ""
      floorRenameOpen = false
      commitFp(fp, false)
      return
    }
  }

  function addFloor() {
    var fp = cloneFp(workingFp)
    if (!Array.isArray(fp.floors) || fp.floors.length === 0) fp.floors = [{ id: "eg", name: "Ground Floor", level: 0 }]
    if (fp.floors.length >= 12) return
    var lvl = 0
    for (var i = 0; i < fp.floors.length; i++) lvl = Math.max(lvl, Number(fp.floors[i].level || 0))
    lvl = Math.min(20, lvl + 1)
    var idx = fp.floors.length + 1
    var fid = "fl-" + idx
    var taken = true
    while (taken) {
      taken = false
      for (var k = 0; k < fp.floors.length; k++) if (fp.floors[k].id === fid) { taken = true; idx += 1; fid = "fl-" + idx; break }
    }
    var name = lvl === 1 ? "Upper Floor" : (lvl === 2 ? "Attic" : ("Floor " + lvl))
    fp.floors.push({ id: fid, name: name, level: lvl })
    fp.active_floor_id = fid
    selectedKind = ""
    selectedId = ""
    floorRenameOpen = false
    commitFp(fp, false)
  }

  function startFloorRename() {
    for (var i = 0; i < fpFloors.length; i++) {
      if (fpFloors[i].id === activeFloorId) {
        floorRenameField.text = floorLabel(fpFloors[i].name)
        floorRenameOpen = true
        Qt.callLater(function() { floorRenameField.forceActiveFocus() })
        return
      }
    }
  }

  function saveFloorRename() {
    var nm = String(floorRenameField.text || "").replace(/[<>&]/g, "").trim().slice(0, 32)
    if (!nm) return
    var fp = cloneFp(workingFp)
    for (var i = 0; i < (fp.floors || []).length; i++) {
      if (fp.floors[i].id === activeFloorId) fp.floors[i].name = nm
    }
    floorRenameOpen = false
    commitFp(fp, false)
    returnFocusRequested()
  }

  function deleteFloor(fid) {
    if (fpFloors.length <= 1) return
    undoFp = cloneFp(workingFp)
    var fp = cloneFp(workingFp)
    fp.floors = fp.floors.filter(function(f) { return f.id !== fid })
    var fallback = fp.floors.length > 0 ? fp.floors[0].id : "eg"
    var floorIdOf = function(o) { return String((o && o.floor_id) || "") || mapRoot.defaultFloorId }
    fp.boxes = (fp.boxes || []).filter(function(b) { return floorIdOf(b) !== fid })
    fp.stamps = (fp.stamps || []).filter(function(st) { return floorIdOf(st) !== fid })
    fp.planned_lights = (fp.planned_lights || []).filter(function(pl) { return floorIdOf(pl) !== fid })
    for (var lid in (fp.lamps || {})) if (floorIdOf(fp.lamps[lid]) === fid) fp.lamps[lid].floor_id = fallback
    for (var sid in (fp.sensors || {})) if (floorIdOf(fp.sensors[sid]) === fid) fp.sensors[sid].floor_id = fallback
    if (String(fp.active_floor_id || "") === fid || !fp.active_floor_id) fp.active_floor_id = fallback
    selectedKind = ""
    selectedId = ""
    floorRenameOpen = false
    commitFp(fp, false)
  }

  function undoFloorplan() {
    if (!undoFp) return
    var prev = undoFp
    undoFp = null
    selectedKind = ""
    selectedId = ""
    floorRenameOpen = false
    commitFp(cloneFp(prev), false)
  }

  // Gallery: replacing a non-empty map needs a second click; the old map stays undoable.
  function applyTemplate(tid) {
    if (fpBoxes.length > 0 && confirmTemplateId !== tid) {
      confirmTemplateId = tid
      return
    }
    confirmTemplateId = ""
    undoFp = cloneFp(workingFp)
    showGallery = false
    selectedKind = ""
    selectedId = ""
    sendCommand({ cmd: "floorplan_template", template_id: tid, include_plan: galleryIncludePlan })
  }

  function boxApplyShape(bid, shape) {
    var fp = cloneFp(workingFp)
    for (var i = 0; i < (fp.boxes || []).length; i++) {
      if (fp.boxes[i].id === bid) {
        applyShape(fp.boxes[i], shape)
        commitFp(fp, true)
        return
      }
    }
  }

  // Move a room to another floor, taking along the lamps, sensors and planned lights inside it.
  function boxSetFloor(bid, fid) {
    var fp = cloneFp(workingFp)
    var b = null
    for (var i = 0; i < (fp.boxes || []).length; i++) if (fp.boxes[i].id === bid) b = fp.boxes[i]
    if (!b) return
    var oldF = floorOf(b)
    if (oldF === fid) return
    for (var lid in (fp.lamps || {})) {
      var lp = fp.lamps[lid]
      if (floorOf(lp) === oldF && boxContains(b, Number(lp.x), Number(lp.y))) lp.floor_id = fid
    }
    for (var sid in (fp.sensors || {})) {
      var sp = fp.sensors[sid]
      if (floorOf(sp) === oldF && boxContains(b, Number(sp.x), Number(sp.y))) sp.floor_id = fid
    }
    for (var k = 0; k < (fp.planned_lights || []).length; k++) {
      var pl = fp.planned_lights[k]
      var an = plannedAnchor(pl)
      if (floorOf(pl) === oldF && boxContains(b, an.x, an.y)) pl.floor_id = fid
    }
    b.floor_id = fid
    selectedKind = ""
    selectedId = ""
    commitFp(fp, true)
  }

  function insertBoxVertex(bid, afterEdge, x, y) {
    var fp = cloneFp(workingFp)
    for (var i = 0; i < (fp.boxes || []).length; i++) {
      var b = fp.boxes[i]
      if (b.id !== bid) continue
      if (!isPolygon(b)) b.points = boxPoints(b)
      if (b.points.length >= 32 || afterEdge < 0 || afterEdge >= b.points.length) return
      b.points.splice(afterEdge + 1, 0, { x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10 })
      syncBounds(b)
      commitFp(fp, true)
      return
    }
  }

  function removeBoxVertex(bid, index) {
    var fp = cloneFp(workingFp)
    for (var i = 0; i < (fp.boxes || []).length; i++) {
      var b = fp.boxes[i]
      if (b.id !== bid || !isPolygon(b) || b.points.length <= 3 || index < 0 || index >= b.points.length) continue
      b.points.splice(index, 1)
      syncBounds(b)
      commitFp(fp, true)
      return
    }
  }

  function addPlanned(presetId) {
    var preset = plannedPresetList[0]
    for (var i = 0; i < plannedPresetList.length; i++) if (plannedPresetList[i].id === presetId) preset = plannedPresetList[i]
    var fp = cloneFp(workingFp)
    if (!Array.isArray(fp.planned_lights)) fp.planned_lights = []
    if (fp.planned_lights.length >= 120) return
    var id = "plan-" + Date.now() + "-" + (fp.planned_lights.length + 1)
    var offset = (fp.planned_lights.length % 6) * 26
    var cx = Math.max(60, Math.min(canvasW - 60, canvasW * 0.5 - 60 + offset))
    var cy = Math.max(60, Math.min(canvasH - 60, canvasH * 0.5 - 40 + offset))
    if (selectedBox && selectedBox.kind === "room") {
      cx = selectedBox.x + selectedBox.w * 0.5
      cy = selectedBox.y + selectedBox.h * 0.5
    }
    cx = Math.round(cx * 10) / 10
    cy = Math.round(cy * 10) / 10
    fp.planned_lights.push({
      id: id,
      floor_id: activeFloorId,
      name: t(preset.key),
      icon: preset.icon,
      x: cx,
      y: cy,
      strip_points: preset.strip ? [{ x: cx - 70, y: cy }, { x: cx, y: cy }, { x: cx + 70, y: cy }] : [],
      lumens: preset.lumens,
      beam_radius: preset.beam,
      kelvin: preset.kelvin,
      color: kelvinToHex(preset.kelvin),
      on: true,
      model_note: "",
      price: preset.price
    })
    closeMenus()
    commitFp(fp, false)
    selectItem("planned", id)
  }

  // Apply fn(plannedLight) to the planned light with this id and save.
  function editPlanned(pid, fn) {
    var fp = cloneFp(workingFp)
    var list = fp.planned_lights || []
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === pid) {
        fn(list[i])
        commitFp(fp, false)
        return
      }
    }
  }

  function deletePlanned(pid) {
    var fp = cloneFp(workingFp)
    fp.planned_lights = (fp.planned_lights || []).filter(function(p) { return p.id !== pid })
    if (selectedKind === "planned" && selectedId === pid) { selectedKind = ""; selectedId = "" }
    commitFp(fp, false)
  }

  // Replace a planned fixture with a real paired light at the same spot.
  function bindPlannedToReal(pid, lid) {
    var fp = cloneFp(workingFp)
    var list = fp.planned_lights || []
    for (var i = 0; i < list.length; i++) {
      if (list[i].id !== pid) continue
      var pl = list.splice(i, 1)[0]
      var an = plannedAnchor(pl)
      if (!fp.lamps || typeof fp.lamps !== "object") fp.lamps = ({})
      var icon = String(pl.icon || "bulb")
      var known = false
      for (var k = 0; k < lampIconList.length; k++) if (lampIconList[k].id === icon) known = true
      fp.lamps[lid] = {
        x: Math.max(0, Math.min(canvasW, Math.round(an.x * 10) / 10)),
        y: Math.max(0, Math.min(canvasH, Math.round(an.y * 10) / 10)),
        z: 0.0,
        icon: known ? icon : "bulb",
        floor_id: floorOf(pl)
      }
      iconVersion += 1
      commitFp(fp, true)
      selectItem("lamp", lid)
      return
    }
  }

  function placeLamp(lid, cx, cy) {
    if (!lid) return
    var fp = cloneFp(workingFp)
    if (!fp.lamps || typeof fp.lamps !== "object") fp.lamps = ({})
    var px = cx
    var py = cy
    if (px === undefined || py === undefined) {
      if (selectedBox) {
        px = selectedBox.x + selectedBox.w * 0.5
        py = selectedBox.y + selectedBox.h * 0.5
      } else {
        var lt = lightById[lid]
        var matched = null
        if (lt && lt.room_id) {
          for (var i = 0; i < fp.boxes.length; i++) {
            if (fp.boxes[i].hue_id === lt.room_id && floorOf(fp.boxes[i]) === activeFloorId) { matched = fp.boxes[i]; break }
          }
        }
        if (matched) {
          px = matched.x + matched.w * 0.5
          py = matched.y + matched.h * 0.5
        } else {
          px = canvasW * 0.5
          py = canvasH * 0.5
        }
      }
    }
    fp.lamps[lid] = {
      x: Math.max(20, Math.min(canvasW - 20, snapVal(px))),
      y: Math.max(20, Math.min(canvasH - 20, snapVal(py))),
      z: 0.0,
      icon: (fp.lamps[lid] && fp.lamps[lid].icon) ? fp.lamps[lid].icon : "bulb",
      floor_id: activeFloorId
    }
    openMenuLampId = ""
    iconVersion += 1
    commitFp(fp, true)
    selectItem("lamp", lid)
  }

  function unplaceLamp(lid) {
    var fp = cloneFp(workingFp)
    if (fp.lamps && lid in fp.lamps) {
      delete fp.lamps[lid]
      iconVersion += 1
      commitFp(fp, false)
    }
    if (hoverLampId === lid) hoverLampId = ""
    if (openMenuLampId === lid) openMenuLampId = ""
    if (selectedKind === "lamp" && selectedId === lid) {
      selectedKind = ""
      selectedId = ""
    }
  }

  function setLampIcon(lid, iconId) {
    if (!lid) return
    var fp = cloneFp(workingFp)
    if (!fp.lamps || typeof fp.lamps !== "object") fp.lamps = ({})
    if (!fp.lamps[lid]) {
      var lt = lightById[lid]
      var matched = null
      if (lt && lt.room_id && Array.isArray(fp.boxes)) {
        for (var i = 0; i < fp.boxes.length; i++) {
          if (fp.boxes[i].hue_id === lt.room_id) { matched = fp.boxes[i]; break }
        }
      }
      var px = matched ? (matched.x + matched.w * 0.5) : (canvasW * 0.5)
      var py = matched ? (matched.y + matched.h * 0.5) : (canvasH * 0.5)
      fp.lamps[lid] = {
        x: Math.max(20, Math.min(canvasW - 20, snapVal(px))),
        y: Math.max(20, Math.min(canvasH - 20, snapVal(py))),
        z: 0.0,
        icon: iconId,
        floor_id: activeFloorId
      }
    } else {
      fp.lamps[lid].icon = iconId
    }
    iconVersion += 1
    commitFp(fp, false)
  }

  function startWireFromLight(lid) {
    resetTransient()
    toolMode = "wire"
    if (lid && fpLamps && fpLamps[lid]) {
      wireFromKind = "light"
      wireFromId = lid
    }
    mapCanvas.requestPaint()
  }

  function placeSensor(sid, cx, cy) {
    if (!sid) return
    var fp = cloneFp(workingFp)
    if (!fp.sensors || typeof fp.sensors !== "object") fp.sensors = ({})
    var px = cx
    var py = cy
    if (px === undefined || py === undefined) {
      if (selectedBox) {
        px = selectedBox.x + selectedBox.w * 0.5
        py = selectedBox.y + selectedBox.h * 0.5
      } else {
        var sn = sensorById[sid]
        var matched = null
        if (sn && sn.room_id) {
          for (var i = 0; i < (fp.boxes || []).length; i++) {
            if (fp.boxes[i].hue_id === sn.room_id && floorOf(fp.boxes[i]) === activeFloorId) { matched = fp.boxes[i]; break }
          }
        }
        if (matched) {
          px = matched.x + matched.w * 0.5
          py = matched.y + matched.h * 0.5
        } else {
          px = canvasW * 0.5
          py = canvasH * 0.5
        }
      }
    }
    fp.sensors[sid] = {
      x: Math.max(20, Math.min(canvasW - 20, snapVal(px))),
      y: Math.max(20, Math.min(canvasH - 20, snapVal(py))),
      floor_id: activeFloorId
    }
    openMenuSensorId = ""
    commitFp(fp, false)
    selectItem("sensor", sid)
  }

  function unplaceSensor(sid) {
    var fp = cloneFp(workingFp)
    if (fp.sensors && sid in fp.sensors) {
      delete fp.sensors[sid]
      commitFp(fp, false)
    }
    if (hoverSensorId === sid) hoverSensorId = ""
    if (openMenuSensorId === sid) openMenuSensorId = ""
    if (selectedKind === "sensor" && selectedId === sid) {
      selectedKind = ""
      selectedId = ""
    }
  }

  function triggerStateOptionsFor(kind) {
    if (kind === "motion" || kind === "motion_area") {
      return [
        { id: "motion", key: "trigMotionDetected" },
        { id: "clear",  key: "trigNoMotion" }
      ]
    }
    if (kind === "contact") {
      return [
        { id: "open",   key: "trigOpens" },
        { id: "closed", key: "trigCloses" }
      ]
    }
    if (kind === "button") {
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

  function defaultTriggerStateFor(kind) {
    var opts = triggerStateOptionsFor(kind)
    return opts.length > 0 ? opts[0].id : "on"
  }

  function isSensorTriggerKind(kind) {
    return kind === "motion" || kind === "motion_area" || kind === "contact" || kind === "button"
  }

  function openBrightnessDialog(lid) {
    if (!lid) return
    openMenuLampId = ""
    dialogLampId = lid
    activeDialog = "brightness"
  }

  function openRenameDialog(lid) {
    if (!lid) return
    openMenuLampId = ""
    dialogLampId = lid
    var lt = lightById[lid]
    lampRenameField.text = lt ? String(lt.name || "") : ""
    lampRenameField.cursorPosition = lampRenameField.text.length
    activeDialog = "rename"
    Qt.callLater(function() { lampRenameField.forceActiveFocus() })
  }

  function openIconDialog(lid) {
    if (!lid) return
    openMenuLampId = ""
    dialogLampId = lid
    activeDialog = "icon"
  }

  function openNewRuleDialog(fromKind, fromId, toKind, toId) {
    if (!fromId || !toId) return
    if (fromKind === toKind && fromId === toId) return
    openMenuLampId = ""
    openMenuSensorId = ""
    ruleEditId = ""
    ruleEditEnabled = true
    ruleEditFromKind = fromKind || "light"
    ruleEditFromId = fromId
    ruleEditToKind = toKind || "light"
    ruleEditToId = toId
    ruleEditKind = "follow"
    ruleEditTriggerState = defaultTriggerStateFor(ruleEditFromKind)
    ruleEditMirrorOff = ruleEditFromKind !== "button"
    ruleEditMatchBri = false
    ruleEditOnlyIfOff = false
    ruleEditExtraTargets = []
    mapRuleStartField.clear()
    mapRuleEndField.clear()
    mapRuleNameField.clear()
    wireFromKind = "light"
    wireFromId = ""
    wireDragging = false
    activeDialog = "rule"
    mapCanvas.requestPaint()
  }

  function openEditRuleDialog(rule) {
    if (!rule || !rule.id) return
    openMenuLampId = ""
    openMenuSensorId = ""
    var targs = rule.targets || []
    var t0 = targs.length > 0 ? targs[0] : ({ kind: "light", id: "" })
    ruleEditId = String(rule.id)
    ruleEditEnabled = rule.enabled !== false
    ruleEditFromKind = String(rule.trigger_kind || "light")
    ruleEditFromId = String(rule.trigger_id || "")
    ruleEditToKind = String(t0.kind || "light")
    ruleEditToId = String(t0.id || "")
    ruleEditKind = (rule.kind === "exclusive" || rule.kind === "companion") ? rule.kind : "follow"
    var opts = triggerStateOptionsFor(ruleEditFromKind)
    var st = String(rule.trigger_state || "")
    var stValid = false
    for (var si = 0; si < opts.length; si++) if (opts[si].id === st) { stValid = true; break }
    ruleEditTriggerState = stValid ? st : defaultTriggerStateFor(ruleEditFromKind)
    ruleEditMirrorOff = rule.mirror_off === true
    ruleEditMatchBri = rule.match_bri === true
    ruleEditOnlyIfOff = rule.only_if_off === true
    ruleEditExtraTargets = targs.length > 1 ? targs.slice(1) : []
    mapRuleStartField.text = String(rule.time_start || "")
    mapRuleEndField.text = String(rule.time_end || "")
    mapRuleNameField.text = String(rule.name || "")
    wireFromKind = "light"
    wireFromId = ""
    wireDragging = false
    activeDialog = "rule"
    mapCanvas.requestPaint()
  }

  function saveRuleFromDialog() {
    if (!ruleEditFromId || !ruleEditToId) return
    if (ruleEditFromKind === ruleEditToKind && ruleEditFromId === ruleEditToId) return
    var ts = mapRuleStartField.text.trim()
    var te = mapRuleEndField.text.trim()
    if ((ts !== "" || te !== "") && (!validHHMM(ts) || !validHHMM(te))) return
    var isExcl = ruleEditKind === "exclusive"
    var isSens = isSensorTriggerKind(ruleEditFromKind)
    var targets = [{
      kind: ruleEditToKind,
      id: ruleEditToId,
      action: isExcl ? "off" : "on",
      bri: null,
      scene_id: ""
    }]
    for (var i = 0; i < ruleEditExtraTargets.length; i++) {
      var et = ruleEditExtraTargets[i]
      if (et && et.kind && et.id) targets.push(et)
    }
    var ruleObj = {
      name: mapRuleNameField.text.trim() || autoRuleName(),
      enabled: ruleEditId !== "" ? ruleEditEnabled : true,
      kind: ruleEditKind,
      trigger_kind: ruleEditFromKind,
      trigger_id: ruleEditFromId,
      trigger_state: ruleEditTriggerState,
      targets: targets,
      mirror_off: (isExcl || ruleEditFromKind === "button") ? false : ruleEditMirrorOff,
      match_bri: (isExcl || isSens) ? false : ruleEditMatchBri,
      only_if_off: isExcl ? false : ruleEditOnlyIfOff,
      time_start: ts,
      time_end: te
    }
    if (ruleEditId !== "") ruleObj.id = ruleEditId
    sendCommand({ cmd: "rule_save", rule: ruleObj })
    closeDialog()
    mapCanvas.requestPaint()
  }

  // Canvas centre of a rule endpoint on the active floor (null when it is on another floor).
  function entityCenter(kind, id) {
    if (kind === "light" && fpLamps[id]) {
      if (!onActiveFloor(fpLamps[id])) return null
      return { x: Number(fpLamps[id].x), y: Number(fpLamps[id].y) }
    }
    if ((kind === "motion" || kind === "contact" || kind === "button") && fpSensors[id]) {
      if (!onActiveFloor(fpSensors[id])) return null
      return { x: Number(fpSensors[id].x), y: Number(fpSensors[id].y) }
    }
    if (kind === "motion_area") {
      var ma = motionAreaById[id]
      if (ma && ma.room_id) return entityCenter("room", ma.room_id)
      return null
    }
    if (kind === "room" || kind === "zone") {
      for (var i = 0; i < fpBoxes.length; i++) {
        if (fpBoxes[i].hue_id === id && onActiveFloor(fpBoxes[i])) {
          return { x: fpBoxes[i].x + fpBoxes[i].w * 0.5, y: fpBoxes[i].y + fpBoxes[i].h * 0.5 }
        }
      }
    }
    return null
  }

  // Native Qt6 FileDialog for custom background image (validated & 0600-copied by Python backend)
  FileDialog {
    id: bgFileDialog
    title: mapRoot.t("mapBackground")
    nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
    onAccepted: {
      var local = mapRoot.fileUrlToPath(selectedFile)
      if (local) {
        bgPathField.text = local
        mapRoot.sendCommand({ cmd: "floorplan_bg_set", path: local })
      }
    }
  }

  // =========================================================================
  // MAIN CONTENT COLUMN
  // =========================================================================
  Column {
    id: mainCol
    width: parent.width
    spacing: Style.space(7)

    // =======================================================================
    // 1. CLEAN 1-ROW TOOLBAR WITH [Map | Rules] SUB-TAB SWITCHER
    // =======================================================================
    Flow {
      width: parent.width
      spacing: Style.space(5)

      // Segmented [Map | Rules] sub-tab switcher
      Rectangle {
        height: Style.space(24)
        width: segRow.implicitWidth + Style.space(4)
        radius: mapRoot.corners.control
        color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.06)
        border.width: 1
        border.color: mapRoot.cardBorderColor

        Row {
          id: segRow
          anchors.centerIn: parent
          spacing: Style.space(2)

          Rectangle {
            readonly property bool active: mapRoot.toolMode === "select"
            width: segMapTxt.implicitWidth + Style.space(12)
            height: Style.space(20)
            radius: Math.max(2, mapRoot.corners.control - 1)
            color: active ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.24) : "transparent"
            Text {
              id: segMapTxt
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: mapRoot.t("tabMap")
              color: parent.active ? mapRoot.fg : mapRoot.dim
              font.family: mapRoot.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: parent.active
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                mapRoot.closeMenus()
                mapRoot.toolMode = "select"
                mapRoot.wireFromId = ""
                mapRoot.wireDragging = false
                mapCanvas.requestPaint()
              }
            }
          }

          Rectangle {
            readonly property bool active: mapRoot.toolMode === "plan"
            width: segPlanTxt.implicitWidth + Style.space(12)
            height: Style.space(20)
            radius: Math.max(2, mapRoot.corners.control - 1)
            color: active ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.24) : "transparent"
            Text {
              id: segPlanTxt
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: mapRoot.t("fpModePlan")
              color: parent.active ? mapRoot.fg : mapRoot.dim
              font.family: mapRoot.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: parent.active
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                mapRoot.closeMenus()
                mapRoot.toolMode = "plan"
                mapRoot.wireFromId = ""
                mapRoot.wireDragging = false
                mapCanvas.requestPaint()
              }
            }
          }

          Rectangle {
            readonly property bool active: mapRoot.toolMode === "wire"
            width: segRulesTxt.implicitWidth + Style.space(12)
            height: Style.space(20)
            radius: Math.max(2, mapRoot.corners.control - 1)
            color: active ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.24) : "transparent"
            Text {
              id: segRulesTxt
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: mapRoot.t("tabRules")
              color: parent.active ? mapRoot.fg : mapRoot.dim
              font.family: mapRoot.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: parent.active
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                mapRoot.toolMode = "wire"
                mapRoot.selectedKind = ""
                mapRoot.selectedId = ""
                mapRoot.closeMenus()
                mapCanvas.requestPaint()
              }
            }
          }
        }
      }

      // Sidebar toggle ("Lamps") — visible in both Map and Rules sub-tabs
      Button {
        radius: mapRoot.corners.control
        iconText: "󰋶"
        text: mapRoot.t("mapLamps")
        bordered: true
        selected: mapRoot.showSidebar
        accent: mapRoot.accentColor
        foreground: mapRoot.fg
        fontFamily: mapRoot.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(2)
        tooltipText: mapRoot.t("mapSidebarTip")
        onClicked: { mapRoot.sidebarUserSet = true; mapRoot.showSidebar = !mapRoot.showSidebar }
      }

      // ---- MAP SUB-TAB CONTROLS ----
      Button {
        visible: mapRoot.toolMode === "select"
        radius: mapRoot.corners.control
        text: mapRoot.t("mapAddMenu") + " ▾"
        bordered: true
        selected: mapRoot.showAddMenu
        accent: mapRoot.accentColor
        foreground: mapRoot.fg
        fontFamily: mapRoot.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(2)
        onClicked: {
          var next = !mapRoot.showAddMenu
          mapRoot.closeMenus()
          mapRoot.showAddMenu = next
        }
      }

      // ---- PLAN SUB-TAB CONTROLS ----
      Button {
        visible: mapRoot.toolMode === "plan"
        radius: mapRoot.corners.control
        text: mapRoot.t("fpAddFixture") + " ▾"
        bordered: true
        selected: mapRoot.showPlanAdd
        accent: mapRoot.accentColor
        foreground: mapRoot.fg
        fontFamily: mapRoot.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(2)
        onClicked: {
          var next = !mapRoot.showPlanAdd
          mapRoot.closeMenus()
          mapRoot.showPlanAdd = next
        }
      }
      Button {
        visible: mapRoot.toolMode === "plan"
        radius: mapRoot.corners.control
        text: mapRoot.fpPlanned.length > 0 ? (mapRoot.t("fpPlanList") + " (" + mapRoot.fpPlanned.length + ")") : mapRoot.t("fpPlanList")
        bordered: true
        selected: mapRoot.showPlanList
        accent: mapRoot.accentColor
        foreground: mapRoot.fg
        fontFamily: mapRoot.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(2)
        onClicked: {
          var next = !mapRoot.showPlanList
          mapRoot.closeMenus()
          mapRoot.showPlanList = next
        }
      }

      Button {
        visible: mapRoot.editMode
        radius: mapRoot.corners.control
        iconText: "󰉖"
        text: mapRoot.t("fpGallery") + " ▾"
        bordered: true
        selected: mapRoot.showGallery
        accent: mapRoot.accentColor
        foreground: mapRoot.fg
        fontFamily: mapRoot.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(2)
        onClicked: {
          var next = !mapRoot.showGallery
          mapRoot.closeMenus()
          mapRoot.showGallery = next
        }
      }

      Button {
        visible: mapRoot.toolMode === "select"
        radius: mapRoot.corners.control
        text: mapRoot.t("mapViewMenu") + " ▾"
        bordered: true
        selected: mapRoot.showViewMenu || mapRoot.showBgBar
        accent: mapRoot.accentColor
        foreground: mapRoot.fg
        fontFamily: mapRoot.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(2)
        onClicked: {
          var next = !mapRoot.showViewMenu
          mapRoot.closeMenus()
          mapRoot.showViewMenu = next
        }
      }

      Button {
        visible: mapRoot.toolMode === "select" && mapRoot.huePaired
        radius: mapRoot.corners.control
        iconText: "󰓦"
        text: mapRoot.pendingSyncCount > 0 ? mapRoot.t("mapSyncPending", [mapRoot.pendingSyncCount]) : mapRoot.t("mapSyncBridge")
        bordered: true
        selected: mapRoot.pendingSyncCount > 0
        accent: mapRoot.accentColor
        foreground: mapRoot.fg
        fontFamily: mapRoot.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(2)
        onClicked: mapRoot.sendCommand({ cmd: "floorplan_sync_all" })
      }

      // ---- RULES SUB-TAB MINIMAL CONTROL ----
      Button {
        visible: mapRoot.toolMode === "wire"
        radius: mapRoot.corners.control
        iconText: "󰊓"
        text: mapRoot.t("mapFit")
        bordered: true
        foreground: mapRoot.fg
        fontFamily: mapRoot.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(2)
        tooltipText: mapRoot.t("mapFitTip")
        onClicked: { mapRoot.userZoom = 1.0; mapRoot.userPanX = 0; mapRoot.userPanY = 0; mapCanvas.requestPaint() }
      }
    }

    // 1A. Rules Sub-Tab Clean 1-Line Hint Banner
    Rectangle {
      visible: mapRoot.toolMode === "wire"
      width: parent.width
      height: rulesHintRow.implicitHeight + Style.space(10)
      radius: mapRoot.corners.control
      color: Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.09)
      border.width: 1
      border.color: Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.30)

      Row {
        id: rulesHintRow
        x: Style.space(8); y: Style.space(5)
        width: parent.width - Style.space(16)
        spacing: Style.space(6)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "󰌹"
          color: mapRoot.accentColor
          font.family: mapRoot.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(22) - (wireCancelBtn.visible ? (wireCancelBtn.width + Style.space(6)) : 0)
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: mapRoot.wireFromId
            ? (mapRoot.entityName(mapRoot.wireFromKind, mapRoot.wireFromId) + " → " + mapRoot.t("mapRulesPickTarget"))
            : mapRoot.t("mapRulesHint")
          color: mapRoot.wireFromId ? mapRoot.fg : mapRoot.dim
          font.family: mapRoot.fontFamily
          font.pixelSize: Style.font.caption
        }
        Button {
          id: wireCancelBtn
          visible: mapRoot.wireFromId !== ""
          radius: mapRoot.corners.control
          text: mapRoot.t("cancel")
          bordered: true
          foreground: mapRoot.dim
          fontFamily: mapRoot.fontFamily
          fontSize: Math.max(9, Style.font.caption - 1)
          horizontalPadding: Style.space(6)
          verticalPadding: Style.space(1)
          onClicked: { mapRoot.wireFromId = ""; mapRoot.wireDragging = false; mapCanvas.requestPaint() }
        }
      }
    }

    // 1A-2. Multi-floor tabs (with lit counts) + Day / Dusk / Night ambient switch
    Item {
      width: parent.width
      height: Math.max(floorFlow.implicitHeight, ambientRow.implicitHeight)

      Flow {
        id: floorFlow
        anchors.left: parent.left
        width: parent.width - ambientRow.width - Style.space(8)
        spacing: Style.space(4)

        Repeater {
          model: mapRoot.fpFloors
          delegate: Button {
            required property var modelData
            readonly property int lit: mapRoot.floorLitCount(String(modelData.id))
            radius: mapRoot.corners.control
            text: mapRoot.floorLabel(modelData.name) + (lit > 0 ? (" · " + lit) : "")
            bordered: true
            selected: String(modelData.id) === mapRoot.activeFloorId
            accent: mapRoot.accentColor
            foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(2)
            onClicked: mapRoot.selectFloor(String(modelData.id))
          }
        }
        Button {
          visible: mapRoot.fpFloors.length < 12
          radius: mapRoot.corners.control
          text: mapRoot.t("fpAddFloor")
          bordered: true
          foreground: mapRoot.fg
          fontFamily: mapRoot.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7)
          verticalPadding: Style.space(2)
          onClicked: mapRoot.addFloor()
        }
        Button {
          visible: !mapRoot.floorRenameOpen
          radius: mapRoot.corners.control
          text: mapRoot.t("fpRename")
          bordered: true
          foreground: mapRoot.dim
          fontFamily: mapRoot.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7)
          verticalPadding: Style.space(2)
          onClicked: mapRoot.startFloorRename()
        }
        Row {
          visible: mapRoot.floorRenameOpen
          spacing: Style.space(4)
          KeyTextField {
            id: floorRenameField
            width: Style.space(120)
            radius: mapRoot.corners.control
            maximumLength: 32
            font: Qt.font({ family: mapRoot.fontFamily, pixelSize: Style.font.caption })
            placeholderText: mapRoot.t("fpFloorName")
            foreground: mapRoot.fg
            accent: mapRoot.accentColor
            onAccepted: mapRoot.saveFloorRename()
          }
          Button {
            radius: mapRoot.corners.control
            text: mapRoot.t("fpSave")
            bordered: true
            selected: true
            accent: mapRoot.accentColor
            foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(2)
            enabled: floorRenameField.text.trim().length > 0
            onClicked: mapRoot.saveFloorRename()
          }
          Button {
            radius: mapRoot.corners.control
            text: mapRoot.t("fpCancel")
            bordered: true
            foreground: mapRoot.dim
            fontFamily: mapRoot.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(2)
            onClicked: { mapRoot.floorRenameOpen = false; mapRoot.returnFocusRequested() }
          }
        }
        Button {
          visible: mapRoot.fpFloors.length > 1
          radius: mapRoot.corners.control
          text: mapRoot.t("fpDeleteFloor")
          bordered: true
          foreground: Commons.Color.urgent
          fontFamily: mapRoot.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7)
          verticalPadding: Style.space(2)
          onClicked: mapRoot.deleteFloor(mapRoot.activeFloorId)
        }
        Button {
          visible: mapRoot.undoFp !== null
          radius: mapRoot.corners.control
          iconText: "󰕌"
          text: mapRoot.t("fpUndo")
          bordered: true
          selected: true
          accent: mapRoot.accentColor
          foreground: mapRoot.fg
          fontFamily: mapRoot.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7)
          verticalPadding: Style.space(2)
          onClicked: mapRoot.undoFloorplan()
        }
      }

      Rectangle {
        id: ambientRow
        anchors.right: parent.right
        anchors.top: parent.top
        height: Style.space(24)
        width: ambRow.implicitWidth + Style.space(4)
        radius: mapRoot.corners.control
        color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.06)
        border.width: 1
        border.color: mapRoot.cardBorderColor
        Row {
          id: ambRow
          anchors.centerIn: parent
          spacing: Style.space(2)
          Repeater {
            model: [
              { id: "day", key: "fpDay", glyph: "󰖙" },
              { id: "dusk", key: "fpDusk", glyph: "󰖚" },
              { id: "night", key: "fpNight", glyph: "󰖔" }
            ]
            delegate: Rectangle {
              id: ambSeg
              required property var modelData
              readonly property bool active: mapRoot.ambient === modelData.id
              width: ambTxt.implicitWidth + Style.space(12)
              height: Style.space(20)
              radius: Math.max(2, mapRoot.corners.control - 1)
              color: active ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.24) : "transparent"
              Text {
                id: ambTxt
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: ambSeg.modelData.glyph + " " + mapRoot.t(ambSeg.modelData.key)
                color: ambSeg.active ? mapRoot.fg : mapRoot.dim
                font.family: mapRoot.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: ambSeg.active
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { mapRoot.ambient = ambSeg.modelData.id; mapCanvas.requestPaint() }
              }
            }
          }
        }
      }
    }

    // 1A-3. Floorplan Gallery popover (Map & Plan)
    Rectangle {
      visible: mapRoot.editMode && mapRoot.showGallery
      width: parent.width
      height: galCol.implicitHeight + Style.space(14)
      radius: mapRoot.corners.radius
      color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.05)
      border.width: 1
      border.color: mapRoot.cardBorderColor

      Column {
        id: galCol
        x: Style.space(8); y: Style.space(7)
        width: parent.width - Style.space(16)
        spacing: Style.space(6)

        Item {
          width: parent.width
          height: Math.max(galTitle.implicitHeight, galPlanBtn.height)
          Text {
            id: galTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: mapRoot.t("fpGalleryTitle")
            color: mapRoot.fg
            font.family: mapRoot.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Button {
            id: galPlanBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            radius: mapRoot.corners.control
            iconText: mapRoot.galleryIncludePlan ? "󰄲" : "󰄱"
            text: mapRoot.t("fpIncludePlan")
            bordered: true
            selected: mapRoot.galleryIncludePlan
            accent: mapRoot.accentColor
            foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(2)
            onClicked: mapRoot.galleryIncludePlan = !mapRoot.galleryIncludePlan
          }
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: mapRoot.t("fpGalleryHint")
          color: mapRoot.dim
          font.family: mapRoot.fontFamily
          font.pixelSize: Style.font.caption
        }
        Flow {
          width: parent.width
          spacing: Style.space(5)
          Repeater {
            model: mapRoot.templateOptions
            delegate: Button {
              required property var modelData
              readonly property bool isActive: String((mapRoot.workingFp && mapRoot.workingFp.template_id) || "") === modelData.value
              readonly property bool confirming: mapRoot.confirmTemplateId === modelData.value
              radius: mapRoot.corners.control
              text: confirming ? mapRoot.t("fpConfirmReplace") : ((isActive ? "✓ " : "") + modelData.label)
              bordered: true
              selected: isActive || confirming
              accent: confirming ? Commons.Color.urgent : mapRoot.accentColor
              foreground: confirming ? Commons.Color.urgent : mapRoot.fg
              fontFamily: mapRoot.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(2)
              onClicked: mapRoot.applyTemplate(modelData.value)
            }
          }
        }
      }
    }

    // 1A-4. Plan: "+ Fixture" presets popover
    Rectangle {
      visible: mapRoot.toolMode === "plan" && mapRoot.showPlanAdd
      width: parent.width
      height: planAddCol.implicitHeight + Style.space(12)
      radius: mapRoot.corners.radius
      color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.05)
      border.width: 1
      border.color: mapRoot.cardBorderColor

      Column {
        id: planAddCol
        x: Style.space(8); y: Style.space(6)
        width: parent.width - Style.space(16)
        spacing: Style.space(5)
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: mapRoot.t("fpAddFixtureHint")
          color: mapRoot.dim
          font.family: mapRoot.fontFamily
          font.pixelSize: Style.font.caption
        }
        Flow {
          width: parent.width
          spacing: Style.space(5)
          Repeater {
            model: mapRoot.plannedPresetList
            delegate: Button {
              required property var modelData
              radius: mapRoot.corners.control
              text: mapRoot.t(modelData.key) + " (" + modelData.lumens + " lm)"
              bordered: true
              foreground: mapRoot.fg
              fontFamily: mapRoot.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(2)
              onClicked: mapRoot.addPlanned(modelData.id)
            }
          }
        }
      }
    }

    // 1A-5. Plan: Lighting plan & shopping list
    Rectangle {
      id: planListCard
      visible: mapRoot.toolMode === "plan" && mapRoot.showPlanList
      width: parent.width
      height: planListCol.implicitHeight + Style.space(14)
      radius: mapRoot.corners.radius
      color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.05)
      border.width: 1
      border.color: mapRoot.cardBorderColor

      readonly property int totalLumens: {
        var n = 0
        for (var i = 0; i < mapRoot.fpPlanned.length; i++) n += Number(mapRoot.fpPlanned[i].lumens || 0)
        return n
      }
      readonly property real totalPrice: {
        var n = 0
        for (var i = 0; i < mapRoot.fpPlanned.length; i++) n += Number(mapRoot.fpPlanned[i].price || 0)
        return n
      }

      Column {
        id: planListCol
        x: Style.space(8); y: Style.space(7)
        width: parent.width - Style.space(16)
        spacing: Style.space(5)

        Item {
          width: parent.width
          height: planListTitle.implicitHeight
          Text {
            id: planListTitle
            anchors.left: parent.left
            width: parent.width - planListSum.implicitWidth - Style.space(8)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: mapRoot.t("fpShoppingTitle")
            color: mapRoot.fg
            font.family: mapRoot.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Text {
            id: planListSum
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: mapRoot.fpPlanned.length + " · " + planListCard.totalLumens + " lm · " + Math.round(planListCard.totalPrice)
            color: mapRoot.dim
            font.family: mapRoot.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          visible: mapRoot.fpPlanned.length === 0
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: mapRoot.t("fpNoPlanned")
          color: mapRoot.dim
          font.family: mapRoot.fontFamily
          font.pixelSize: Style.font.caption
        }
        Repeater {
          model: mapRoot.fpPlanned.length
          delegate: Item {
            id: planRow
            required property int index
            readonly property var pl: mapRoot.fpPlanned[index] || ({})
            width: planListCol.width
            height: Style.space(22)
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - planRowCtrls.width - Style.space(8)
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: String(planRow.pl.name || "") + " · " + Number(planRow.pl.lumens || 0) + " lm · " + Number(planRow.pl.kelvin || 0) + " K"
                + (mapRoot.fpFloors.length > 1 ? (" · " + mapRoot.floorLabel(mapRoot.floorNameOf(mapRoot.floorOf(planRow.pl)))) : "")
              color: mapRoot.fg
              font.family: mapRoot.fontFamily
              font.pixelSize: Style.font.caption
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  mapRoot.selectFloor(mapRoot.floorOf(planRow.pl))
                  mapRoot.selectItem("planned", String(planRow.pl.id || ""))
                }
              }
            }
            Row {
              id: planRowCtrls
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Number(planRow.pl.price || 0) > 0
                textFormat: Text.PlainText
                text: String(Math.round(Number(planRow.pl.price || 0)))
                color: mapRoot.dim
                font.family: mapRoot.fontFamily
                font.pixelSize: Style.font.caption
              }
              Button {
                radius: mapRoot.corners.control
                text: planRow.pl.on !== false ? mapRoot.t("fpOn") : mapRoot.t("fpOff")
                bordered: true
                selected: planRow.pl.on !== false
                accent: mapRoot.accentColor
                foreground: mapRoot.fg
                fontFamily: mapRoot.fontFamily
                fontSize: Math.max(9, Style.font.caption - 1)
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(1)
                onClicked: mapRoot.editPlanned(String(planRow.pl.id || ""), function(p) { p.on = !(p.on !== false) })
              }
              Button {
                radius: mapRoot.corners.control
                text: "×"
                bordered: true
                foreground: Commons.Color.urgent
                fontFamily: mapRoot.fontFamily
                fontSize: Math.max(9, Style.font.caption - 1)
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(1)
                onClicked: mapRoot.deletePlanned(String(planRow.pl.id || ""))
              }
            }
          }
        }
      }
    }

    // 1B. "+ Add ▾" Popover Strip (+ Room, + Zone, and 8 Architectural Stamps)
    Rectangle {
      visible: mapRoot.toolMode === "select" && mapRoot.showAddMenu
      width: parent.width
      height: addPopFlow.implicitHeight + Style.space(12)
      radius: mapRoot.corners.radius
      color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.05)
      border.width: 1
      border.color: mapRoot.cardBorderColor

      Flow {
        id: addPopFlow
        x: Style.space(8); y: Style.space(6)
        width: parent.width - Style.space(16)
        spacing: Style.space(5)

        Button {
          radius: mapRoot.corners.control
          text: mapRoot.t("mapAddRoom")
          bordered: true
          accent: mapRoot.accentColor
          foreground: mapRoot.fg
          fontFamily: mapRoot.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7)
          verticalPadding: Style.space(2)
          onClicked: mapRoot.addBox("room")
        }
        Button {
          radius: mapRoot.corners.control
          text: mapRoot.t("mapAddZone")
          bordered: true
          accent: mapRoot.accentColor
          foreground: mapRoot.fg
          fontFamily: mapRoot.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7)
          verticalPadding: Style.space(2)
          onClicked: mapRoot.addBox("zone")
        }
        Button {
          radius: mapRoot.corners.control
          text: mapRoot.t("fpAddLShape")
          bordered: true
          accent: mapRoot.accentColor
          foreground: mapRoot.fg
          fontFamily: mapRoot.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7)
          verticalPadding: Style.space(2)
          onClicked: mapRoot.addBox("room", "l_shape")
        }
        Button {
          radius: mapRoot.corners.control
          text: mapRoot.t("fpAddBay")
          bordered: true
          accent: mapRoot.accentColor
          foreground: mapRoot.fg
          fontFamily: mapRoot.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7)
          verticalPadding: Style.space(2)
          onClicked: mapRoot.addBox("room", "bay_window")
        }
        Rectangle {
          width: 1
          height: Style.space(20)
          color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.16)
        }
        Repeater {
          model: mapRoot.stampKindList
          delegate: Button {
            required property var modelData
            radius: mapRoot.corners.control
            text: "+ " + mapRoot.t(modelData.key)
            bordered: true
            foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(2)
            onClicked: mapRoot.addStamp(modelData.id)
          }
        }
      }
    }

    // 1C. "View ▾" Popover (Glows, Furniture, Wires, Background, optional Entertainment, Auto-sync, Fit)
    Rectangle {
      visible: mapRoot.toolMode === "select" && mapRoot.showViewMenu
      width: parent.width
      height: viewPopCol.implicitHeight + Style.space(12)
      radius: mapRoot.corners.radius
      color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.05)
      border.width: 1
      border.color: mapRoot.cardBorderColor

      Column {
        id: viewPopCol
        x: Style.space(8); y: Style.space(6)
        width: parent.width - Style.space(16)
        spacing: Style.space(6)

        Flow {
          width: parent.width
          spacing: Style.space(5)

          Button {
            radius: mapRoot.corners.control; iconText: "󰖙"; text: mapRoot.t("mapGlows"); bordered: true
            selected: mapRoot.showGlows; accent: mapRoot.accentColor; foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: {
              var fp = mapRoot.cloneFp(mapRoot.workingFp)
              fp.show_glows = !mapRoot.showGlows
              mapRoot.commitFp(fp, false)
            }
          }
          Button {
            radius: mapRoot.corners.control; iconText: "󰒹"; text: mapRoot.t("mapFurniture"); bordered: true
            selected: mapRoot.showFurniture; accent: mapRoot.accentColor; foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: {
              var fp = mapRoot.cloneFp(mapRoot.workingFp)
              fp.show_furniture = !mapRoot.showFurniture
              mapRoot.commitFp(fp, false)
            }
          }
          Button {
            radius: mapRoot.corners.control; iconText: "󱐋"; text: mapRoot.t("mapWires"); bordered: true
            selected: mapRoot.showWires; accent: mapRoot.accentColor; foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: {
              var fp = mapRoot.cloneFp(mapRoot.workingFp)
              fp.show_wires = !mapRoot.showWires
              mapRoot.commitFp(fp, false)
            }
          }
          Button {
            radius: mapRoot.corners.control; iconText: "󰋩"; text: mapRoot.t("mapBackground"); bordered: true
            selected: mapRoot.showBgBar || mapRoot.bgPath !== ""
            accent: mapRoot.accentColor; foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: mapRoot.showBgBar = !mapRoot.showBgBar
          }
          CompactDropdown {
            id: entPicker
            visible: (mapRoot.entertainmentAreas || []).length > 0
            width: Style.space(124)
            popupRadius: mapRoot.corners.radius
            controlRadius: mapRoot.corners.control
            fontSize: Style.font.caption
            rowHeight: Style.space(24)
            popupRowHeight: Style.space(26)
            showLabel: false
            fontFamily: mapRoot.fontFamily
            accent: mapRoot.accentColor
            options: mapRoot.entertainmentOptions
            value: mapRoot.validOption(mapRoot.entertainmentOptions, String((mapRoot.workingFp && mapRoot.workingFp.entertainment_id) || ""), 0)
            onChanged: function(v) {
              var fp = mapRoot.cloneFp(mapRoot.workingFp)
              fp.entertainment_id = v ? v : null
              mapRoot.commitFp(fp, false)
              entPicker.value = Qt.binding(function() {
                return mapRoot.validOption(mapRoot.entertainmentOptions, String((mapRoot.workingFp && mapRoot.workingFp.entertainment_id) || ""), 0)
              })
            }
          }
          Button {
            radius: mapRoot.corners.control; text: mapRoot.t("mapAutoSync"); bordered: true
            selected: mapRoot.autoSync; accent: mapRoot.accentColor; foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: {
              var fp = mapRoot.cloneFp(mapRoot.workingFp)
              fp.auto_sync = !mapRoot.autoSync
              fp.auto_sync_rooms = fp.auto_sync
              mapRoot.commitFp(fp, false)
            }
          }
          Button {
            radius: mapRoot.corners.control; iconText: "󰊓"; text: mapRoot.t("mapFit"); bordered: true
            foreground: mapRoot.fg; fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: { mapRoot.userZoom = 1.0; mapRoot.userPanX = 0; mapRoot.userPanY = 0; mapCanvas.requestPaint() }
          }
        }

        // Background Image Editor sub-panel inside View popover
        Column {
          visible: mapRoot.showBgBar
          width: parent.width
          spacing: Style.space(6)

          Rectangle { width: parent.width; height: 1; color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.12) }

          Row {
            width: parent.width
            spacing: Style.space(5)
            Button {
              id: bgBrowseBtn
              radius: mapRoot.corners.control
              iconText: "󰉋"
              text: mapRoot.t("mapBgBrowse")
              bordered: true
              foreground: mapRoot.fg
              fontFamily: mapRoot.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(2)
              onClicked: bgFileDialog.open()
            }
            KeyTextField {
              id: bgPathField
              width: Math.max(Style.space(80), parent.width - bgBrowseBtn.width - bgApplyBtn.width - Style.space(10))
              radius: mapRoot.corners.control
              maximumLength: 512
              font: Qt.font({ family: mapRoot.fontFamily, pixelSize: Style.font.caption })
              placeholderText: mapRoot.t("mapBgPathPlaceholder")
              foreground: mapRoot.fg
              accent: mapRoot.accentColor
              onAccepted: {
                var p = text.trim()
                if (p) mapRoot.sendCommand({ cmd: "floorplan_bg_set", path: p })
              }
            }
            Button {
              id: bgApplyBtn
              radius: mapRoot.corners.control
              text: mapRoot.t("mapBgApply")
              bordered: true
              foreground: mapRoot.fg
              fontFamily: mapRoot.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(2)
              enabled: bgPathField.text.trim().length > 0
              onClicked: mapRoot.sendCommand({ cmd: "floorplan_bg_set", path: bgPathField.text.trim() })
            }
          }

          Item {
            width: parent.width
            height: Math.max(bgOpLbl.implicitHeight, bgOpSlider.implicitHeight)
            Text {
              id: bgOpLbl
              anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
              width: Style.space(56)
              textFormat: Text.PlainText
              text: mapRoot.t("mapBgOpacity")
              color: mapRoot.dim
              font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
            }
            PanelSlider {
              id: bgOpSlider
              anchors.left: bgOpLbl.right; anchors.leftMargin: Style.space(6)
              anchors.right: bgOpPct.left; anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              bar: mapRoot.bar
              minimum: 5; maximum: 100; step: 5
              fillColor: mapRoot.accentColor
              value: Math.round(mapRoot.bgOpacity * 100)
              onMoved: function(v) {
                var op = Math.max(0.05, Math.min(1.0, Math.round(v) / 100.0))
                mapRoot.sendCommand({ cmd: "floorplan_bg_update", opacity: op, fit: mapRoot.bgFit })
              }
            }
            Text {
              id: bgOpPct
              anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34); horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: Math.round(bgOpSlider.liveValue) + "%"
              color: mapRoot.fg
              font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
            }
          }

          Row {
            spacing: Style.space(6)
            Button {
              radius: mapRoot.corners.control; text: mapRoot.t("mapBgContain"); bordered: true
              selected: mapRoot.bgFit === "contain"; accent: mapRoot.accentColor
              foreground: mapRoot.fg; fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
              horizontalPadding: Style.space(8); verticalPadding: Style.space(2)
              onClicked: mapRoot.sendCommand({ cmd: "floorplan_bg_update", opacity: mapRoot.bgOpacity, fit: "contain" })
            }
            Button {
              radius: mapRoot.corners.control; text: mapRoot.t("mapBgCover"); bordered: true
              selected: mapRoot.bgFit === "cover"; accent: mapRoot.accentColor
              foreground: mapRoot.fg; fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
              horizontalPadding: Style.space(8); verticalPadding: Style.space(2)
              onClicked: mapRoot.sendCommand({ cmd: "floorplan_bg_update", opacity: mapRoot.bgOpacity, fit: "cover" })
            }
            Button {
              radius: mapRoot.corners.control; text: mapRoot.t("mapBgClear"); bordered: true
              enabled: mapRoot.bgPath !== ""
              foreground: Commons.Color.urgent; fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
              horizontalPadding: Style.space(8); verticalPadding: Style.space(2)
              onClicked: { bgPathField.clear(); mapRoot.sendCommand({ cmd: "floorplan_bg_clear" }) }
            }
          }
        }
      }
    }

    // =======================================================================
    // 2. MAIN WORKSPACE: LAMP SIDEBAR (WITH ⋯ SUBMENUS) + LARGER 2D CANVAS
    // =======================================================================
    readonly property real workspaceHeight: mapRoot.panelHeight > 0
      ? Math.max(Style.space(300), Math.min(Style.space(580), Style.space(mapRoot.panelHeight) - Style.space(210)))
      : Style.space(360)

    Row {
      id: workspaceRow
      width: parent.width
      height: mainCol.workspaceHeight
      spacing: Style.space(6)

      // Left Collapsible Lamp Sidebar
      Rectangle {
        id: lampSidebar
        visible: mapRoot.showSidebar
        width: Math.min(Style.space(164), Math.max(Style.space(136), Math.round(parent.width * 0.30)))
        height: parent.height
        radius: mapRoot.corners.radius
        color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.04)
        border.width: 1
        border.color: mapRoot.cardBorderColor
        clip: true

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(6)
          spacing: Style.space(5)

          KeyTextField {
            id: lampSearchField
            width: parent.width
            radius: mapRoot.corners.control
            maximumLength: 40
            font: Qt.font({ family: mapRoot.fontFamily, pixelSize: Style.font.caption })
            placeholderText: mapRoot.t("mapSearchLamps")
            foreground: mapRoot.fg
            accent: mapRoot.accentColor
          }

          Flickable {
            id: sidebarList
            width: parent.width
            height: parent.height - lampSearchField.height - Style.space(5)
            contentWidth: width
            contentHeight: sideCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: sideCol
              width: sidebarList.width
              spacing: Style.space(4)

              // ---- BRIDGE PRO MOTIONAWARE READY HINT (hidden unless Pro & 0 areas & not dismissed) ----
              Rectangle {
                visible: mapRoot.showMotionAwareHint
                width: sideCol.width
                height: mapMaHintCol.implicitHeight + Style.space(12)
                radius: mapRoot.corners.control
                color: Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.11)
                border.width: 1
                border.color: Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.45)

                Column {
                  id: mapMaHintCol
                  x: Style.space(6)
                  y: Style.space(6)
                  width: parent.width - Style.space(12)
                  spacing: Style.space(4)

                  Item {
                    width: parent.width
                    height: Math.max(mapMaHintTitle.implicitHeight, Style.space(16))
                    Text {
                      id: mapMaHintTitle
                      anchors.left: parent.left
                      anchors.right: mapMaHintClose.left
                      anchors.rightMargin: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      wrapMode: Text.WordWrap
                      textFormat: Text.PlainText
                      text: "● " + mapRoot.t("motionHintTitle")
                      color: "#10B981"
                      font.family: mapRoot.fontFamily
                      font.pixelSize: Math.max(9, Style.font.caption - 1)
                      font.bold: true
                    }
                    Rectangle {
                      id: mapMaHintClose
                      anchors.right: parent.right
                      anchors.top: parent.top
                      width: Style.space(16)
                      height: Style.space(16)
                      radius: mapRoot.corners.small
                      color: mapMaCloseM.containsMouse ? Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.16) : "transparent"
                      Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "×"
                        color: mapMaCloseM.containsMouse ? mapRoot.fg : mapRoot.dim
                        font.family: mapRoot.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      MouseArea {
                        id: mapMaCloseM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mapRoot.dismissMotionAwareHint()
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: (mapRoot.motionAwareEligibleRooms || []).length > 0
                      ? mapRoot.t("motionHintEligible", [mapRoot.motionAwareEligibleRooms.join(", ")])
                      : mapRoot.t("motionHintNeed3Lights")
                    color: mapRoot.fg
                    font.family: mapRoot.fontFamily
                    font.pixelSize: Math.max(9, Style.font.caption - 2)
                  }

                  Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: "1. " + mapRoot.t("motionHintStep1") + "\n2. " + mapRoot.t("motionHintStep2") + "\n3. " + mapRoot.t("motionHintStep3")
                    color: mapRoot.dim
                    font.family: mapRoot.fontFamily
                    font.pixelSize: Math.max(9, Style.font.caption - 2)
                  }
                }
              }

              // ---- PLACED LAMPS ----
              Text {
                visible: mapRoot.placedLampList.length > 0
                textFormat: Text.PlainText
                text: mapRoot.t("mapPlaced").toUpperCase() + " (" + mapRoot.placedLampList.length + ")"
                color: mapRoot.dim
                font.family: mapRoot.fontFamily
                font.pixelSize: Math.max(9, Style.font.caption - 1)
                font.bold: true
              }

              Repeater {
                model: mapRoot.placedLampList.length
                delegate: Column {
                  id: plWrap
                  required property int index
                  readonly property var entry: mapRoot.placedLampList[index] || ({ light: ({}), pos: ({ icon: "bulb" }) })
                  readonly property var lt: entry.light || ({})
                  readonly property string lampIcon: mapRoot.lampIconFor(lt.id)
                  readonly property bool isSel: mapRoot.selectedKind === "lamp" && mapRoot.selectedId === lt.id
                  readonly property bool menuOpen: mapRoot.openMenuLampId === lt.id
                  readonly property string subLine: {
                    var parts = []
                    if (mapRoot.providerTag(lt.provider)) parts.push(mapRoot.providerTag(lt.provider))
                    if (lt.room_name) parts.push(lt.room_name)
                    if (mapRoot.floorOf(entry.pos) !== mapRoot.activeFloorId) parts.push(mapRoot.floorLabel(mapRoot.floorNameOf(mapRoot.floorOf(entry.pos))))
                    parts.push(lt.on ? (Math.round(lt.bri) + "%") : mapRoot.t("actionOff"))
                    return parts.join(" · ")
                  }
                  width: sideCol.width
                  spacing: Style.space(3)

                  // Lamp Card Row
                  Rectangle {
                    width: parent.width
                    height: Style.space(34)
                    radius: mapRoot.corners.small
                    color: plWrap.isSel || plWrap.menuOpen
                      ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.20)
                      : (plMouse.containsMouse ? Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.08) : Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.03))
                    border.width: 1
                    border.color: (plWrap.isSel || plWrap.menuOpen) ? mapRoot.accentColor : Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.10)

                    MouseArea {
                      id: plMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: mapRoot.selectItem("lamp", plWrap.lt.id)
                    }

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(5)
                      anchors.rightMargin: Style.space(4)
                      spacing: Style.space(6)

                      // Colored circular lamp icon badge (1:1 with map node!)
                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(22)
                        height: Style.space(22)
                        radius: width * 0.5
                        color: plWrap.lt.on ? (plWrap.lt.color || "#ffd27a") : Qt.rgba(22 / 255, 26 / 255, 36 / 255, 0.92)
                        border.width: 1.2
                        border.color: plWrap.lt.on ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(1, 1, 1, 0.28)
                        LampGlyph {
                          anchors.centerIn: parent
                          width: Style.space(13)
                          height: Style.space(13)
                          iconName: plWrap.lampIcon
                          version: mapRoot.iconVersion
                          tint: mapRoot.contrastTintForLight(plWrap.lt)
                        }
                      }

                      // Name + room/brightness
                      Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Style.space(54)
                        spacing: 0
                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          textFormat: Text.PlainText
                          text: String(plWrap.lt.name || "")
                          color: plWrap.lt.on ? mapRoot.fg : mapRoot.dim
                          font.family: mapRoot.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: plWrap.lt.on || plWrap.isSel
                        }
                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          textFormat: Text.PlainText
                          text: plWrap.subLine
                          color: mapRoot.dim
                          font.family: mapRoot.fontFamily
                          font.pixelSize: Math.max(9, Style.font.caption - 2)
                        }
                      }

                      // "⋯" submenu toggle button
                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(20)
                        height: Style.space(20)
                        radius: mapRoot.corners.small
                        color: plWrap.menuOpen || plDotsMouse.containsMouse
                          ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.25)
                          : "transparent"
                        Text {
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          text: "⋯"
                          color: plWrap.menuOpen || plDotsMouse.containsMouse ? mapRoot.fg : mapRoot.dim
                          font.family: mapRoot.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                        MouseArea {
                          id: plDotsMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            mapRoot.openMenuSensorId = ""
                            mapRoot.openMenuLampId = (mapRoot.openMenuLampId === plWrap.lt.id) ? "" : plWrap.lt.id
                          }
                        }
                      }
                    }
                  }

                  // Indented inline submenu for placed lamp
                  Rectangle {
                    visible: plWrap.menuOpen
                    x: Style.space(10)
                    width: parent.width - Style.space(10)
                    height: plSubCol.implicitHeight + Style.space(6)
                    radius: mapRoot.corners.small
                    color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.30)

                    Column {
                      id: plSubCol
                      x: Style.space(3); y: Style.space(3)
                      width: parent.width - Style.space(6)
                      spacing: Style.space(1)

                      // 1. Turn off / Turn on
                      Rectangle {
                        width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                        color: smToggleM.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.22) : "transparent"
                        Text {
                          anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                          width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                          text: plWrap.lt.on ? mapRoot.t("mapTurnOff") : mapRoot.t("mapTurnOn")
                          color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                        }
                        MouseArea {
                          id: smToggleM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            mapRoot.sendCommand({ cmd: "light", id: plWrap.lt.id, on: !plWrap.lt.on })
                            mapRoot.openMenuLampId = ""
                          }
                        }
                      }
                      // 2. Brightness…
                      Rectangle {
                        width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                        color: smBriM.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.22) : "transparent"
                        Text {
                          anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                          width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                          text: mapRoot.t("mapMenuBrightness")
                          color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                        }
                        MouseArea {
                          id: smBriM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                          onClicked: mapRoot.openBrightnessDialog(plWrap.lt.id)
                        }
                      }
                      // 3. Rename…
                      Rectangle {
                        width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                        color: smRenM.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.22) : "transparent"
                        Text {
                          anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                          width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                          text: mapRoot.t("mapMenuRename")
                          color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                        }
                        MouseArea {
                          id: smRenM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                          onClicked: mapRoot.openRenameDialog(plWrap.lt.id)
                        }
                      }
                      // 4. Lamp icon…
                      Rectangle {
                        width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                        color: smIcoM.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.22) : "transparent"
                        Text {
                          anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                          width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                          text: mapRoot.t("mapMenuIcon")
                          color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                        }
                        MouseArea {
                          id: smIcoM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                          onClicked: mapRoot.openIconDialog(plWrap.lt.id)
                        }
                      }
                      // 5. Wire from here
                      Rectangle {
                        width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                        color: smWireM.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.22) : "transparent"
                        Text {
                          anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                          width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                          text: mapRoot.t("mapMenuWireFromHere")
                          color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                        }
                        MouseArea {
                          id: smWireM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            mapRoot.openMenuLampId = ""
                            mapRoot.showAddMenu = false
                            mapRoot.showViewMenu = false
                            mapRoot.showBgBar = false
                            mapRoot.selectedKind = ""
                            mapRoot.selectedId = ""
                            mapRoot.toolMode = "wire"
                            mapRoot.wireFromKind = "light"
                            mapRoot.wireFromId = plWrap.lt.id
                            mapRoot.wireDragging = false
                            mapCanvas.requestPaint()
                          }
                        }
                      }
                      // 6. Unplace
                      Rectangle {
                        width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                        color: smUnpM.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.22) : "transparent"
                        Text {
                          anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                          width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                          text: mapRoot.t("mapUnplace")
                          color: smUnpM.containsMouse ? Commons.Color.urgent : mapRoot.dim
                          font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                        }
                        MouseArea {
                          id: smUnpM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                          onClicked: mapRoot.unplaceLamp(plWrap.lt.id)
                        }
                      }
                    }
                  }
                }
              }

              // ---- UNPLACED LAMPS ----
              Text {
                visible: mapRoot.unplacedLampList.length > 0
                textFormat: Text.PlainText
                text: mapRoot.t("mapUnplaced").toUpperCase() + " (" + mapRoot.unplacedLampList.length + ")"
                color: mapRoot.dim
                font.family: mapRoot.fontFamily
                font.pixelSize: Math.max(9, Style.font.caption - 1)
                font.bold: true
              }

              Repeater {
                model: mapRoot.unplacedLampList.length
                delegate: Column {
                  id: unpWrap
                  required property int index
                  readonly property var lt: mapRoot.unplacedLampList[index] || ({})
                  readonly property bool menuOpen: mapRoot.openMenuLampId === lt.id
                  readonly property string subLine: {
                    var parts = []
                    if (mapRoot.providerTag(lt.provider)) parts.push(mapRoot.providerTag(lt.provider))
                    if (lt.room_name) parts.push(lt.room_name)
                    parts.push(lt.on ? (Math.round(lt.bri) + "%") : mapRoot.t("actionOff"))
                    return parts.join(" · ")
                  }
                  width: sideCol.width
                  spacing: Style.space(3)

                  Rectangle {
                    width: parent.width
                    height: Style.space(32)
                    radius: mapRoot.corners.small
                    color: unpWrap.menuOpen
                      ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.18)
                      : (unpMouse.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.14) : Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.03))
                    border.width: 1
                    border.color: unpWrap.menuOpen ? mapRoot.accentColor : Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.10)

                    MouseArea {
                      id: unpMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: mapRoot.placeLamp(unpWrap.lt.id)
                    }

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(6)
                      anchors.rightMargin: Style.space(4)
                      spacing: Style.space(6)

                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(9); height: Style.space(9); radius: width * 0.5
                        color: unpWrap.lt.on ? (unpWrap.lt.color || "#ffd27a") : Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.26)
                      }

                      Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Style.space(42)
                        spacing: 0
                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          textFormat: Text.PlainText
                          text: String(unpWrap.lt.name || "")
                          color: mapRoot.fg
                          font.family: mapRoot.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          textFormat: Text.PlainText
                          text: unpWrap.subLine
                          color: mapRoot.dim
                          font.family: mapRoot.fontFamily
                          font.pixelSize: Math.max(9, Style.font.caption - 2)
                        }
                      }

                      // "⋯" submenu toggle button
                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(20); height: Style.space(20)
                        radius: mapRoot.corners.small
                        color: unpWrap.menuOpen || unpDotsMouse.containsMouse
                          ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.25)
                          : "transparent"
                        Text {
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          text: "⋯"
                          color: unpWrap.menuOpen || unpDotsMouse.containsMouse ? mapRoot.fg : mapRoot.dim
                          font.family: mapRoot.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                        MouseArea {
                          id: unpDotsMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            mapRoot.openMenuSensorId = ""
                            mapRoot.openMenuLampId = (mapRoot.openMenuLampId === unpWrap.lt.id) ? "" : unpWrap.lt.id
                          }
                        }
                      }
                    }
                  }

                  // Indented inline submenu for unplaced lamp (Place, Turn on/off, Brightness…, Rename…)
                  Rectangle {
                    visible: unpWrap.menuOpen
                    x: Style.space(10)
                    width: parent.width - Style.space(10)
                    height: unpSubCol.implicitHeight + Style.space(6)
                    radius: mapRoot.corners.small
                    color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.30)

                    Column {
                      id: unpSubCol
                      x: Style.space(3); y: Style.space(3)
                      width: parent.width - Style.space(6)
                      spacing: Style.space(1)

                      Rectangle {
                        width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                        color: uPlaceM.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.22) : "transparent"
                        Text {
                          anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                          width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                          text: mapRoot.t("mapMenuPlace")
                          color: mapRoot.accentColor; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                        }
                        MouseArea {
                          id: uPlaceM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                          onClicked: mapRoot.placeLamp(unpWrap.lt.id)
                        }
                      }
                      Rectangle {
                        width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                        color: uTogM.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.22) : "transparent"
                        Text {
                          anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                          width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                          text: unpWrap.lt.on ? mapRoot.t("mapTurnOff") : mapRoot.t("mapTurnOn")
                          color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                        }
                        MouseArea {
                          id: uTogM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            mapRoot.sendCommand({ cmd: "light", id: unpWrap.lt.id, on: !unpWrap.lt.on })
                            mapRoot.openMenuLampId = ""
                          }
                        }
                      }
                      Rectangle {
                        width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                        color: uBriM.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.22) : "transparent"
                        Text {
                          anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                          width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                          text: mapRoot.t("mapMenuBrightness")
                          color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                        }
                        MouseArea {
                          id: uBriM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                          onClicked: mapRoot.openBrightnessDialog(unpWrap.lt.id)
                        }
                      }
                      Rectangle {
                        width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                        color: uRenM.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.22) : "transparent"
                        Text {
                          anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                          width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                          text: mapRoot.t("mapMenuRename")
                          color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                        }
                        MouseArea {
                          id: uRenM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                          onClicked: mapRoot.openRenameDialog(unpWrap.lt.id)
                        }
                      }
                    }
                  }
                }
              }

              // ---- PHYSICAL SENSORS & SWITCHES (only shown when bridge has sensors) ----
              Column {
                visible: (mapRoot.sensors || []).length > 0
                width: sideCol.width
                spacing: Style.space(4)

                Rectangle {
                  width: parent.width; height: 1
                  color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.12)
                }

                Text {
                  textFormat: Text.PlainText
                  text: mapRoot.t("mapSensors").toUpperCase() + " (" + (mapRoot.placedSensorList.length + mapRoot.unplacedSensorList.length) + ")"
                  color: mapRoot.dim
                  font.family: mapRoot.fontFamily
                  font.pixelSize: Math.max(9, Style.font.caption - 1)
                  font.bold: true
                }

                // Placed sensors
                Repeater {
                  model: mapRoot.placedSensorList.length
                  delegate: Column {
                    id: psWrap
                    required property int index
                    readonly property var entry: mapRoot.placedSensorList[index] || ({ sensor: ({}), pos: ({ x: 0, y: 0 }) })
                    readonly property var sn: entry.sensor || ({})
                    readonly property bool isSel: mapRoot.selectedKind === "sensor" && mapRoot.selectedId === sn.id
                    readonly property bool menuOpen: mapRoot.openMenuSensorId === sn.id
                    readonly property bool isActive: (sn.kind === "motion" && sn.motion === true && sn.enabled !== false)
                      || (sn.kind === "contact" && sn.open === true && sn.enabled !== false)
                    readonly property color badgeCol: sn.kind === "motion"
                      ? (isActive ? "#10B981" : Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.24))
                      : (sn.kind === "contact"
                        ? (isActive ? "#F59E0B" : Qt.rgba(245 / 255, 158 / 255, 11 / 255, 0.22))
                        : Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.24))
                    width: sideCol.width
                    spacing: Style.space(3)

                    Rectangle {
                      width: parent.width
                      height: Style.space(34)
                      radius: mapRoot.corners.small
                      color: psWrap.isSel || psWrap.menuOpen
                        ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.20)
                        : (psMouse.containsMouse ? Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.08) : Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.03))
                      border.width: 1
                      border.color: (psWrap.isSel || psWrap.menuOpen)
                        ? mapRoot.accentColor
                        : (psWrap.isActive ? psWrap.badgeCol : Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.10))

                      MouseArea {
                        id: psMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mapRoot.selectItem("sensor", psWrap.sn.id)
                      }

                      Row {
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(5)
                        anchors.rightMargin: Style.space(4)
                        spacing: Style.space(6)

                        // Rounded-square sensor icon badge
                        Rectangle {
                          anchors.verticalCenter: parent.verticalCenter
                          width: Style.space(22); height: Style.space(22)
                          radius: Math.min(mapRoot.corners.small, 5)
                          color: psWrap.badgeCol
                          opacity: psWrap.sn.enabled === false ? 0.45 : 1.0
                          border.width: 1
                          border.color: psWrap.isActive ? "#ffffff" : Qt.rgba(1, 1, 1, 0.26)
                          SensorGlyph {
                            anchors.centerIn: parent
                            width: Style.space(13); height: Style.space(13)
                            sensorKind: String(psWrap.sn.kind || "motion")
                            tint: psWrap.isActive ? "#0f172a" : "#f8fafc"
                          }
                        }

                        Column {
                          anchors.verticalCenter: parent.verticalCenter
                          width: parent.width - Style.space(54)
                          spacing: 0
                          Text {
                            width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                            text: String(psWrap.sn.name || "")
                            color: psWrap.sn.enabled === false ? mapRoot.dim : mapRoot.fg
                            font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                            font.bold: psWrap.isActive || psWrap.isSel
                          }
                          Text {
                            width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                            text: mapRoot.sensorStatusText(psWrap.sn)
                            color: psWrap.isActive ? (psWrap.sn.kind === "contact" ? "#F59E0B" : "#10B981") : mapRoot.dim
                            font.family: mapRoot.fontFamily; font.pixelSize: Math.max(9, Style.font.caption - 2)
                          }
                        }

                        // "⋯" submenu toggle button
                        Rectangle {
                          anchors.verticalCenter: parent.verticalCenter
                          width: Style.space(20); height: Style.space(20)
                          radius: mapRoot.corners.small
                          color: psWrap.menuOpen || psDotsM.containsMouse
                            ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.25)
                            : "transparent"
                          Text {
                            anchors.centerIn: parent; textFormat: Text.PlainText; text: "⋯"
                            color: psWrap.menuOpen || psDotsM.containsMouse ? mapRoot.fg : mapRoot.dim
                            font.family: mapRoot.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true
                          }
                          MouseArea {
                            id: psDotsM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              mapRoot.openMenuLampId = ""
                              mapRoot.openMenuSensorId = (mapRoot.openMenuSensorId === psWrap.sn.id) ? "" : psWrap.sn.id
                            }
                          }
                        }
                      }
                    }

                    // Indented inline submenu for placed sensor
                    Rectangle {
                      visible: psWrap.menuOpen
                      x: Style.space(10)
                      width: parent.width - Style.space(10)
                      height: psSubCol.implicitHeight + Style.space(6)
                      radius: mapRoot.corners.small
                      color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.06)
                      border.width: 1
                      border.color: Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.30)

                      Column {
                        id: psSubCol
                        x: Style.space(3); y: Style.space(3)
                        width: parent.width - Style.space(6)
                        spacing: Style.space(1)

                        // Enable / Disable (for motion & contact)
                        Rectangle {
                          visible: psWrap.sn.kind === "motion" || psWrap.sn.kind === "contact"
                          width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                          color: psEnM.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.22) : "transparent"
                          Text {
                            anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                            width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                            text: psWrap.sn.enabled === false ? mapRoot.t("sensorEnable") : mapRoot.t("sensorDisable")
                            color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                          }
                          MouseArea {
                            id: psEnM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              mapRoot.sendCommand({ cmd: "sensor_toggle", kind: psWrap.sn.kind, id: psWrap.sn.id, enabled: psWrap.sn.enabled === false })
                              mapRoot.openMenuSensorId = ""
                            }
                          }
                        }
                        // Wire from here
                        Rectangle {
                          width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                          color: psWireM.containsMouse ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.22) : "transparent"
                          Text {
                            anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                            width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                            text: mapRoot.t("mapMenuWireFromHere")
                            color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                          }
                          MouseArea {
                            id: psWireM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              mapRoot.openMenuSensorId = ""
                              mapRoot.showAddMenu = false
                              mapRoot.showViewMenu = false
                              mapRoot.showBgBar = false
                              mapRoot.selectedKind = ""
                              mapRoot.selectedId = ""
                              mapRoot.toolMode = "wire"
                              mapRoot.wireFromKind = String(psWrap.sn.kind || "motion")
                              mapRoot.wireFromId = psWrap.sn.id
                              mapRoot.wireDragging = false
                              mapCanvas.requestPaint()
                            }
                          }
                        }
                        // Unplace
                        Rectangle {
                          width: parent.width; height: Style.space(22); radius: Math.max(2, mapRoot.corners.small - 1)
                          color: psUnpM.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.22) : "transparent"
                          Text {
                            anchors.verticalCenter: parent.verticalCenter; x: Style.space(6)
                            width: parent.width - Style.space(12); elide: Text.ElideRight; textFormat: Text.PlainText
                            text: mapRoot.t("mapUnplace")
                            color: psUnpM.containsMouse ? Commons.Color.urgent : mapRoot.dim
                            font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                          }
                          MouseArea {
                            id: psUnpM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: mapRoot.unplaceSensor(psWrap.sn.id)
                          }
                        }
                      }
                    }
                  }
                }

                // Unplaced sensors (with Place button)
                Repeater {
                  model: mapRoot.unplacedSensorList.length
                  delegate: Rectangle {
                    id: usCard
                    required property int index
                    readonly property var sn: mapRoot.unplacedSensorList[index] || ({})
                    width: sideCol.width
                    height: Style.space(32)
                    radius: mapRoot.corners.small
                    color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.03)
                    border.width: 1
                    border.color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.10)

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(5)
                      anchors.rightMargin: Style.space(4)
                      spacing: Style.space(5)

                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(16); height: Style.space(16)
                        radius: Math.min(mapRoot.corners.small, 4)
                        color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.14)
                        SensorGlyph {
                          anchors.centerIn: parent
                          width: Style.space(10); height: Style.space(10)
                          sensorKind: String(usCard.sn.kind || "motion")
                          tint: mapRoot.fg
                        }
                      }

                      Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Style.space(22) - placeSensBtn.width - Style.space(10)
                        spacing: 0
                        Text {
                          width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                          text: String(usCard.sn.name || "")
                          color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
                        }
                        Text {
                          width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                          text: mapRoot.sensorStatusText(usCard.sn)
                          color: mapRoot.dim; font.family: mapRoot.fontFamily; font.pixelSize: Math.max(9, Style.font.caption - 2)
                        }
                      }

                      Button {
                        id: placeSensBtn
                        anchors.verticalCenter: parent.verticalCenter
                        radius: mapRoot.corners.small
                        text: mapRoot.t("mapMenuPlace")
                        bordered: true
                        foreground: mapRoot.accentColor
                        fontFamily: mapRoot.fontFamily
                        fontSize: Math.max(9, Style.font.caption - 2)
                        horizontalPadding: Style.space(5)
                        verticalPadding: Style.space(1)
                        onClicked: mapRoot.placeSensor(usCard.sn.id)
                      }
                    }
                  }
                }
              }

              Text {
                visible: mapRoot.placedLampList.length === 0 && mapRoot.unplacedLampList.length === 0 && (mapRoot.sensors || []).length === 0
                width: sideCol.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: mapRoot.t("mapNoLamps")
                color: mapRoot.dim
                font.family: mapRoot.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      // =====================================================================
      // INTERACTIVE 2D FLOORPLAN CANVAS VIEWPORT
      // =====================================================================
      Rectangle {
        id: viewport
        width: mapRoot.showSidebar ? (parent.width - lampSidebar.width - Style.space(6)) : parent.width
        height: parent.height
        radius: mapRoot.corners.radius
        color: Qt.rgba(0.05, 0.06, 0.09, 0.72)
        border.width: 1
        border.color: mapRoot.hasSkin
          ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.36)
          : Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.18)
        clip: true

        readonly property real fitScale: Math.min((width - 16) / Math.max(1, mapRoot.canvasW), (height - 16) / Math.max(1, mapRoot.canvasH))
        readonly property real scale: Math.max(0.08, fitScale * mapRoot.userZoom)
        readonly property real offX: (width - mapRoot.canvasW * scale) * 0.5 + mapRoot.userPanX
        readonly property real offY: (height - mapRoot.canvasH * scale) * 0.5 + mapRoot.userPanY

        readonly property var hoverEntry: {
          if (mapRoot.hoverLampId) {
            var lt = mapRoot.lightById[mapRoot.hoverLampId]
            var pos = mapRoot.fpLamps[mapRoot.hoverLampId]
            if (lt && pos) return { name: String(lt.name || ""), pos: pos }
          }
          if (mapRoot.hoverSensorId) {
            var sn = mapRoot.sensorById[mapRoot.hoverSensorId]
            var spos = mapRoot.fpSensors[mapRoot.hoverSensorId]
            if (sn && spos) return { name: String(sn.name || ""), pos: spos }
          }
          return null
        }

        function toScreenX(cx) { return offX + cx * scale }
        function toScreenY(cy) { return offY + cy * scale }
        function toCanvasX(sx) { return (sx - offX) / Math.max(0.01, scale) }
        function toCanvasY(sy) { return (sy - offY) / Math.max(0.01, scale) }

        onWidthChanged: mapCanvas.requestPaint()
        onHeightChanged: mapCanvas.requestPaint()
        onScaleChanged: mapCanvas.requestPaint()
        onOffXChanged: mapCanvas.requestPaint()
        onOffYChanged: mapCanvas.requestPaint()

        // Pan / Zoom / Deselect / Wire click-to-edit MouseArea
        MouseArea {
          id: canvasBgMouse
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          hoverEnabled: true
          cursorShape: mapRoot.hoverRuleId !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
          property real lastX: 0
          property real lastY: 0
          property bool moved: false

          onPressed: function(mouse) {
            lastX = mouse.x
            lastY = mouse.y
            moved = false
          }
          onPositionChanged: function(mouse) {
            if (mapRoot.wireDragging) {
              mapRoot.wireCursorX = viewport.toCanvasX(mouse.x)
              mapRoot.wireCursorY = viewport.toCanvasY(mouse.y)
              mapCanvas.requestPaint()
              return
            }
            if (pressed) {
              var dx = mouse.x - lastX
              var dy = mouse.y - lastY
              if (Math.abs(dx) + Math.abs(dy) > 2) moved = true
              mapRoot.userPanX += dx
              mapRoot.userPanY += dy
              lastX = mouse.x
              lastY = mouse.y
              return
            }
            var hr = hitTestWire(mouse.x, mouse.y)
            var nextHover = hr ? String(hr.id) : ""
            if (nextHover !== mapRoot.hoverRuleId) {
              mapRoot.hoverRuleId = nextHover
              mapCanvas.requestPaint()
            }
          }
          onExited: {
            if (mapRoot.hoverRuleId !== "") {
              mapRoot.hoverRuleId = ""
              mapCanvas.requestPaint()
            }
          }
          onReleased: function(mouse) {
            if (moved) return
            // Clicking any existing rule line (in either Rules or Map sub-tab) opens the Edit Rule Dialog
            var hitRule = hitTestWire(mouse.x, mouse.y)
            if (hitRule) {
              mapRoot.openEditRuleDialog(hitRule)
            } else {
              mapRoot.selectedKind = ""
              mapRoot.selectedId = ""
              mapRoot.wireFromId = ""
              mapRoot.wireDragging = false
              mapCanvas.requestPaint()
            }
          }
          onWheel: function(wheel) {
            var factor = wheel.angleDelta.y > 0 ? 1.12 : (1.0 / 1.12)
            mapRoot.userZoom = Math.max(0.5, Math.min(3.5, mapRoot.userZoom * factor))
            wheel.accepted = true
          }

          // Hit-test along the entire quadratic Bezier curve of every visible rule wire
          function hitTestWire(sx, sy) {
            if (!mapRoot.wiresVisible) return null
            var rs = mapRoot.rules || []
            var best = null
            var bestDist = 14
            for (var i = 0; i < rs.length; i++) {
              var r = rs[i]
              if (!r) continue
              var p1 = mapRoot.entityCenter(r.trigger_kind, r.trigger_id)
              if (!p1) continue
              var targs = r.targets || []
              for (var j = 0; j < targs.length; j++) {
                var p2 = mapRoot.entityCenter(targs[j].kind, targs[j].id)
                if (!p2) continue
                var x1 = viewport.toScreenX(p1.x), y1 = viewport.toScreenY(p1.y)
                var x2 = viewport.toScreenX(p2.x), y2 = viewport.toScreenY(p2.y)
                var dist = Math.hypot(x2 - x1, y2 - y1)
                if (dist < 4) continue
                var cx = (x1 + x2) * 0.5
                var cy = (y1 + y2) * 0.5 - Math.min(48, dist * 0.18)
                for (var s = 1; s <= 9; s++) {
                  var u = s / 10.0
                  var inv = 1.0 - u
                  var bx = inv * inv * x1 + 2 * inv * u * cx + u * u * x2
                  var by = inv * inv * y1 + 2 * inv * u * cy + u * u * y2
                  var d = Math.hypot(sx - bx, sy - by)
                  if (d < bestDist) { bestDist = d; best = r }
                }
              }
            }
            return best
          }
        }

        // Layer 1: Optional Custom Floorplan Background Image
        Image {
          id: bgImage
          x: viewport.offX
          y: viewport.offY
          width: mapRoot.canvasW * viewport.scale
          height: mapRoot.canvasH * viewport.scale
          visible: mapRoot.bgPath !== ""
          opacity: mapRoot.bgOpacity
          asynchronous: true
          cache: false
          smooth: true
          sourceSize.width: 1920
          sourceSize.height: 1920
          fillMode: mapRoot.bgFit === "cover" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
          source: mapRoot.bgPath ? mapRoot.pathToFileUrl(mapRoot.bgPath) : ""

          Connections {
            target: mapRoot
            function onBgReloadTickChanged() {
              bgImage.source = ""
              Qt.callLater(function() {
                bgImage.source = mapRoot.bgPath ? mapRoot.pathToFileUrl(mapRoot.bgPath) : ""
              })
            }
          }
        }

        // Layer 2: Dot grid + architectural stamps + radial lamp halos + typed Bezier wires
        Canvas {
          id: mapCanvas
          anchors.fill: parent
          renderTarget: Canvas.Image

          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var sc = viewport.scale
            var ox = viewport.offX
            var oy = viewport.offY
            var cw = mapRoot.canvasW
            var ch = mapRoot.canvasH

            // 0. Day / Dusk / Night ambient simulation (view only)
            if (mapRoot.ambientDim > 0) {
              ctx.fillStyle = "rgba(0, 0, 0, " + mapRoot.ambientDim.toFixed(2) + ")"
              ctx.fillRect(0, 0, width, height)
            }

            // 1. Subtle architectural dot grid
            var step = Math.max(20, mapRoot.canvasGrid * 2)
            ctx.fillStyle = "rgba(255, 255, 255, 0.11)"
            for (var gx = 0; gx <= cw; gx += step) {
              var sx = ox + gx * sc
              if (sx < -2 || sx > width + 2) continue
              for (var gy = 0; gy <= ch; gy += step) {
                var sy = oy + gy * sc
                if (sy < -2 || sy > height + 2) continue
                ctx.fillRect(sx - 0.75, sy - 0.75, 1.5, 1.5)
              }
            }

            // 1b. Polygon rooms / zones on the active floor (rectangles are QML items above)
            var pboxes = mapRoot.fpBoxes || []
            for (var pbi = 0; pbi < pboxes.length; pbi++) {
              var pb = pboxes[pbi]
              if (!pb || !mapRoot.isPolygon(pb) || !mapRoot.onActiveFloor(pb)) continue
              drawPolygonBox(ctx, pb, ox, oy, sc)
            }

            // 2. Minimalist vector architectural stamps
            if (mapRoot.showFurniture) {
              var stamps = mapRoot.fpStamps || []
              for (var si = 0; si < stamps.length; si++) {
                var st = stamps[si]
                if (!st || !mapRoot.onActiveFloor(st)) continue
                var isSelSt = mapRoot.selectedKind === "stamp" && mapRoot.selectedId === st.id
                drawStamp(ctx, st, ox, oy, sc, isSelSt)
              }
            }

            // 3. Live radial light halos + active sensor / MotionAware glows
            if (mapRoot.showGlows) {
              var placed = mapRoot.floorPlacedLamps || []
              for (var li = 0; li < placed.length; li++) {
                var lt = placed[li].light
                var pos = placed[li].pos
                if (!lt) continue
                var lx = ox + pos.x * sc
                var ly = oy + pos.y * sc
                if (lt.on) {
                  var briFrac = Math.max(0.15, Math.min(1.0, Number(lt.bri || 50) / 100.0))
                  var rad = Math.max(26, (58 + briFrac * 96) * sc)
                  var c = Qt.color(lt.color || "#ffd27a")
                  var grad = ctx.createRadialGradient(lx, ly, 2, lx, ly, rad)
                  var gb = mapRoot.glowBoost
                  grad.addColorStop(0.0, "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + Math.min(0.85, 0.48 * briFrac * gb).toFixed(3) + ")")
                  grad.addColorStop(0.45, "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + Math.min(0.6, 0.18 * briFrac * gb).toFixed(3) + ")")
                  grad.addColorStop(1.0, "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ",0)")
                  ctx.fillStyle = grad
                  ctx.beginPath()
                  ctx.arc(lx, ly, rad, 0, Math.PI * 2)
                  ctx.fill()
                }
                if (lt.motion_aware && lt.motion_active) {
                  ctx.save()
                  ctx.strokeStyle = "rgba(16, 185, 129, 0.72)"
                  ctx.lineWidth = 2.0
                  ctx.beginPath()
                  ctx.arc(lx, ly, Math.max(18, 22 * sc), 0, Math.PI * 2)
                  ctx.stroke()
                  ctx.restore()
                }
              }
              var psens = mapRoot.floorPlacedSensors || []
              for (var psi = 0; psi < psens.length; psi++) {
                var sn = psens[psi].sensor
                var sp = psens[psi].pos
                if (!sn || sn.enabled === false) continue
                var srgb = null
                if (sn.kind === "motion" && sn.motion) srgb = [16, 185, 129]
                else if (sn.kind === "contact" && sn.open) srgb = [245, 158, 11]
                if (!srgb) continue
                var sx0 = ox + sp.x * sc
                var sy0 = oy + sp.y * sc
                var srad = Math.max(24, 52 * sc)
                var sgrad = ctx.createRadialGradient(sx0, sy0, 3, sx0, sy0, srad)
                sgrad.addColorStop(0.0, "rgba(" + srgb[0] + "," + srgb[1] + "," + srgb[2] + ",0.46)")
                sgrad.addColorStop(0.55, "rgba(" + srgb[0] + "," + srgb[1] + "," + srgb[2] + ",0.15)")
                sgrad.addColorStop(1.0, "rgba(" + srgb[0] + "," + srgb[1] + "," + srgb[2] + ",0)")
                ctx.fillStyle = sgrad
                ctx.beginPath()
                ctx.arc(sx0, sy0, srad, 0, Math.PI * 2)
                ctx.fill()
              }
            }

            // 3b. Planned fixtures & bendable LED strips (glow in Plan mode even with glows off)
            if (mapRoot.showGlows || mapRoot.toolMode === "plan") {
              var aps = mapRoot.activePlanned || []
              for (var api = 0; api < aps.length; api++) drawPlannedGlow(ctx, aps[api].pl, ox, oy, sc)
            }
            var aps2 = mapRoot.activePlanned || []
            for (var apj = 0; apj < aps2.length; apj++) {
              var spl = aps2[apj].pl
              if (spl && Array.isArray(spl.strip_points) && spl.strip_points.length >= 2) drawPlannedStrip(ctx, spl, ox, oy, sc)
            }

            // 4. Audio Light Synth active magenta overlay
            if (mapRoot.wiresVisible && mapRoot.synth && mapRoot.synth.running) {
              var synthRoom = String(mapRoot.synth.room_id || "")
              var pl2 = mapRoot.floorPlacedLamps || []
              ctx.save()
              ctx.strokeStyle = "rgba(217, 70, 239, 0.72)"
              ctx.lineWidth = 2.0
              for (var m = 0; m < pl2.length; m++) {
                var slt = pl2[m].light
                var spos = pl2[m].pos
                if (synthRoom && slt.room_id !== synthRoom) continue
                var mx = ox + spos.x * sc
                var my = oy + spos.y * sc
                ctx.beginPath()
                ctx.arc(mx, my, Math.max(15, 22 * sc), 0, Math.PI * 2)
                ctx.stroke()
              }
              ctx.restore()
            }

            // 5. Typed Bezier dependency wires (always visible in Rules sub-tab)
            if (mapRoot.wiresVisible) {
              var rules = mapRoot.rules || []
              for (var ri = 0; ri < rules.length; ri++) {
                var rule = rules[ri]
                if (!rule) continue
                var p1 = mapRoot.entityCenter(rule.trigger_kind, rule.trigger_id)
                if (!p1) continue
                var targs = rule.targets || []
                for (var ti = 0; ti < targs.length; ti++) {
                  var p2 = mapRoot.entityCenter(targs[ti].kind, targs[ti].id)
                  if (!p2) continue
                  var isHot = mapRoot.hoverRuleId === rule.id || (mapRoot.activeDialog === "rule" && mapRoot.ruleEditId === rule.id)
                  drawWire(ctx, ox + p1.x * sc, oy + p1.y * sc, ox + p2.x * sc, oy + p2.y * sc, rule, isHot)
                }
              }
            }

            // 6. Active wire-creation preview line in Rules sub-tab (Lamp OR Sensor source)
            if (mapRoot.toolMode === "wire" && mapRoot.wireFromId) {
              var wp = mapRoot.entityCenter(mapRoot.wireFromKind, mapRoot.wireFromId)
              if (wp) {
                var wx1 = ox + wp.x * sc
                var wy1 = oy + wp.y * sc
                var wx2 = mapRoot.wireDragging ? (ox + mapRoot.wireCursorX * sc) : wx1
                var wy2 = mapRoot.wireDragging ? (oy + mapRoot.wireCursorY * sc) : wy1
                ctx.save()
                ctx.strokeStyle = mapRoot.isSensorTriggerKind(mapRoot.wireFromKind) ? "#10B981" : "#38BDF8"
                ctx.lineWidth = 2.6
                ctx.setLineDash([6, 4])
                ctx.beginPath()
                ctx.arc(wx1, wy1, 18, 0, Math.PI * 2)
                ctx.stroke()
                if (mapRoot.wireDragging) {
                  ctx.beginPath()
                  ctx.moveTo(wx1, wy1)
                  ctx.lineTo(wx2, wy2)
                  ctx.stroke()
                }
                ctx.restore()
              }
            }
          }

          function rgbaOf(col, a) {
            var c = (typeof col === "string" || !col) ? Qt.color(col || "#ffd27a") : col
            return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + Math.max(0, Math.min(1, a)).toFixed(3) + ")"
          }

          function drawPolygonBox(ctx, b, ox, oy, sc) {
            var pts = b.points
            var isZone = b.kind === "zone"
            var isSel = mapRoot.selectedKind === "box" && mapRoot.selectedId === b.id
            var ma = b.hue_id ? mapRoot.motionAreaForRoom(b.hue_id) : null
            var motion = ma !== null && ma.enabled === true && ma.motion === true
            var li = mapRoot.boxLightInfo(b)
            var ac = mapRoot.accentColor
            ctx.save()
            ctx.beginPath()
            for (var i = 0; i < pts.length; i++) {
              var px = ox + pts[i].x * sc, py = oy + pts[i].y * sc
              if (i === 0) ctx.moveTo(px, py)
              else ctx.lineTo(px, py)
            }
            ctx.closePath()
            if (isSel) ctx.fillStyle = rgbaOf(ac, 0.14)
            else if (motion) ctx.fillStyle = "rgba(16,185,129,0.09)"
            else if (li.count > 0) ctx.fillStyle = "rgba(" + Math.round(li.r * 255) + "," + Math.round(li.g * 255) + "," + Math.round(li.b * 255) + "," + (isZone ? "0.08" : "0.13") + ")"
            else ctx.fillStyle = isZone ? "rgba(56,189,248,0.08)" : "rgba(255,255,255,0.045)"
            ctx.fill()
            ctx.lineWidth = isSel ? 2 : (motion ? 1.6 : 1.2)
            if (isSel) ctx.strokeStyle = rgbaOf(ac, 1)
            else if (motion) ctx.strokeStyle = "rgba(16,185,129,0.68)"
            else ctx.strokeStyle = isZone ? "rgba(56,189,248,0.45)" : "rgba(255,255,255,0.28)"
            if (isZone) ctx.setLineDash([6, 4])
            ctx.stroke()
            ctx.restore()
          }

          function drawPlannedGlow(ctx, pl, ox, oy, sc) {
            if (!pl || pl.on === false) return
            var lumenF = Math.max(0.35, Math.min(1.25, Number(pl.lumens || 800) / 1400))
            var maxR = Math.max(24, Math.min(260, Number(pl.beam_radius || 2.6) * mapRoot.pxPerMeter * sc))
            var gb = mapRoot.glowBoost
            var sp = Array.isArray(pl.strip_points) ? pl.strip_points : []
            ctx.save()
            if (sp.length >= 2) {
              ctx.lineCap = "round"
              ctx.lineJoin = "round"
              ctx.beginPath()
              for (var i = 0; i < sp.length; i++) {
                if (i === 0) ctx.moveTo(ox + sp[i].x * sc, oy + sp[i].y * sc)
                else ctx.lineTo(ox + sp[i].x * sc, oy + sp[i].y * sc)
              }
              ctx.strokeStyle = rgbaOf(pl.color, Math.min(0.65, 0.22 * lumenF * gb))
              ctx.lineWidth = Math.max(16, maxR * 0.36)
              ctx.stroke()
              ctx.strokeStyle = rgbaOf(pl.color, Math.min(0.9, 0.55 * lumenF * gb))
              ctx.lineWidth = 8
              ctx.stroke()
            } else {
              var cx = ox + Number(pl.x) * sc, cy = oy + Number(pl.y) * sc
              var grad = ctx.createRadialGradient(cx, cy, 2, cx, cy, maxR)
              grad.addColorStop(0.0, rgbaOf(pl.color, Math.min(0.85, 0.5 * lumenF * gb)))
              grad.addColorStop(0.45, rgbaOf(pl.color, Math.min(0.6, 0.2 * lumenF * gb)))
              grad.addColorStop(1.0, rgbaOf(pl.color, 0))
              ctx.fillStyle = grad
              ctx.beginPath()
              ctx.arc(cx, cy, maxR, 0, Math.PI * 2)
              ctx.fill()
            }
            ctx.restore()
          }

          function drawPlannedStrip(ctx, pl, ox, oy, sc) {
            var sp = pl.strip_points
            var isSel = mapRoot.selectedKind === "planned" && mapRoot.selectedId === pl.id
            ctx.save()
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.setLineDash([6, 4])
            ctx.lineWidth = isSel ? 3.2 : 2.6
            ctx.strokeStyle = pl.on !== false ? rgbaOf(pl.color, 1) : "rgba(255,255,255,0.5)"
            ctx.beginPath()
            for (var i = 0; i < sp.length; i++) {
              if (i === 0) ctx.moveTo(ox + sp[i].x * sc, oy + sp[i].y * sc)
              else ctx.lineTo(ox + sp[i].x * sc, oy + sp[i].y * sc)
            }
            ctx.stroke()
            ctx.restore()
          }

          function drawStamp(ctx, st, ox, oy, sc, selected) {
            var sx = ox + st.x * sc
            var sy = oy + st.y * sc
            var sw = st.w * sc
            var sh = st.h * sc
            var cx = sx + sw * 0.5
            var cy = sy + sh * 0.5
            ctx.save()
            ctx.translate(cx, cy)
            ctx.rotate((Number(st.rot || 0) * Math.PI) / 180.0)
            ctx.strokeStyle = selected ? "#38BDF8" : "rgba(210, 224, 245, 0.34)"
            ctx.fillStyle = selected ? "rgba(56, 189, 248, 0.14)" : "rgba(210, 224, 245, 0.06)"
            ctx.lineWidth = selected ? 1.8 : 1.15
            var hw = sw * 0.5, hh = sh * 0.5

            if (st.kind === "door") {
              ctx.beginPath()
              ctx.moveTo(-hw, -hh)
              ctx.lineTo(-hw, hh)
              ctx.moveTo(-hw, -hh)
              ctx.arc(-hw, -hh, Math.min(sw, sh), 0, Math.PI * 0.5)
              ctx.stroke()
            } else if (st.kind === "window") {
              ctx.fillRect(-hw, -hh, sw, sh)
              ctx.strokeRect(-hw, -hh, sw, sh)
              ctx.beginPath()
              ctx.moveTo(-hw, 0); ctx.lineTo(hw, 0)
              ctx.stroke()
            } else if (st.kind === "sofa") {
              ctx.fillRect(-hw, -hh, sw, sh)
              ctx.strokeRect(-hw, -hh, sw, sh)
              ctx.strokeRect(-hw, -hh, sw, sh * 0.28)
              ctx.strokeRect(-hw, -hh, sw * 0.14, sh)
              ctx.strokeRect(hw - sw * 0.14, -hh, sw * 0.14, sh)
            } else if (st.kind === "tv") {
              ctx.fillRect(-hw, -hh, sw, sh)
              ctx.strokeRect(-hw, -hh, sw, sh)
              ctx.beginPath()
              ctx.moveTo(-hw * 0.75, 0); ctx.lineTo(hw * 0.75, 0)
              ctx.stroke()
            } else if (st.kind === "desk") {
              ctx.fillRect(-hw, -hh, sw, sh * 0.72)
              ctx.strokeRect(-hw, -hh, sw, sh * 0.72)
              ctx.beginPath()
              ctx.arc(0, hh * 0.72, Math.min(sw, sh) * 0.22, Math.PI, 0)
              ctx.stroke()
            } else if (st.kind === "bed") {
              ctx.fillRect(-hw, -hh, sw, sh)
              ctx.strokeRect(-hw, -hh, sw, sh)
              ctx.strokeRect(-hw + sw * 0.08, -hh + sh * 0.08, sw * 0.36, sh * 0.22)
              ctx.strokeRect(sw * 0.06, -hh + sh * 0.08, sw * 0.36, sh * 0.22)
              ctx.beginPath()
              ctx.moveTo(-hw, -hh + sh * 0.42); ctx.lineTo(hw, -hh + sh * 0.42)
              ctx.stroke()
            } else if (st.kind === "dining") {
              ctx.fillRect(-hw * 0.82, -hh * 0.75, sw * 0.82, sh * 0.75)
              ctx.strokeRect(-hw * 0.82, -hh * 0.75, sw * 0.82, sh * 0.75)
              var cr = Math.max(2, Math.min(sw, sh) * 0.08)
              var chairs = [[-hw * 0.4, -hh * 0.92], [hw * 0.4, -hh * 0.92], [-hw * 0.4, hh * 0.92], [hw * 0.4, hh * 0.92]]
              for (var ci = 0; ci < chairs.length; ci++) {
                ctx.beginPath(); ctx.arc(chairs[ci][0], chairs[ci][1], cr, 0, Math.PI * 2); ctx.stroke()
              }
            } else if (st.kind === "kitchen") {
              ctx.fillRect(-hw, -hh, sw, sh)
              ctx.strokeRect(-hw, -hh, sw, sh)
              ctx.strokeRect(-hw + sw * 0.08, -hh + sh * 0.18, sw * 0.26, sh * 0.64)
              var br = Math.max(2, sh * 0.16)
              var burners = [[hw * 0.35, -hh * 0.32], [hw * 0.68, -hh * 0.32], [hw * 0.35, hh * 0.32], [hw * 0.68, hh * 0.32]]
              for (var bi = 0; bi < burners.length; bi++) {
                ctx.beginPath(); ctx.arc(burners[bi][0], burners[bi][1], br, 0, Math.PI * 2); ctx.stroke()
              }
            } else if (st.kind === "stairs") {
              ctx.fillRect(-hw, -hh, sw, sh)
              ctx.strokeRect(-hw, -hh, sw, sh)
              ctx.beginPath()
              for (var sti = 1; sti < 7; sti++) {
                var sty = -hh + sh * sti / 7
                ctx.moveTo(-hw, sty); ctx.lineTo(hw, sty)
              }
              ctx.moveTo(0, hh - 5); ctx.lineTo(0, -hh + 5)
              ctx.moveTo(0, -hh + 5); ctx.lineTo(-5, -hh + 11)
              ctx.moveTo(0, -hh + 5); ctx.lineTo(5, -hh + 11)
              ctx.stroke()
            }
            ctx.restore()
          }

          function drawWire(ctx, x1, y1, x2, y2, rule, highlighted) {
            var kind = String(rule.kind || "follow")
            var isSensRule = mapRoot.isSensorTriggerKind(String(rule.trigger_kind || ""))
            var mirror = kind === "follow" && rule.mirror_off === true
            var col = kind === "exclusive" ? "#F43F5E" : (kind === "companion" ? "#F59E0B" : (isSensRule ? "#10B981" : (mirror ? "#22D3EE" : "#38BDF8")))
            var alpha = rule.enabled === false ? 0.36 : 0.94
            var dist = Math.hypot(x2 - x1, y2 - y1)
            if (dist < 4) return
            var mx = (x1 + x2) * 0.5
            var my = (y1 + y2) * 0.5 - Math.min(48, dist * 0.18)

            ctx.save()
            ctx.globalAlpha = alpha
            ctx.strokeStyle = col
            ctx.fillStyle = col
            ctx.lineWidth = highlighted ? 3.8 : 2.4
            if (kind === "exclusive") ctx.setLineDash([7, 5])
            else if (kind === "companion") ctx.setLineDash([2, 5])
            else ctx.setLineDash([])

            ctx.beginPath()
            ctx.moveTo(x1, y1)
            ctx.quadraticCurveTo(mx, my, x2, y2)
            ctx.stroke()

            var dx = x2 - mx
            var dy = y2 - my
            var ang = Math.atan2(dy, dx)
            var ex = x2 - Math.cos(ang) * 14
            var ey = y2 - Math.sin(ang) * 14

            ctx.setLineDash([])
            if (kind === "exclusive") {
              var px = -Math.sin(ang) * 7
              var py = Math.cos(ang) * 7
              ctx.lineWidth = 2.6
              ctx.beginPath()
              ctx.moveTo(ex - px, ey - py)
              ctx.lineTo(ex + px, ey + py)
              ctx.stroke()
            } else if (kind === "companion") {
              ctx.save()
              ctx.translate(ex, ey)
              ctx.rotate(ang)
              ctx.fillStyle = "#11161f"
              ctx.beginPath()
              ctx.moveTo(5, 0); ctx.lineTo(0, 4.5); ctx.lineTo(-5, 0); ctx.lineTo(0, -4.5); ctx.closePath()
              ctx.fill()
              ctx.stroke()
              ctx.restore()
            } else {
              drawArrowHead(ctx, ex, ey, ang)
              if (mirror) {
                var angStart = Math.atan2(y1 - my, x1 - mx)
                drawArrowHead(ctx, x1 - Math.cos(angStart) * 14, y1 - Math.sin(angStart) * 14, angStart)
              }
            }

            if (highlighted) {
              var midX = 0.25 * x1 + 0.5 * mx + 0.25 * x2
              var midY = 0.25 * y1 + 0.5 * my + 0.25 * y2
              ctx.beginPath()
              ctx.arc(midX, midY, 5, 0, Math.PI * 2)
              ctx.fill()
            }
            ctx.restore()
          }

          function drawArrowHead(ctx, x, y, ang) {
            ctx.save()
            ctx.translate(x, y)
            ctx.rotate(ang)
            ctx.beginPath()
            ctx.moveTo(2, 0)
            ctx.lineTo(-8, -4.5)
            ctx.lineTo(-8, 4.5)
            ctx.closePath()
            ctx.fill()
            ctx.restore()
          }
        }

        // Layer 3: Interactive Movable & 8-Handle Resizable Room / Zone Boxes
        Repeater {
          model: mapRoot.fpBoxes.length
          delegate: Rectangle {
            id: boxItem
            required property int index
            readonly property var bx: mapRoot.fpBoxes[index] || ({ id: "", kind: "room", name: "", x: 0, y: 0, w: 200, h: 150 })
            readonly property bool isZone: bx.kind === "zone"
            readonly property bool isSel: mapRoot.selectedKind === "box" && mapRoot.selectedId === bx.id
            readonly property var hueRoom: bx.hue_id ? mapRoot.findRoomByHueId(bx.hue_id) : null
            readonly property var boxScheds: bx.hue_id ? mapRoot.roomSchedules(bx.hue_id) : []
            readonly property var boxMotionArea: bx.hue_id ? mapRoot.motionAreaForRoom(bx.hue_id) : null
            readonly property bool boxMotionActive: boxMotionArea !== null && boxMotionArea.enabled === true && boxMotionArea.motion === true
            readonly property bool isPoly: mapRoot.isPolygon(bx)
            readonly property bool onFloor: mapRoot.onActiveFloor(bx)
            readonly property var litInfo: mapRoot.boxLightInfo(bx)
            readonly property real areaM2: Math.max(0.5, mapRoot.boxAreaM2(bx))
            readonly property int luxNow: Math.round(litInfo.lumens / areaM2)
            // Polygon label sits below the top-most corner (the bbox corner can be outside the walls)
            readonly property var topPt: {
              if (!isPoly) return ({ x: bx.x, y: bx.y })
              var best = bx.points[0]
              for (var i = 1; i < bx.points.length; i++) if (bx.points[i].y < best.y) best = bx.points[i]
              return best
            }

            visible: onFloor
            x: viewport.toScreenX(bx.x)
            y: viewport.toScreenY(bx.y)
            width: Math.max(28, bx.w * viewport.scale)
            height: Math.max(24, bx.h * viewport.scale)
            radius: Math.min(mapRoot.corners.small, 6)
            // Selected room rises above zones (handles stay reachable) but stays below stamps (z 4)
            z: isSel ? 3.5 : (isZone ? 3 : 2)
            color: isPoly ? "transparent" : (isSel
              ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.14)
              : (boxMotionActive
                ? Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.09)
                : (litInfo.count > 0
                  ? Qt.rgba(litInfo.r, litInfo.g, litInfo.b, isZone ? 0.08 : 0.13)
                  : (isZone ? Qt.rgba(56 / 255, 189 / 255, 248 / 255, 0.08) : Qt.rgba(1, 1, 1, 0.045)))))
            border.width: isPoly ? 0 : (isSel ? 2 : (boxMotionActive ? 1.6 : 1.2))
            border.color: isSel
              ? mapRoot.accentColor
              : (boxMotionActive
                ? Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.68)
                : (isZone ? Qt.rgba(56 / 255, 189 / 255, 248 / 255, 0.45) : Qt.rgba(1, 1, 1, 0.28)))

            // Header badge
            Rectangle {
              id: boxHeader
              x: boxItem.isPoly ? Math.max(3, Math.min(boxItem.width - width - 3, (boxItem.topPt.x - boxItem.bx.x) * viewport.scale + 6)) : 3
              y: boxItem.isPoly ? Math.max(3, (boxItem.topPt.y - boxItem.bx.y) * viewport.scale + 5) : 3
              width: Math.min(parent.width - 6, boxHdrRow.implicitWidth + Style.space(10))
              height: Style.space(18)
              radius: Math.min(mapRoot.corners.small, 4)
              color: Qt.rgba(0.06, 0.08, 0.12, 0.78)

              Row {
                id: boxHdrRow
                anchors.verticalCenter: parent.verticalCenter
                x: Style.space(5)
                spacing: Style.space(4)

                Rectangle {
                  visible: boxItem.hueRoom !== null
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(7); height: Style.space(7); radius: width / 2
                  color: (boxItem.hueRoom && boxItem.hueRoom.on) ? (boxItem.hueRoom.color || "#ffd27a") : Qt.rgba(1, 1, 1, 0.28)
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: mapRoot.roomIconGlyph(boxItem.bx.archetype, boxItem.bx.kind)
                  color: boxItem.isZone ? "#38BDF8" : mapRoot.fg
                  font.family: mapRoot.fontFamily
                  font.pixelSize: Math.max(9, Style.font.caption - 1)
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, Math.max(Style.space(28), boxItem.width - (boxAreaTxt.visible ? boxAreaTxt.implicitWidth : 0) - Style.space(44)))
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: String(boxItem.bx.name || "")
                  color: mapRoot.fg
                  font.family: mapRoot.fontFamily
                  font.pixelSize: Math.max(9, Style.font.caption - 1)
                  font.bold: true
                }
                Text {
                  id: boxAreaTxt
                  visible: boxItem.width > Style.space(mapRoot.toolMode === "plan" ? 190 : 130)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: Math.round(boxItem.areaM2) + " m²"
                    + (mapRoot.toolMode === "plan" ? (" · " + boxItem.luxNow + "/" + mapRoot.targetLux(boxItem.bx.archetype) + " lx") : "")
                  color: mapRoot.toolMode === "plan" && boxItem.luxNow < mapRoot.targetLux(boxItem.bx.archetype) * 0.6
                    ? "#F59E0B" : mapRoot.dim
                  font.family: mapRoot.fontFamily
                  font.pixelSize: Math.max(8, Style.font.caption - 2)
                }
                Text {
                  visible: boxItem.boxScheds.length > 0
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "⏰" + (boxItem.boxScheds.length > 1 ? String(boxItem.boxScheds.length) : "")
                  color: "#F59E0B"
                  font.family: mapRoot.fontFamily
                  font.pixelSize: Math.max(9, Style.font.caption - 1)
                }
                Rectangle {
                  visible: boxItem.boxMotionActive
                  anchors.verticalCenter: parent.verticalCenter
                  width: boxMotTxt.implicitWidth + Style.space(6)
                  height: Style.space(12)
                  radius: height * 0.5
                  color: Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.28)
                  border.width: 1
                  border.color: "#10B981"
                  Text {
                    id: boxMotTxt
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "● " + mapRoot.t("motionPresence")
                    color: "#10B981"
                    font.family: mapRoot.fontFamily
                    font.pixelSize: Math.max(8, Style.font.caption - 3)
                    font.bold: true
                  }
                }
              }
            }

            // Drag-to-move box (in Map sub-tab; passes clicks to canvas wire hit-test if clicking a wire!)
            MouseArea {
              anchors.fill: parent
              enabled: mapRoot.editMode && boxItem.onFloor
              cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
              property real startMouseX: 0
              property real startMouseY: 0
              property real origX: 0
              property real origY: 0
              property var enclosedOrig: ({})
              property var enclosedSensorsOrig: ({})
              property var enclosedPlannedOrig: ({})
              property var origPoints: []
              property bool dragged: false

              onPressed: function(mouse) {
                var pt = mapToItem(viewport, mouse.x, mouse.y)
                // If clicking directly on an existing rule wire inside the room box, let the wire open Edit Rule Dialog!
                var wireHit = canvasBgMouse.hitTestWire(pt.x, pt.y)
                if (wireHit) {
                  mouse.accepted = false
                  return
                }
                // Polygon rooms: clicks in the bounding box but outside the walls fall through
                if (boxItem.isPoly && !mapRoot.boxContains(boxItem.bx, viewport.toCanvasX(pt.x), viewport.toCanvasY(pt.y))) {
                  mouse.accepted = false
                  return
                }
                startMouseX = pt.x
                startMouseY = pt.y
                origX = boxItem.bx.x
                origY = boxItem.bx.y
                dragged = false
                var enc = ({})
                var encS = ({})
                var encP = ({})
                if (!boxItem.isZone) {
                  var bf = mapRoot.floorOf(boxItem.bx)
                  var ls = mapRoot.fpLamps || ({})
                  for (var lid in ls) {
                    var p = ls[lid]
                    if (p && mapRoot.floorOf(p) === bf && mapRoot.boxContains(boxItem.bx, Number(p.x), Number(p.y))) {
                      enc[lid] = { x: p.x, y: p.y }
                    }
                  }
                  var ss = mapRoot.fpSensors || ({})
                  for (var sid in ss) {
                    var sp = ss[sid]
                    if (sp && mapRoot.floorOf(sp) === bf && mapRoot.boxContains(boxItem.bx, Number(sp.x), Number(sp.y))) {
                      encS[sid] = { x: sp.x, y: sp.y }
                    }
                  }
                  var plist = mapRoot.fpPlanned || []
                  for (var pi = 0; pi < plist.length; pi++) {
                    var an = mapRoot.plannedAnchor(plist[pi])
                    if (mapRoot.floorOf(plist[pi]) === bf && mapRoot.boxContains(boxItem.bx, an.x, an.y)) {
                      encP[plist[pi].id] = JSON.parse(JSON.stringify(plist[pi]))
                    }
                  }
                }
                enclosedOrig = enc
                enclosedSensorsOrig = encS
                enclosedPlannedOrig = encP
                origPoints = JSON.parse(JSON.stringify(boxItem.bx.points || []))
                mapRoot.selectItem("box", boxItem.bx.id)
              }
              onPositionChanged: function(mouse) {
                if (!pressed) return
                var pt = mapToItem(viewport, mouse.x, mouse.y)
                var dx = (pt.x - startMouseX) / viewport.scale
                var dy = (pt.y - startMouseY) / viewport.scale
                if (!dragged && Math.hypot(pt.x - startMouseX, pt.y - startMouseY) < 4) return
                dragged = true
                mapRoot.isDragging = true
                var fp = mapRoot.cloneFp(mapRoot.workingFp)
                var target = fp.boxes[boxItem.index]
                if (!target) return
                var nx = Math.max(0, Math.min(mapRoot.canvasW - target.w, mapRoot.snapVal(origX + dx)))
                var ny = Math.max(0, Math.min(mapRoot.canvasH - target.h, mapRoot.snapVal(origY + dy)))
                var appliedDx = nx - origX
                var appliedDy = ny - origY
                target.x = nx
                target.y = ny
                if (origPoints.length >= 3) {
                  target.points = []
                  for (var vi = 0; vi < origPoints.length; vi++) {
                    target.points.push({ x: Math.round((origPoints[vi].x + appliedDx) * 10) / 10, y: Math.round((origPoints[vi].y + appliedDy) * 10) / 10 })
                  }
                }
                var plw = fp.planned_lights || []
                for (var pw = 0; pw < plw.length; pw++) {
                  var po = enclosedPlannedOrig[plw[pw].id]
                  if (!po) continue
                  plw[pw].x = Math.round((Number(po.x) + appliedDx) * 10) / 10
                  plw[pw].y = Math.round((Number(po.y) + appliedDy) * 10) / 10
                  var spo = po.strip_points || []
                  plw[pw].strip_points = []
                  for (var sq = 0; sq < spo.length; sq++) {
                    plw[pw].strip_points.push({ x: Math.round((spo[sq].x + appliedDx) * 10) / 10, y: Math.round((spo[sq].y + appliedDy) * 10) / 10 })
                  }
                }
                for (var lid in enclosedOrig) {
                  if (fp.lamps && fp.lamps[lid]) {
                    fp.lamps[lid].x = Math.max(10, Math.min(mapRoot.canvasW - 10, Math.round((enclosedOrig[lid].x + appliedDx) * 10) / 10))
                    fp.lamps[lid].y = Math.max(10, Math.min(mapRoot.canvasH - 10, Math.round((enclosedOrig[lid].y + appliedDy) * 10) / 10))
                  }
                }
                for (var sid in enclosedSensorsOrig) {
                  if (fp.sensors && fp.sensors[sid]) {
                    fp.sensors[sid].x = Math.max(10, Math.min(mapRoot.canvasW - 10, Math.round((enclosedSensorsOrig[sid].x + appliedDx) * 10) / 10))
                    fp.sensors[sid].y = Math.max(10, Math.min(mapRoot.canvasH - 10, Math.round((enclosedSensorsOrig[sid].y + appliedDy) * 10) / 10))
                  }
                }
                mapRoot.workingFp = fp
                mapCanvas.requestPaint()
              }
              onReleased: {
                if (dragged) {
                  mapRoot.isDragging = false
                  mapRoot.commitFp(mapRoot.workingFp, true)
                }
              }
              onDoubleClicked: {
                if (boxItem.hueRoom && boxItem.hueRoom.grouped_light) {
                  mapRoot.sendCommand({ cmd: "group", id: boxItem.hueRoom.grouped_light, on: !boxItem.hueRoom.on })
                }
              }
            }

            // 8 Resize Handles (shown when selected)
            Repeater {
              model: (boxItem.isSel && !boxItem.isPoly && mapRoot.editMode) ? [
                { id: "nw", rx: 0.0, ry: 0.0, cur: Qt.SizeFDiagCursor },
                { id: "n",  rx: 0.5, ry: 0.0, cur: Qt.SizeVerCursor },
                { id: "ne", rx: 1.0, ry: 0.0, cur: Qt.SizeBDiagCursor },
                { id: "e",  rx: 1.0, ry: 0.5, cur: Qt.SizeHorCursor },
                { id: "se", rx: 1.0, ry: 1.0, cur: Qt.SizeFDiagCursor },
                { id: "s",  rx: 0.5, ry: 1.0, cur: Qt.SizeVerCursor },
                { id: "sw", rx: 0.0, ry: 1.0, cur: Qt.SizeBDiagCursor },
                { id: "w",  rx: 0.0, ry: 0.5, cur: Qt.SizeHorCursor }
              ] : []
              delegate: Rectangle {
                id: handleRect
                required property var modelData
                width: Style.space(8)
                height: Style.space(8)
                x: boxItem.width * modelData.rx - width * 0.5
                y: boxItem.height * modelData.ry - height * 0.5
                radius: 2
                z: 10
                color: "#ffffff"
                border.width: 1.5
                border.color: mapRoot.accentColor

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -3
                  cursorShape: handleRect.modelData.cur
                  property real startX: 0
                  property real startY: 0
                  property real ox: 0
                  property real oy: 0
                  property real ow: 0
                  property real oh: 0

                  onPressed: function(mouse) {
                    var pt = mapToItem(viewport, mouse.x, mouse.y)
                    startX = pt.x; startY = pt.y
                    ox = boxItem.bx.x; oy = boxItem.bx.y
                    ow = boxItem.bx.w; oh = boxItem.bx.h
                    mapRoot.isDragging = true
                    mouse.accepted = true
                  }
                  onPositionChanged: function(mouse) {
                    if (!pressed) return
                    var pt = mapToItem(viewport, mouse.x, mouse.y)
                    var dx = (pt.x - startX) / viewport.scale
                    var dy = (pt.y - startY) / viewport.scale
                    var fp = mapRoot.cloneFp(mapRoot.workingFp)
                    var b = fp.boxes[boxItem.index]
                    if (!b) return
                    var hId = handleRect.modelData.id
                    var nx = ox, ny = oy, nw = ow, nh = oh
                    if (hId.indexOf("e") >= 0) nw = Math.max(80, mapRoot.snapVal(ow + dx))
                    if (hId.indexOf("s") >= 0) nh = Math.max(80, mapRoot.snapVal(oh + dy))
                    if (hId.indexOf("w") >= 0) {
                      var right = ox + ow
                      nx = Math.max(0, Math.min(right - 80, mapRoot.snapVal(ox + dx)))
                      nw = right - nx
                    }
                    if (hId.indexOf("n") >= 0) {
                      var bottom = oy + oh
                      ny = Math.max(0, Math.min(bottom - 80, mapRoot.snapVal(oy + dy)))
                      nh = bottom - ny
                    }
                    b.x = Math.max(0, nx)
                    b.y = Math.max(0, ny)
                    b.w = Math.max(80, Math.min(mapRoot.canvasW - b.x, nw))
                    b.h = Math.max(80, Math.min(mapRoot.canvasH - b.y, nh))
                    mapRoot.workingFp = fp
                    mapCanvas.requestPaint()
                  }
                  onReleased: {
                    mapRoot.isDragging = false
                    mapRoot.commitFp(mapRoot.workingFp, true)
                  }
                }
              }
            }

            // Polygon wall midpoints: '+' inserts a corner (drag it right away), wall length in metres
            Repeater {
              model: (boxItem.isSel && boxItem.isPoly && mapRoot.editMode && boxItem.bx.points.length < 32) ? boxItem.bx.points.length : 0
              delegate: Item {
                id: midH
                required property int index
                readonly property var a: boxItem.bx.points[index] || ({ x: 0, y: 0 })
                readonly property var c: boxItem.bx.points[(index + 1) % Math.max(1, boxItem.bx.points.length)] || ({ x: 0, y: 0 })
                readonly property real segPx: Math.hypot(c.x - a.x, c.y - a.y)
                readonly property real mx: (a.x + c.x) * 0.5
                readonly property real my: (a.y + c.y) * 0.5
                visible: segPx * viewport.scale >= 42
                x: (mx - boxItem.bx.x) * viewport.scale - Style.space(6)
                y: (my - boxItem.bx.y) * viewport.scale - Style.space(6)
                width: Style.space(12)
                height: Style.space(12)
                z: 11
                Rectangle {
                  anchors.fill: parent
                  radius: width * 0.5
                  color: mapRoot.accentColor
                  border.width: 1.1
                  border.color: "#ffffff"
                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "+"
                    color: "#ffffff"
                    font.family: mapRoot.fontFamily
                    font.pixelSize: Math.max(8, Style.font.caption - 2)
                    font.bold: true
                  }
                }
                Text {
                  x: parent.width + Style.space(3)
                  y: -Style.space(1)
                  textFormat: Text.PlainText
                  text: (midH.segPx / mapRoot.pxPerMeter).toFixed(1) + "m"
                  color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.72)
                  font.family: mapRoot.fontFamily
                  font.pixelSize: Math.max(8, Style.font.caption - 3)
                }
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -3
                  cursorShape: Qt.PointingHandCursor
                  onClicked: mapRoot.insertBoxVertex(boxItem.bx.id, midH.index, midH.mx, midH.my)
                }
              }
            }

            // Polygon corners: drag to move, right-click to remove (keeps at least 3)
            Repeater {
              model: (boxItem.isSel && boxItem.isPoly && mapRoot.editMode) ? boxItem.bx.points.length : 0
              delegate: Rectangle {
                id: vtxH
                required property int index
                readonly property var pt: boxItem.bx.points[index] || ({ x: 0, y: 0 })
                width: Style.space(11)
                height: Style.space(11)
                radius: width * 0.5
                x: (pt.x - boxItem.bx.x) * viewport.scale - width * 0.5
                y: (pt.y - boxItem.bx.y) * viewport.scale - height * 0.5
                z: 12
                color: mapRoot.accentColor
                border.width: 1.5
                border.color: "#ffffff"

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -3
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.SizeAllCursor
                  property real startX: 0
                  property real startY: 0
                  property real ox: 0
                  property real oy: 0
                  property bool moved: false
                  onPressed: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                      mapRoot.removeBoxVertex(boxItem.bx.id, vtxH.index)
                      return
                    }
                    var p = mapToItem(viewport, mouse.x, mouse.y)
                    startX = p.x; startY = p.y
                    ox = vtxH.pt.x; oy = vtxH.pt.y
                    moved = false
                  }
                  onPositionChanged: function(mouse) {
                    if (!pressed || !(pressedButtons & Qt.LeftButton)) return
                    var p = mapToItem(viewport, mouse.x, mouse.y)
                    if (!moved && Math.hypot(p.x - startX, p.y - startY) < 3) return
                    moved = true
                    mapRoot.isDragging = true
                    var fp = mapRoot.cloneFp(mapRoot.workingFp)
                    var b = fp.boxes[boxItem.index]
                    if (!b || !Array.isArray(b.points) || vtxH.index >= b.points.length) return
                    b.points[vtxH.index] = {
                      x: Math.max(-200, Math.min(mapRoot.canvasW, mapRoot.snapVal(ox + (p.x - startX) / viewport.scale))),
                      y: Math.max(-200, Math.min(mapRoot.canvasH, mapRoot.snapVal(oy + (p.y - startY) / viewport.scale)))
                    }
                    mapRoot.syncBounds(b)
                    mapRoot.workingFp = fp
                    mapCanvas.requestPaint()
                  }
                  onReleased: function(mouse) {
                    if (mouse.button !== Qt.LeftButton || !moved) return
                    mapRoot.isDragging = false
                    mapRoot.commitFp(mapRoot.workingFp, true)
                  }
                }
              }
            }
          }
        }

        // Layer 4: Draggable Architectural Stamp Hit Targets
        Repeater {
          model: (mapRoot.showFurniture && mapRoot.editMode) ? mapRoot.fpStamps.length : 0
          delegate: Item {
            id: stampHit
            required property int index
            readonly property var st: mapRoot.fpStamps[index] || ({ id: "", x: 0, y: 0, w: 40, h: 40, rot: 0 })
            visible: mapRoot.onActiveFloor(st)
            x: viewport.toScreenX(st.x)
            y: viewport.toScreenY(st.y)
            width: Math.max(14, st.w * viewport.scale)
            height: Math.max(14, st.h * viewport.scale)
            z: 4

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.SizeAllCursor
              property real sx: 0
              property real sy: 0
              property real ox: 0
              property real oy: 0
              property bool moved: false
              onPressed: function(mouse) {
                var pt = mapToItem(viewport, mouse.x, mouse.y)
                sx = pt.x; sy = pt.y
                ox = stampHit.st.x; oy = stampHit.st.y
                moved = false
                mapRoot.selectItem("stamp", stampHit.st.id)
              }
              onPositionChanged: function(mouse) {
                if (!pressed) return
                var pt = mapToItem(viewport, mouse.x, mouse.y)
                if (!moved && Math.hypot(pt.x - sx, pt.y - sy) < 3) return
                moved = true
                mapRoot.isDragging = true
                var fp = mapRoot.cloneFp(mapRoot.workingFp)
                var target = fp.stamps[stampHit.index]
                if (!target) return
                target.x = Math.max(0, Math.min(mapRoot.canvasW - target.w, mapRoot.snapVal(ox + (pt.x - sx) / viewport.scale)))
                target.y = Math.max(0, Math.min(mapRoot.canvasH - target.h, mapRoot.snapVal(oy + (pt.y - sy) / viewport.scale)))
                mapRoot.workingFp = fp
                mapCanvas.requestPaint()
              }
              onReleased: {
                if (moved) {
                  mapRoot.isDragging = false
                  mapRoot.commitFp(mapRoot.workingFp, false)
                }
              }
            }
          }
        }

        // Layer 5: Interactive Lamp Nodes (NO permanent captions — clean hover-only tooltip pill!)
        Repeater {
          model: mapRoot.floorPlacedLamps.length
          delegate: Item {
            id: lampNode
            required property int index
            readonly property var entry: mapRoot.floorPlacedLamps[index] || ({ light: ({}), pos: ({ x: 0, y: 0, icon: "bulb" }) })
            readonly property var lt: entry.light || ({})
            readonly property var pos: entry.pos || ({ x: 0, y: 0, icon: "bulb" })
            readonly property string lampIcon: mapRoot.lampIconFor(lt.id)
            readonly property bool isSel: mapRoot.selectedKind === "lamp" && mapRoot.selectedId === lt.id
            readonly property bool isWireSrc: mapRoot.toolMode === "wire" && mapRoot.wireFromKind === "light" && mapRoot.wireFromId === lt.id
            readonly property bool isHovered: mapRoot.hoverLampId === lt.id
            readonly property real nodeDiam: Style.space(26)

            x: viewport.toScreenX(pos.x) - nodeDiam * 0.5
            y: viewport.toScreenY(pos.y) - nodeDiam * 0.5
            width: nodeDiam
            height: nodeDiam
            z: isSel || isHovered ? 20 : 10

            // Circular node body (1:1 with sidebar badge)
            Rectangle {
              id: nodeCircle
              anchors.fill: parent
              radius: width * 0.5
              color: lampNode.lt.on ? (lampNode.lt.color || "#ffd27a") : Qt.rgba(22 / 255, 26 / 255, 36 / 255, 0.92)
              border.width: lampNode.isSel || lampNode.isWireSrc || lampNode.isHovered ? 2.4 : 1.5
              border.color: lampNode.isWireSrc
                ? "#38BDF8"
                : (lampNode.isSel ? mapRoot.accentColor : (lampNode.lt.on ? "#ffffff" : Qt.rgba(1, 1, 1, 0.42)))

              LampGlyph {
                anchors.centerIn: parent
                width: Style.space(16)
                height: Style.space(16)
                iconName: lampNode.lampIcon
                version: mapRoot.iconVersion
                tint: mapRoot.contrastTintForLight(lampNode.lt)
              }
            }

            // Bridge Pro MotionAware™ top-right radar/wave badge (calm cyan monitoring, bright emerald when active)
            Rectangle {
              visible: lampNode.lt.motion_aware === true
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.topMargin: -Style.space(3)
              anchors.rightMargin: -Style.space(3)
              width: Style.space(12)
              height: Style.space(12)
              radius: width * 0.5
              z: 3
              color: lampNode.lt.motion_active === true ? "#10B981" : "#06B6D4"
              border.width: 1.4
              border.color: lampNode.lt.motion_active === true ? "#d1fae5" : "#0b111c"
              SensorGlyph {
                anchors.centerIn: parent
                width: Style.space(8)
                height: Style.space(8)
                sensorKind: "motion"
                tint: "#081018"
              }
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              hoverEnabled: true
              cursorShape: mapRoot.toolMode === "wire" ? Qt.CrossCursor : (pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor)
              property real startSX: 0
              property real startSY: 0
              property real origCX: 0
              property real origCY: 0
              property bool dragged: false
              property bool leftActive: false

              onEntered: { mapRoot.hoverSensorId = ""; mapRoot.hoverLampId = lampNode.lt.id }
              onExited: {
                if (mapRoot.hoverLampId === lampNode.lt.id) mapRoot.hoverLampId = ""
              }

              onPressed: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  leftActive = false
                  mapRoot.sendCommand({ cmd: "light", id: lampNode.lt.id, on: !lampNode.lt.on })
                  mouse.accepted = true
                  return
                }
                leftActive = true
                var pt = mapToItem(viewport, mouse.x, mouse.y)
                startSX = pt.x; startSY = pt.y
                origCX = lampNode.pos.x; origCY = lampNode.pos.y
                dragged = false
                if (mapRoot.toolMode === "wire") {
                  if (mapRoot.wireFromId && !(mapRoot.wireFromKind === "light" && mapRoot.wireFromId === lampNode.lt.id)) {
                    leftActive = false
                    mapRoot.openNewRuleDialog(mapRoot.wireFromKind, mapRoot.wireFromId, "light", lampNode.lt.id)
                  } else {
                    mapRoot.wireFromKind = "light"
                    mapRoot.wireFromId = lampNode.lt.id
                    mapRoot.wireCursorX = lampNode.pos.x
                    mapRoot.wireCursorY = lampNode.pos.y
                    mapRoot.wireDragging = true
                    mapCanvas.requestPaint()
                  }
                } else {
                  mapRoot.selectItem("lamp", lampNode.lt.id)
                }
              }
              onPositionChanged: function(mouse) {
                if (!leftActive || !pressed) return
                var pt = mapToItem(viewport, mouse.x, mouse.y)
                if (mapRoot.toolMode === "wire") {
                  mapRoot.wireCursorX = viewport.toCanvasX(pt.x)
                  mapRoot.wireCursorY = viewport.toCanvasY(pt.y)
                  mapCanvas.requestPaint()
                  return
                }
                if (!dragged && Math.hypot(pt.x - startSX, pt.y - startSY) < 4) return
                dragged = true
                mapRoot.isDragging = true
                var fp = mapRoot.cloneFp(mapRoot.workingFp)
                if (!fp.lamps[lampNode.lt.id]) return
                fp.lamps[lampNode.lt.id].x = Math.max(12, Math.min(mapRoot.canvasW - 12, mapRoot.snapVal(origCX + (pt.x - startSX) / viewport.scale)))
                fp.lamps[lampNode.lt.id].y = Math.max(12, Math.min(mapRoot.canvasH - 12, mapRoot.snapVal(origCY + (pt.y - startSY) / viewport.scale)))
                mapRoot.workingFp = fp
                mapCanvas.requestPaint()
              }
              onReleased: function(mouse) {
                if (!leftActive) return
                leftActive = false
                if (mapRoot.toolMode === "wire") {
                  var pt = mapToItem(viewport, mouse.x, mouse.y)
                  var cx = viewport.toCanvasX(pt.x)
                  var cy = viewport.toCanvasY(pt.y)
                  var hitId = ""
                  var bestD = 28 / Math.max(0.15, viewport.scale)
                  var pl = mapRoot.floorPlacedLamps || []
                  for (var i = 0; i < pl.length; i++) {
                    if (mapRoot.wireFromKind === "light" && pl[i].light.id === mapRoot.wireFromId) continue
                    var d = Math.hypot(pl[i].pos.x - cx, pl[i].pos.y - cy)
                    if (d < bestD) { bestD = d; hitId = pl[i].light.id }
                  }
                  mapRoot.wireDragging = false
                  if (hitId) {
                    mapRoot.openNewRuleDialog(mapRoot.wireFromKind, mapRoot.wireFromId, "light", hitId)
                  } else if (Math.hypot(pt.x - startSX, pt.y - startSY) > 20) {
                    // Dropped on empty space after dragging: cancel preview line
                    mapRoot.wireFromKind = "light"
                    mapRoot.wireFromId = ""
                  }
                  mapCanvas.requestPaint()
                  return
                }
                if (dragged) {
                  mapRoot.isDragging = false
                  mapRoot.commitFp(mapRoot.workingFp, true)
                }
              }
              onDoubleClicked: function(mouse) {
                if (mouse.button === Qt.LeftButton && mapRoot.editMode) {
                  mapRoot.sendCommand({ cmd: "light", id: lampNode.lt.id, on: !lampNode.lt.on })
                }
              }
            }
          }
        }

        // Layer 5B: Interactive Physical Sensor & Switch Nodes (28x28 rounded-square nodes, distinct from circular lamps)
        Repeater {
          model: mapRoot.floorPlacedSensors.length
          delegate: Item {
            id: sensorNode
            required property int index
            readonly property var entry: mapRoot.floorPlacedSensors[index] || ({ sensor: ({}), pos: ({ x: 0, y: 0 }) })
            readonly property var sn: entry.sensor || ({})
            readonly property var pos: entry.pos || ({ x: 0, y: 0 })
            readonly property bool isSel: mapRoot.selectedKind === "sensor" && mapRoot.selectedId === sn.id
            readonly property bool isWireSrc: mapRoot.toolMode === "wire" && mapRoot.wireFromId === sn.id && mapRoot.wireFromKind === sn.kind
            readonly property bool isHovered: mapRoot.hoverSensorId === sn.id
            readonly property bool isActive: (sn.kind === "motion" && sn.motion === true && sn.enabled !== false)
              || (sn.kind === "contact" && sn.open === true && sn.enabled !== false)
            readonly property real nodeSize: Style.space(28)

            x: viewport.toScreenX(pos.x) - nodeSize * 0.5
            y: viewport.toScreenY(pos.y) - nodeSize * 0.5
            width: nodeSize
            height: nodeSize
            z: isSel || isHovered ? 22 : 12

            Rectangle {
              anchors.fill: parent
              radius: Style.space(6)
              opacity: sensorNode.sn.enabled === false ? 0.50 : 1.0
              color: sensorNode.sn.kind === "motion"
                ? (sensorNode.isActive ? "#10B981" : Qt.rgba(16 / 255, 36 / 255, 34 / 255, 0.94))
                : (sensorNode.sn.kind === "contact"
                  ? (sensorNode.isActive ? "#F59E0B" : Qt.rgba(38 / 255, 30 / 255, 18 / 255, 0.94))
                  : Qt.rgba(24 / 255, 28 / 255, 42 / 255, 0.94))
              border.width: sensorNode.isSel || sensorNode.isWireSrc || sensorNode.isHovered ? 2.4 : 1.6
              border.color: sensorNode.isWireSrc
                ? "#10B981"
                : (sensorNode.isSel
                  ? mapRoot.accentColor
                  : (sensorNode.isActive
                    ? "#ffffff"
                    : (sensorNode.sn.kind === "motion"
                      ? "#10B981"
                      : (sensorNode.sn.kind === "contact" ? "#F59E0B" : mapRoot.accentColor))))

              SensorGlyph {
                anchors.centerIn: parent
                width: Style.space(16)
                height: Style.space(16)
                sensorKind: String(sensorNode.sn.kind || "motion")
                tint: sensorNode.isActive ? "#0b111c" : "#f8fafc"
              }
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              hoverEnabled: true
              cursorShape: mapRoot.toolMode === "wire" ? Qt.CrossCursor : (pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor)
              property real startSX: 0
              property real startSY: 0
              property real origCX: 0
              property real origCY: 0
              property bool dragged: false
              property bool leftActive: false

              onEntered: { mapRoot.hoverLampId = ""; mapRoot.hoverSensorId = sensorNode.sn.id }
              onExited: {
                if (mapRoot.hoverSensorId === sensorNode.sn.id) mapRoot.hoverSensorId = ""
              }

              onPressed: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  leftActive = false
                  if (sensorNode.sn.kind === "motion" || sensorNode.sn.kind === "contact") {
                    mapRoot.sendCommand({ cmd: "sensor_toggle", kind: sensorNode.sn.kind, id: sensorNode.sn.id, enabled: sensorNode.sn.enabled === false })
                  }
                  mouse.accepted = true
                  return
                }
                leftActive = true
                var pt = mapToItem(viewport, mouse.x, mouse.y)
                startSX = pt.x; startSY = pt.y
                origCX = sensorNode.pos.x; origCY = sensorNode.pos.y
                dragged = false
                if (mapRoot.toolMode === "wire") {
                  mapRoot.wireFromKind = String(sensorNode.sn.kind || "motion")
                  mapRoot.wireFromId = sensorNode.sn.id
                  mapRoot.wireCursorX = sensorNode.pos.x
                  mapRoot.wireCursorY = sensorNode.pos.y
                  mapRoot.wireDragging = true
                  mapCanvas.requestPaint()
                } else {
                  mapRoot.selectItem("sensor", sensorNode.sn.id)
                }
              }
              onPositionChanged: function(mouse) {
                if (!leftActive || !pressed) return
                var pt = mapToItem(viewport, mouse.x, mouse.y)
                if (mapRoot.toolMode === "wire") {
                  mapRoot.wireCursorX = viewport.toCanvasX(pt.x)
                  mapRoot.wireCursorY = viewport.toCanvasY(pt.y)
                  mapCanvas.requestPaint()
                  return
                }
                if (!dragged && Math.hypot(pt.x - startSX, pt.y - startSY) < 4) return
                dragged = true
                mapRoot.isDragging = true
                var fp = mapRoot.cloneFp(mapRoot.workingFp)
                if (!fp.sensors || !fp.sensors[sensorNode.sn.id]) return
                fp.sensors[sensorNode.sn.id].x = Math.max(14, Math.min(mapRoot.canvasW - 14, mapRoot.snapVal(origCX + (pt.x - startSX) / viewport.scale)))
                fp.sensors[sensorNode.sn.id].y = Math.max(14, Math.min(mapRoot.canvasH - 14, mapRoot.snapVal(origCY + (pt.y - startSY) / viewport.scale)))
                mapRoot.workingFp = fp
                mapCanvas.requestPaint()
              }
              onReleased: function(mouse) {
                if (!leftActive) return
                leftActive = false
                if (mapRoot.toolMode === "wire") {
                  var pt = mapToItem(viewport, mouse.x, mouse.y)
                  var cx = viewport.toCanvasX(pt.x)
                  var cy = viewport.toCanvasY(pt.y)
                  var hitId = ""
                  var bestD = 28 / Math.max(0.15, viewport.scale)
                  var pl = mapRoot.floorPlacedLamps || []
                  for (var i = 0; i < pl.length; i++) {
                    var d = Math.hypot(pl[i].pos.x - cx, pl[i].pos.y - cy)
                    if (d < bestD) { bestD = d; hitId = pl[i].light.id }
                  }
                  mapRoot.wireDragging = false
                  if (hitId) {
                    mapRoot.openNewRuleDialog(mapRoot.wireFromKind, mapRoot.wireFromId, "light", hitId)
                  } else if (Math.hypot(pt.x - startSX, pt.y - startSY) > 20) {
                    mapRoot.wireFromKind = "light"
                    mapRoot.wireFromId = ""
                  }
                  mapCanvas.requestPaint()
                  return
                }
                if (dragged) {
                  mapRoot.isDragging = false
                  mapRoot.commitFp(mapRoot.workingFp, false)
                }
              }
            }
          }
        }

        // Layer 5C: Planned future fixtures (dashed blueprint nodes) + bendable LED strip vertices
        Repeater {
          model: mapRoot.activePlanned.length
          delegate: Item {
            id: planNode
            required property int index
            readonly property var entry: mapRoot.activePlanned[index] || ({ idx: -1, pl: ({ id: "", x: 0, y: 0, strip_points: [] }) })
            readonly property var pl: entry.pl || ({})
            readonly property bool isStrip: Array.isArray(pl.strip_points) && pl.strip_points.length >= 2
            readonly property var anchorPt: mapRoot.plannedAnchor(pl)
            readonly property bool isSel: mapRoot.selectedKind === "planned" && mapRoot.selectedId === pl.id
            readonly property bool isOn: pl.on !== false
            readonly property real nodeDiam: Style.space(isStrip ? 18 : 26)
            x: viewport.toScreenX(anchorPt.x) - nodeDiam * 0.5
            y: viewport.toScreenY(anchorPt.y) - nodeDiam * 0.5
            width: nodeDiam
            height: nodeDiam
            z: isSel ? 19 : 9

            Canvas {
              id: planRing
              anchors.fill: parent
              property bool sel: planNode.isSel
              property bool lit: planNode.isOn
              property color col: planNode.pl.color || "#ffd27a"
              onSelChanged: requestPaint()
              onLitChanged: requestPaint()
              onColChanged: requestPaint()
              onWidthChanged: requestPaint()
              onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = lit ? ("rgba(" + Math.round(col.r * 255) + "," + Math.round(col.g * 255) + "," + Math.round(col.b * 255) + ",0.28)") : "rgba(22,26,36,0.85)"
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, width / 2 - 1.5, 0, Math.PI * 2)
                ctx.fill()
                var ac = mapRoot.accentColor
                ctx.strokeStyle = sel ? ("rgb(" + Math.round(ac.r * 255) + "," + Math.round(ac.g * 255) + "," + Math.round(ac.b * 255) + ")") : "#38BDF8"
                ctx.lineWidth = sel ? 2.4 : 1.6
                ctx.setLineDash([3, 3])
                ctx.stroke()
              }
            }
            LampGlyph {
              anchors.centerIn: parent
              width: Style.space(planNode.isStrip ? 11 : 15)
              height: width
              iconName: String(planNode.pl.icon || "bulb")
              version: mapRoot.iconVersion
              tint: planNode.isOn ? "#ffffff" : mapRoot.dim
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.top
              anchors.bottomMargin: Style.space(1)
              textFormat: Text.PlainText
              text: Number(planNode.pl.lumens || 0) + " lm"
              color: planNode.isSel ? mapRoot.accentColor : "#38BDF8"
              font.family: mapRoot.fontFamily
              font.pixelSize: Math.max(8, Style.font.caption - 2)
            }

            MouseArea {
              anchors.fill: parent
              enabled: mapRoot.editMode
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
              property real sx: 0
              property real sy: 0
              property var orig: null
              property bool moved: false
              onPressed: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  mapRoot.editPlanned(String(planNode.pl.id || ""), function(p) { p.on = !(p.on !== false) })
                  return
                }
                var p = mapToItem(viewport, mouse.x, mouse.y)
                sx = p.x; sy = p.y
                orig = JSON.parse(JSON.stringify(planNode.pl))
                moved = false
                mapRoot.selectItem("planned", String(planNode.pl.id || ""))
              }
              onPositionChanged: function(mouse) {
                if (!pressed || !(pressedButtons & Qt.LeftButton) || !orig) return
                var p = mapToItem(viewport, mouse.x, mouse.y)
                if (!moved && Math.hypot(p.x - sx, p.y - sy) < 3) return
                moved = true
                mapRoot.isDragging = true
                var dx = (p.x - sx) / viewport.scale
                var dy = (p.y - sy) / viewport.scale
                var fp = mapRoot.cloneFp(mapRoot.workingFp)
                var tgt = fp.planned_lights[planNode.entry.idx]
                if (!tgt || tgt.id !== orig.id) return
                var an = mapRoot.plannedAnchor(orig)
                var nax = Math.max(0, Math.min(mapRoot.canvasW, mapRoot.snapVal(an.x + dx)))
                var nay = Math.max(0, Math.min(mapRoot.canvasH, mapRoot.snapVal(an.y + dy)))
                var adx = nax - an.x, ady = nay - an.y
                tgt.x = Math.round((Number(orig.x) + adx) * 10) / 10
                tgt.y = Math.round((Number(orig.y) + ady) * 10) / 10
                var osp = orig.strip_points || []
                tgt.strip_points = []
                for (var i = 0; i < osp.length; i++) {
                  tgt.strip_points.push({
                    x: Math.max(0, Math.min(mapRoot.canvasW, Math.round((osp[i].x + adx) * 10) / 10)),
                    y: Math.max(0, Math.min(mapRoot.canvasH, Math.round((osp[i].y + ady) * 10) / 10))
                  })
                }
                mapRoot.workingFp = fp
                mapCanvas.requestPaint()
              }
              onReleased: function(mouse) {
                if (mouse.button !== Qt.LeftButton || !moved) return
                mapRoot.isDragging = false
                mapRoot.commitFp(mapRoot.workingFp, false)
              }
            }
          }
        }

        // Strip vertices of planned LED lightstrips (drag to bend)
        Repeater {
          // Count-based model so a vertex keeps its delegate (and mouse grab) while it is dragged
          model: mapRoot.plannedStripVerts.length
          delegate: Rectangle {
            id: stripV
            required property int index
            readonly property var modelData: mapRoot.plannedStripVerts[index] || ({ idx: -1, pid: "", vi: 0, x: 0, y: 0 })
            width: Style.space(10)
            height: Style.space(10)
            radius: width * 0.5
            x: viewport.toScreenX(modelData.x) - width * 0.5
            y: viewport.toScreenY(modelData.y) - height * 0.5
            z: 18
            color: mapRoot.accentColor
            border.width: 1.2
            border.color: "#ffffff"
            MouseArea {
              anchors.fill: parent
              anchors.margins: -3
              enabled: mapRoot.editMode
              cursorShape: Qt.SizeAllCursor
              property real sx: 0
              property real sy: 0
              property real ox: 0
              property real oy: 0
              property bool moved: false
              onPressed: function(mouse) {
                var p = mapToItem(viewport, mouse.x, mouse.y)
                sx = p.x; sy = p.y
                ox = stripV.modelData.x; oy = stripV.modelData.y
                moved = false
                mapRoot.selectItem("planned", stripV.modelData.pid)
              }
              onPositionChanged: function(mouse) {
                if (!pressed) return
                var p = mapToItem(viewport, mouse.x, mouse.y)
                if (!moved && Math.hypot(p.x - sx, p.y - sy) < 3) return
                moved = true
                mapRoot.isDragging = true
                var fp = mapRoot.cloneFp(mapRoot.workingFp)
                var tgt = fp.planned_lights[stripV.modelData.idx]
                if (!tgt || tgt.id !== stripV.modelData.pid || !tgt.strip_points || stripV.modelData.vi >= tgt.strip_points.length) return
                tgt.strip_points[stripV.modelData.vi] = {
                  x: Math.max(0, Math.min(mapRoot.canvasW, mapRoot.snapVal(ox + (p.x - sx) / viewport.scale))),
                  y: Math.max(0, Math.min(mapRoot.canvasH, mapRoot.snapVal(oy + (p.y - sy) / viewport.scale)))
                }
                var an = mapRoot.plannedAnchor(tgt)
                tgt.x = Math.round(an.x * 10) / 10
                tgt.y = Math.round(an.y * 10) / 10
                mapRoot.workingFp = fp
                mapCanvas.requestPaint()
              }
              onReleased: {
                if (!moved) return
                mapRoot.isDragging = false
                mapRoot.commitFp(mapRoot.workingFp, false)
              }
            }
          }
        }

        // Layer 6: Floating Hover-Only Lamp Name Tooltip Pill (Name ONLY, flipped if near top, clamped inside canvas)
        Rectangle {
          id: lampHoverTip
          visible: viewport.hoverEntry !== null && !mapRoot.isDragging && mapRoot.activeDialog === ""
          z: 60
          readonly property real tipW: Math.min(viewport.width - 12, hoverTipTxt.implicitWidth + Style.space(14))
          readonly property real tipH: hoverTipTxt.implicitHeight + Style.space(6)
          readonly property real anchorSX: viewport.hoverEntry ? viewport.toScreenX(viewport.hoverEntry.pos.x) : 0
          readonly property real anchorSY: viewport.hoverEntry ? viewport.toScreenY(viewport.hoverEntry.pos.y) : 0
          readonly property real nodeHalf: Style.space(13)
          readonly property real aboveY: anchorSY - nodeHalf - tipH - 6

          x: Math.max(6, Math.min(viewport.width - tipW - 6, Math.round(anchorSX - tipW * 0.5)))
          y: aboveY >= 6 ? Math.round(aboveY) : Math.round(Math.min(viewport.height - tipH - 6, anchorSY + nodeHalf + 6))
          width: tipW
          height: tipH
          radius: Math.min(mapRoot.corners.pill, tipH * 0.5)
          color: Qt.rgba(10 / 255, 13 / 255, 20 / 255, 0.94)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.24)

          Text {
            id: hoverTipTxt
            anchors.centerIn: parent
            width: Math.min(implicitWidth, viewport.width - Style.space(26))
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: viewport.hoverEntry ? String(viewport.hoverEntry.name || "") : ""
            color: "#f8fafc"
            font.family: mapRoot.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
    }

    // =======================================================================
    // 3. COMPACT CONTEXTUAL INSPECTORS (ONLY ROOM/ZONE 3B & STAMP 3D)
    // =======================================================================

    // 3B. Compact Room / Zone Inspector + Scenes + Schedule Scene + Save Scene
    Rectangle {
      visible: mapRoot.selectedBox !== null
      width: parent.width
      height: boxInspCol.implicitHeight + Style.space(14)
      radius: mapRoot.corners.radius
      color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.05)
      border.width: 1
      border.color: Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.35)

      Column {
        id: boxInspCol
        x: Style.space(8); y: Style.space(7)
        width: parent.width - Style.space(16)
        spacing: Style.space(6)

        // Room / Zone toggle + Inline Rename
        Row {
          width: parent.width
          spacing: Style.space(5)
          Button {
            id: kindRoomBtn
            radius: mapRoot.corners.control; text: mapRoot.t("mapRoom"); bordered: true
            selected: mapRoot.selectedBox !== null && mapRoot.selectedBox.kind === "room"
            accent: mapRoot.accentColor; foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            enabled: mapRoot.selectedBox !== null && !mapRoot.selectedBox.hue_id
            onClicked: {
              var fp = mapRoot.cloneFp(mapRoot.workingFp)
              for (var i = 0; i < fp.boxes.length; i++) if (fp.boxes[i].id === mapRoot.selectedId) { fp.boxes[i].kind = "room"; break }
              mapRoot.commitFp(fp, false)
            }
          }
          Button {
            id: kindZoneBtn
            radius: mapRoot.corners.control; text: mapRoot.t("zone"); bordered: true
            selected: mapRoot.selectedBox !== null && mapRoot.selectedBox.kind === "zone"
            accent: mapRoot.accentColor; foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            enabled: mapRoot.selectedBox !== null && !mapRoot.selectedBox.hue_id
            onClicked: {
              var fp = mapRoot.cloneFp(mapRoot.workingFp)
              for (var i = 0; i < fp.boxes.length; i++) if (fp.boxes[i].id === mapRoot.selectedId) { fp.boxes[i].kind = "zone"; break }
              mapRoot.commitFp(fp, false)
            }
          }
          KeyTextField {
            id: roomRenameField
            width: Math.max(Style.space(80), parent.width - kindRoomBtn.width - kindZoneBtn.width - roomRenameBtn.width - Style.space(15))
            radius: mapRoot.corners.control
            maximumLength: 32
            font: Qt.font({ family: mapRoot.fontFamily, pixelSize: Style.font.caption })
            placeholderText: mapRoot.t("mapRenamePlaceholder")
            foreground: mapRoot.fg
            accent: mapRoot.accentColor
            onAccepted: boxInspCol.applyRoomRename()
          }
          Button {
            id: roomRenameBtn
            radius: mapRoot.corners.control
            text: mapRoot.t("mapRename")
            bordered: true
            foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            enabled: mapRoot.selectedBox !== null && roomRenameField.text.trim().length > 0
            onClicked: boxInspCol.applyRoomRename()
          }
        }

        function applyRoomRename() {
          if (!mapRoot.selectedBox) return
          var nm = roomRenameField.text.trim()
          if (!nm) return
          var fp = mapRoot.cloneFp(mapRoot.workingFp)
          for (var i = 0; i < fp.boxes.length; i++) {
            if (fp.boxes[i].id === mapRoot.selectedId) { fp.boxes[i].name = nm; break }
          }
          mapRoot.commitFp(fp, false)
          if (mapRoot.selectedBox.hue_id) {
            mapRoot.sendCommand({ cmd: "room_update", id: mapRoot.selectedBox.hue_id, kind: mapRoot.selectedBox.kind, name: nm })
          }
        }

        // Room shape starters (rooms only) + floor assignment
        Flow {
          visible: mapRoot.selectedBox !== null
          width: parent.width
          spacing: Style.space(4)
          Text {
            height: Style.space(22)
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: mapRoot.t("fpRoomShape")
            color: mapRoot.dim
            font.family: mapRoot.fontFamily
            font.pixelSize: Style.font.caption
          }
          Repeater {
            model: mapRoot.roomShapeList
            delegate: Button {
              required property var modelData
              radius: mapRoot.corners.control
              text: mapRoot.t(modelData.key)
              bordered: true
              selected: mapRoot.selectedBox !== null && mapRoot.shapeIdOf(mapRoot.selectedBox) === modelData.id
              accent: mapRoot.accentColor
              foreground: mapRoot.fg
              fontFamily: mapRoot.fontFamily
              fontSize: Math.max(9, Style.font.caption - 1)
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(1)
              onClicked: if (mapRoot.selectedBox) mapRoot.boxApplyShape(mapRoot.selectedBox.id, modelData.id)
            }
          }
        }
        Text {
          visible: mapRoot.selectedBox !== null && mapRoot.isPolygon(mapRoot.selectedBox)
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: mapRoot.t("fpShapeHint")
          color: mapRoot.dim
          font.family: mapRoot.fontFamily
          font.pixelSize: Math.max(9, Style.font.caption - 1)
        }
        Flow {
          visible: mapRoot.selectedBox !== null && mapRoot.fpFloors.length > 1
          width: parent.width
          spacing: Style.space(4)
          Text {
            height: Style.space(22)
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: mapRoot.t("fpFloor")
            color: mapRoot.dim
            font.family: mapRoot.fontFamily
            font.pixelSize: Style.font.caption
          }
          Repeater {
            model: mapRoot.fpFloors
            delegate: Button {
              required property var modelData
              radius: mapRoot.corners.control
              text: mapRoot.floorLabel(modelData.name)
              bordered: true
              selected: mapRoot.selectedBox !== null && mapRoot.floorOf(mapRoot.selectedBox) === String(modelData.id)
              accent: mapRoot.accentColor
              foreground: mapRoot.fg
              fontFamily: mapRoot.fontFamily
              fontSize: Math.max(9, Style.font.caption - 1)
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(1)
              onClicked: if (mapRoot.selectedBox) mapRoot.boxSetFloor(mapRoot.selectedBox.id, String(modelData.id))
            }
          }
        }

        // Archetype + optional Entertainment link + Remove / Delete on Bridge
        Flow {
          width: parent.width
          spacing: Style.space(6)
          CompactDropdown {
            id: boxArchPicker
            width: Style.space(132)
            popupRadius: mapRoot.corners.radius
            controlRadius: mapRoot.corners.control
            fontSize: Style.font.caption
            rowHeight: Style.space(24)
            popupRowHeight: Style.space(26)
            showLabel: false
            fontFamily: mapRoot.fontFamily
            accent: mapRoot.accentColor
            options: mapRoot.archetypeOptions
            value: mapRoot.validOption(mapRoot.archetypeOptions, mapRoot.selectedBox ? String(mapRoot.selectedBox.archetype || "other") : "other", 0)
            onChanged: function(v) {
              if (!mapRoot.selectedBox) return
              var fp = mapRoot.cloneFp(mapRoot.workingFp)
              for (var i = 0; i < fp.boxes.length; i++) if (fp.boxes[i].id === mapRoot.selectedId) { fp.boxes[i].archetype = v; break }
              mapRoot.commitFp(fp, false)
              if (mapRoot.selectedBox.hue_id) {
                mapRoot.sendCommand({ cmd: "room_update", id: mapRoot.selectedBox.hue_id, kind: mapRoot.selectedBox.kind, archetype: v })
              }
              boxArchPicker.value = Qt.binding(function() {
                return mapRoot.validOption(mapRoot.archetypeOptions, mapRoot.selectedBox ? String(mapRoot.selectedBox.archetype || "other") : "other", 0)
              })
            }
          }

          CompactDropdown {
            id: boxEntPicker
            visible: (mapRoot.entertainmentAreas || []).length > 0
            width: Style.space(120)
            popupRadius: mapRoot.corners.radius
            controlRadius: mapRoot.corners.control
            fontSize: Style.font.caption
            rowHeight: Style.space(24)
            popupRowHeight: Style.space(26)
            showLabel: false
            fontFamily: mapRoot.fontFamily
            accent: mapRoot.accentColor
            options: mapRoot.entertainmentOptions
            value: mapRoot.validOption(mapRoot.entertainmentOptions, mapRoot.selectedBox ? String(mapRoot.selectedBox.entertainment_area_id || "") : "", 0)
            onChanged: function(v) {
              if (!mapRoot.selectedBox) return
              var fp = mapRoot.cloneFp(mapRoot.workingFp)
              for (var i = 0; i < fp.boxes.length; i++) if (fp.boxes[i].id === mapRoot.selectedId) { fp.boxes[i].entertainment_area_id = v ? v : null; break }
              mapRoot.commitFp(fp, false)
              boxEntPicker.value = Qt.binding(function() {
                return mapRoot.validOption(mapRoot.entertainmentOptions, mapRoot.selectedBox ? String(mapRoot.selectedBox.entertainment_area_id || "") : "", 0)
              })
            }
          }

          Button {
            visible: mapRoot.selectedBox !== null && Boolean(mapRoot.selectedBox.entertainment_area_id)
            radius: mapRoot.corners.control
            text: mapRoot.t("mapSyncEnt")
            bordered: true; foreground: mapRoot.fg; fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: mapRoot.sendCommand({ cmd: "entertainment_sync", area_id: mapRoot.selectedBox.entertainment_area_id, box_id: mapRoot.selectedBox.id })
          }

          Button {
            radius: mapRoot.corners.control
            text: mapRoot.t("mapRemoveBox")
            bordered: true; foreground: mapRoot.dim; fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: {
              var fp = mapRoot.cloneFp(mapRoot.workingFp)
              fp.boxes = (fp.boxes || []).filter(function(b) { return b.id !== mapRoot.selectedId })
              mapRoot.selectedKind = ""
              mapRoot.selectedId = ""
              mapRoot.commitFp(fp, false)
            }
          }

          Button {
            visible: mapRoot.selectedBox !== null && Boolean(mapRoot.selectedBox.hue_id)
            radius: mapRoot.corners.control
            text: mapRoot.confirmBridgeDelete ? mapRoot.t("mapConfirmDeleteBridge") : mapRoot.t("mapDeleteBridge")
            bordered: true
            foreground: Commons.Color.urgent
            fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: {
              if (!mapRoot.confirmBridgeDelete) {
                mapRoot.confirmBridgeDelete = true
                return
              }
              var bx = mapRoot.selectedBox
              mapRoot.sendCommand({ cmd: "room_delete", id: bx.hue_id, kind: bx.kind })
              var fp = mapRoot.cloneFp(mapRoot.workingFp)
              fp.boxes = (fp.boxes || []).filter(function(b) { return b.id !== bx.id })
              mapRoot.confirmBridgeDelete = false
              mapRoot.selectedKind = ""
              mapRoot.selectedId = ""
              mapRoot.commitFp(fp, false)
            }
          }
        }

        Text {
          visible: mapRoot.selectedBox !== null && !mapRoot.selectedBox.hue_id
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: mapRoot.t("mapUnlinkedRoom")
          color: mapRoot.dim
          font.family: mapRoot.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Compact Bridge Pro MotionAware™ control row (ONLY when this room has a linked MotionAware area)
        Rectangle {
          visible: mapRoot.selectedRoomMotionArea !== null
          width: parent.width
          height: maRowWrap.implicitHeight + Style.space(10)
          radius: mapRoot.corners.control
          color: (mapRoot.selectedRoomMotionArea && mapRoot.selectedRoomMotionArea.enabled && mapRoot.selectedRoomMotionArea.motion)
            ? Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.14)
            : Qt.rgba(6 / 255, 182 / 255, 212 / 255, 0.08)
          border.width: 1
          border.color: (mapRoot.selectedRoomMotionArea && mapRoot.selectedRoomMotionArea.enabled && mapRoot.selectedRoomMotionArea.motion)
            ? Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.55)
            : Qt.rgba(6 / 255, 182 / 255, 212 / 255, 0.30)

          Item {
            id: maRowWrap
            x: Style.space(8); y: Style.space(5)
            width: parent.width - Style.space(16)
            implicitHeight: Math.max(maLeftRow.implicitHeight, maRightRow.implicitHeight)
            height: implicitHeight

            Row {
              id: maLeftRow
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              SensorGlyph {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(13); height: Style.space(13)
                sensorKind: "motion"
                tint: (mapRoot.selectedRoomMotionArea && mapRoot.selectedRoomMotionArea.enabled && mapRoot.selectedRoomMotionArea.motion) ? "#10B981" : "#06B6D4"
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: mapRoot.t("motionAwareTitle")
                color: mapRoot.fg
                font.family: mapRoot.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: {
                  var a = mapRoot.selectedRoomMotionArea
                  if (!a) return ""
                  if (!a.enabled) return mapRoot.t("motionDisabled")
                  return a.motion ? mapRoot.t("motionDetected") : mapRoot.t("motionClear")
                }
                color: {
                  var a = mapRoot.selectedRoomMotionArea
                  if (!a || !a.enabled) return mapRoot.dim
                  return a.motion ? "#10B981" : "#06B6D4"
                }
                font.family: mapRoot.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: mapRoot.selectedRoomMotionArea !== null && mapRoot.selectedRoomMotionArea.enabled && mapRoot.selectedRoomMotionArea.motion
              }
            }

            Row {
              id: maRightRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              // Sensitivity - / + stepper
              Row {
                visible: mapRoot.selectedRoomMotionArea !== null && String(mapRoot.selectedRoomMotionArea.convenience_id || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: mapRoot.t("motionSensitivity")
                  color: mapRoot.dim
                  font.family: mapRoot.fontFamily
                  font.pixelSize: Math.max(9, Style.font.caption - 1)
                }
                Button {
                  radius: mapRoot.corners.small
                  text: "−"
                  bordered: true
                  foreground: mapRoot.fg
                  fontFamily: mapRoot.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(1)
                  enabled: mapRoot.selectedRoomMotionArea !== null && Number(mapRoot.selectedRoomMotionArea.sensitivity || 0) > 0
                  onClicked: {
                    var a = mapRoot.selectedRoomMotionArea
                    if (!a) return
                    mapRoot.sendCommand({ cmd: "motion_area_update", id: a.id, sensitivity: Math.max(0, Number(a.sensitivity || 0) - 1) })
                  }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: mapRoot.selectedRoomMotionArea ? (String(mapRoot.selectedRoomMotionArea.sensitivity) + "/" + String(mapRoot.selectedRoomMotionArea.sensitivity_max || 4)) : ""
                  color: mapRoot.fg
                  font.family: mapRoot.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Button {
                  radius: mapRoot.corners.small
                  text: "+"
                  bordered: true
                  foreground: mapRoot.fg
                  fontFamily: mapRoot.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(1)
                  enabled: mapRoot.selectedRoomMotionArea !== null && Number(mapRoot.selectedRoomMotionArea.sensitivity || 0) < Number(mapRoot.selectedRoomMotionArea.sensitivity_max || 4)
                  onClicked: {
                    var a = mapRoot.selectedRoomMotionArea
                    if (!a) return
                    var smax = Number(a.sensitivity_max || 4)
                    mapRoot.sendCommand({ cmd: "motion_area_update", id: a.id, sensitivity: Math.min(smax, Number(a.sensitivity || 0) + 1) })
                  }
                }
              }

              ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                cursorRing: false
                rounded: mapRoot.corners.pill > 0
                trackHeight: Style.space(16)
                checked: mapRoot.selectedRoomMotionArea !== null && mapRoot.selectedRoomMotionArea.enabled === true
                foreground: mapRoot.fg
                accent: "#10B981"
                onToggled: {
                  var a = mapRoot.selectedRoomMotionArea
                  if (a) mapRoot.sendCommand({ cmd: "motion_area_update", id: a.id, enabled: a.enabled !== true })
                }
              }
            }
          }
        }

        // Scenes for this Room / Zone
        Column {
          visible: mapRoot.selectedHueRoom !== null
          width: parent.width
          spacing: Style.space(5)

          Text {
            textFormat: Text.PlainText
            text: mapRoot.t("mapScenes").toUpperCase()
            color: mapRoot.dim
            font.family: mapRoot.fontFamily
            font.pixelSize: Math.max(9, Style.font.caption - 1)
            font.bold: true
          }

          Flow {
            visible: mapRoot.selectedHueRoom !== null && (mapRoot.selectedHueRoom.scenes || []).length > 0
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: mapRoot.selectedHueRoom ? (mapRoot.selectedHueRoom.scenes || []).length : 0
              delegate: Rectangle {
                id: scPill
                required property int index
                readonly property var sc: (mapRoot.selectedHueRoom && mapRoot.selectedHueRoom.scenes && mapRoot.selectedHueRoom.scenes[index]) || ({ id: "", name: "" })
                width: scRow.implicitWidth + Style.space(8)
                height: Style.space(22)
                radius: mapRoot.corners.control
                color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.07)
                border.width: 1
                border.color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.16)

                Row {
                  id: scRow
                  anchors.centerIn: parent
                  spacing: Style.space(4)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: String(scPill.sc.name || "")
                    color: scRecallMouse.containsMouse ? mapRoot.accentColor : mapRoot.fg
                    font.family: mapRoot.fontFamily
                    font.pixelSize: Style.font.caption
                    MouseArea {
                      id: scRecallMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: mapRoot.sendCommand({ cmd: "scene", id: scPill.sc.id })
                    }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "⏰"
                    color: scSchedMouse.containsMouse ? "#F59E0B" : mapRoot.dim
                    font.family: mapRoot.fontFamily
                    font.pixelSize: Style.font.caption
                    MouseArea {
                      id: scSchedMouse
                      anchors.fill: parent
                      anchors.margins: -Style.space(2)
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (mapRoot.selectedBox && mapRoot.selectedBox.hue_id) {
                          mapRoot.scheduleSceneRequested(mapRoot.selectedBox.kind, mapRoot.selectedBox.hue_id, scPill.sc.id, scPill.sc.name)
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: mapRoot.selectedHueRoom !== null && (mapRoot.selectedHueRoom.scenes || []).length === 0
            textFormat: Text.PlainText
            text: mapRoot.t("mapNoScenes")
            color: mapRoot.dim
            font.family: mapRoot.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            KeyTextField {
              id: sceneNameField
              width: parent.width - saveSceneBtn.width - Style.space(6)
              radius: mapRoot.corners.control
              maximumLength: 32
              font: Qt.font({ family: mapRoot.fontFamily, pixelSize: Style.font.caption })
              placeholderText: mapRoot.t("mapSaveScenePlaceholder")
              foreground: mapRoot.fg
              accent: mapRoot.accentColor
              onAccepted: {
                if (mapRoot.selectedBox && mapRoot.selectedBox.hue_id && text.trim().length > 0) {
                  mapRoot.sendCommand({ cmd: "scene_create", room_id: mapRoot.selectedBox.hue_id, name: text.trim() })
                  clear()
                }
              }
            }
            Button {
              id: saveSceneBtn
              radius: mapRoot.corners.control
              text: mapRoot.t("mapSaveScene")
              bordered: true
              foreground: mapRoot.fg
              fontFamily: mapRoot.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8); verticalPadding: Style.space(2)
              enabled: mapRoot.selectedBox !== null && Boolean(mapRoot.selectedBox.hue_id) && sceneNameField.text.trim().length > 0
              onClicked: {
                mapRoot.sendCommand({ cmd: "scene_create", room_id: mapRoot.selectedBox.hue_id, name: sceneNameField.text.trim() })
                sceneNameField.clear()
              }
            }
          }
        }
      }
    }

    // 3C. Planned fixture inspector (Future Lighting Planner)
    Rectangle {
      id: planInsp
      visible: mapRoot.selectedPlanned !== null
      width: parent.width
      height: planInspCol.implicitHeight + Style.space(14)
      radius: mapRoot.corners.radius
      color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.05)
      border.width: 1
      border.color: Qt.rgba(56 / 255, 189 / 255, 248 / 255, 0.45)

      readonly property var pl: mapRoot.selectedPlanned || ({ id: "", name: "", lumens: 0, kelvin: 2700, beam_radius: 2.6, on: true, price: 0 })
      readonly property string pid: String(pl.id || "")

      Column {
        id: planInspCol
        x: Style.space(8); y: Style.space(7)
        width: parent.width - Style.space(16)
        spacing: Style.space(6)

        Item {
          width: parent.width
          height: Math.max(planInspTitle.implicitHeight, planInspBtns.height)
          Text {
            id: planInspTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - planInspBtns.width - Style.space(8)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: "✦ " + String(planInsp.pl.name || "") + " (" + Number(planInsp.pl.lumens || 0) + " lm · " + Number(planInsp.pl.kelvin || 0) + " K)"
            color: mapRoot.fg
            font.family: mapRoot.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Row {
            id: planInspBtns
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(5)
            Button {
              radius: mapRoot.corners.control
              text: planInsp.pl.on !== false ? mapRoot.t("fpOn") : mapRoot.t("fpOff")
              bordered: true
              selected: planInsp.pl.on !== false
              accent: mapRoot.accentColor
              foreground: mapRoot.fg
              fontFamily: mapRoot.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
              onClicked: mapRoot.editPlanned(planInsp.pid, function(p) { p.on = !(p.on !== false) })
            }
            Button {
              radius: mapRoot.corners.control
              iconText: "󰩺"
              text: mapRoot.t("fpDelete")
              bordered: true
              foreground: Commons.Color.urgent
              fontFamily: mapRoot.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
              onClicked: mapRoot.deletePlanned(planInsp.pid)
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(5)
          KeyTextField {
            id: plannedNameField
            width: Math.max(Style.space(80), parent.width - planRenameBtn.width - plannedPriceField.width - planPriceBtn.width - Style.space(15))
            radius: mapRoot.corners.control
            maximumLength: 40
            font: Qt.font({ family: mapRoot.fontFamily, pixelSize: Style.font.caption })
            placeholderText: mapRoot.t("fpPlannedLight")
            foreground: mapRoot.fg
            accent: mapRoot.accentColor
            onAccepted: planRenameBtn.clicked()
          }
          Button {
            id: planRenameBtn
            radius: mapRoot.corners.control
            text: mapRoot.t("fpRename")
            bordered: true
            foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            enabled: plannedNameField.text.trim().length > 0
            onClicked: {
              var nm = plannedNameField.text.replace(/[<>&]/g, "").trim().slice(0, 40)
              if (nm) mapRoot.editPlanned(planInsp.pid, function(p) { p.name = nm })
            }
          }
          KeyTextField {
            id: plannedPriceField
            width: Style.space(64)
            radius: mapRoot.corners.control
            maximumLength: 9
            font: Qt.font({ family: mapRoot.fontFamily, pixelSize: Style.font.caption })
            placeholderText: mapRoot.t("fpEstPrice")
            foreground: mapRoot.fg
            accent: mapRoot.accentColor
            onAccepted: planPriceBtn.clicked()
          }
          Button {
            id: planPriceBtn
            radius: mapRoot.corners.control
            text: mapRoot.t("fpSave")
            bordered: true
            foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: {
              var v = parseFloat(plannedPriceField.text.trim().replace(",", "."))
              if (isFinite(v)) mapRoot.editPlanned(planInsp.pid, function(p) { p.price = Math.round(Math.max(0, Math.min(99999, v)) * 100) / 100 })
            }
          }
        }

        // Lumens / Kelvin / Beam steppers (same steps and limits as Maprisma Lights)
        Flow {
          width: parent.width
          spacing: Style.space(10)
          Repeater {
            model: [
              { key: "fpLumens", unit: "lm", field: "lumens", step: 150, min: 150, max: 6000, dec: 0 },
              { key: "fpKelvin", unit: "K", field: "kelvin", step: 300, min: 2000, max: 6500, dec: 0 },
              { key: "fpBeam", unit: "m", field: "beam_radius", step: 0.4, min: 1.0, max: 6.0, dec: 1 }
            ]
            delegate: Row {
              id: stepRow
              required property var modelData
              readonly property real cur: Number(planInsp.pl[modelData.field] || 0)
              spacing: Style.space(4)
              function setTo(v) {
                var f = stepRow.modelData
                var nv = Math.max(f.min, Math.min(f.max, v))
                nv = f.dec > 0 ? Math.round(nv * 10) / 10 : Math.round(nv)
                mapRoot.editPlanned(planInsp.pid, function(p) {
                  p[f.field] = nv
                  if (f.field === "kelvin") p.color = mapRoot.kelvinToHex(nv)
                })
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: mapRoot.t(stepRow.modelData.key)
                color: mapRoot.dim
                font.family: mapRoot.fontFamily
                font.pixelSize: Style.font.caption
              }
              Button {
                radius: mapRoot.corners.control
                text: "−"
                bordered: true
                foreground: mapRoot.fg
                fontFamily: mapRoot.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6); verticalPadding: Style.space(1)
                onClicked: stepRow.setTo(stepRow.cur - stepRow.modelData.step)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: stepRow.cur.toFixed(stepRow.modelData.dec) + " " + stepRow.modelData.unit
                color: mapRoot.fg
                font.family: mapRoot.fontFamily
                font.pixelSize: Style.font.caption
              }
              Button {
                radius: mapRoot.corners.control
                text: "+"
                bordered: true
                foreground: mapRoot.fg
                fontFamily: mapRoot.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6); verticalPadding: Style.space(1)
                onClicked: stepRow.setTo(stepRow.cur + stepRow.modelData.step)
              }
            }
          }
        }

        // Replace with a real paired light (any provider)
        Rectangle {
          visible: mapRoot.allLights.length > 0
          width: parent.width; height: 1
          color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.12)
        }
        Text {
          visible: mapRoot.allLights.length > 0
          textFormat: Text.PlainText
          text: mapRoot.t("fpBindReal")
          color: mapRoot.dim
          font.family: mapRoot.fontFamily
          font.pixelSize: Style.font.caption
        }
        Flow {
          visible: mapRoot.allLights.length > 0
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: Math.min(12, mapRoot.allLights.length)
            delegate: Button {
              required property int index
              readonly property var lt: mapRoot.allLights[index] || ({ id: "", name: "" })
              radius: mapRoot.corners.control
              text: String(lt.name || "")
              bordered: true
              foreground: mapRoot.fg
              fontFamily: mapRoot.fontFamily
              fontSize: Math.max(9, Style.font.caption - 1)
              horizontalPadding: Style.space(6); verticalPadding: Style.space(1)
              onClicked: mapRoot.bindPlannedToReal(planInsp.pid, String(lt.id))
            }
          }
        }
      }
    }

    // 3D. Compact Stamp Inspector (Rotate 90° / Delete)
    Rectangle {
      visible: mapRoot.selectedStamp !== null
      width: parent.width
      height: stampInspRow.implicitHeight + Style.space(12)
      radius: mapRoot.corners.radius
      color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.05)
      border.width: 1
      border.color: mapRoot.cardBorderColor

      Row {
        id: stampInspRow
        x: Style.space(8); y: Style.space(6)
        spacing: Style.space(8)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: mapRoot.selectedStamp ? (mapRoot.stampLabel(mapRoot.selectedStamp.kind) + " · " + String(mapRoot.selectedStamp.rot || 0) + "°") : ""
          color: mapRoot.fg
          font.family: mapRoot.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Button {
          radius: mapRoot.corners.control
          iconText: "󰑓"
          text: mapRoot.t("mapRotate90")
          bordered: true
          foreground: mapRoot.fg
          fontFamily: mapRoot.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
          onClicked: {
            var fp = mapRoot.cloneFp(mapRoot.workingFp)
            for (var i = 0; i < fp.stamps.length; i++) {
              if (fp.stamps[i].id === mapRoot.selectedId) {
                fp.stamps[i].rot = (Number(fp.stamps[i].rot || 0) + 90) % 360
                break
              }
            }
            mapRoot.commitFp(fp, false)
          }
        }
        Button {
          radius: mapRoot.corners.control
          iconText: "󰩺"
          text: mapRoot.t("deleteTip")
          bordered: true
          foreground: Commons.Color.urgent
          fontFamily: mapRoot.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
          onClicked: {
            var fp = mapRoot.cloneFp(mapRoot.workingFp)
            fp.stamps = (fp.stamps || []).filter(function(s) { return s.id !== mapRoot.selectedId })
            mapRoot.selectedKind = ""
            mapRoot.selectedId = ""
            mapRoot.commitFp(fp, false)
          }
        }
      }
    }

    // 3E. Compact 1-Line Wire Color Legend (only when wires are visible and no box/stamp inspector is open)
    Flow {
      visible: mapRoot.wiresVisible && mapRoot.selectedBox === null && mapRoot.selectedStamp === null && mapRoot.selectedPlanned === null
      width: parent.width
      spacing: Style.space(10)

      Repeater {
        model: [
          { col: "#38BDF8", sym: "──▶", key: "ruleFollow" },
          { col: "#22D3EE", sym: "◀─▶", key: "mapWireMirror" },
          { col: "#F43F5E", sym: "- -┤", key: "ruleExclusive" },
          { col: "#F59E0B", sym: "···◇", key: "ruleCompanion" },
          { col: "#D946EF", sym: "◯",   key: "mapWireLegendSynth" }
        ]
        delegate: Row {
          id: legendItem
          required property var modelData
          spacing: Style.space(3)
          Text {
            textFormat: Text.PlainText
            text: legendItem.modelData.sym
            color: legendItem.modelData.col
            font.family: mapRoot.fontFamily
            font.pixelSize: Math.max(9, Style.font.caption - 1)
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            text: mapRoot.t(legendItem.modelData.key)
            color: mapRoot.dim
            font.family: mapRoot.fontFamily
            font.pixelSize: Math.max(9, Style.font.caption - 1)
          }
        }
      }
    }
  }

  // =========================================================================
  // 4. FOCUSED CENTERED MODAL DIALOGS (Brightness / Rename / Lamp Icon / Rule)
  // =========================================================================
  Item {
    id: modalOverlay
    anchors.fill: parent
    visible: mapRoot.activeDialog !== ""
    z: 100

    Keys.onEscapePressed: function(ev) {
      mapRoot.closeDialog()
      ev.accepted = true
    }

    // Scrim (clicks outside close dialog)
    Rectangle {
      anchors.fill: parent
      radius: mapRoot.corners.radius
      color: Qt.rgba(0, 0, 0, 0.56)
      MouseArea {
        anchors.fill: parent
        onClicked: mapRoot.closeDialog()
      }
    }

    // ---- 4A. BRIGHTNESS MODAL DIALOG ----
    Rectangle {
      visible: mapRoot.activeDialog === "brightness"
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(20), Style.space(310))
      height: briDlgCol.implicitHeight + Style.space(24)
      radius: mapRoot.corners.radius
      color: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 0.97)
      border.width: 1
      border.color: Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.45)

      MouseArea { anchors.fill: parent } // swallow background clicks

      Column {
        id: briDlgCol
        x: Style.space(12); y: Style.space(12)
        width: parent.width - Style.space(24)
        spacing: Style.space(12)

        // Header: colored icon badge + lamp name + on/off switch
        Item {
          width: parent.width
          height: Math.max(Style.space(26), briSwitch.implicitHeight)
          Row {
            anchors.left: parent.left
            anchors.right: briSwitch.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(24); height: Style.space(24); radius: width * 0.5
              color: (mapRoot.dialogLight && mapRoot.dialogLight.on) ? (mapRoot.dialogLight.color || "#ffd27a") : Qt.rgba(22 / 255, 26 / 255, 36 / 255, 0.92)
              border.width: 1.2
              border.color: (mapRoot.dialogLight && mapRoot.dialogLight.on) ? "#ffffff" : Qt.rgba(1, 1, 1, 0.32)
              LampGlyph {
                anchors.centerIn: parent
                width: Style.space(14); height: Style.space(14)
                iconName: mapRoot.lampIconFor(mapRoot.dialogLampId)
                version: mapRoot.iconVersion
                tint: mapRoot.contrastTintForLight(mapRoot.dialogLight)
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(32)
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: mapRoot.dialogLight ? String(mapRoot.dialogLight.name || "") : ""
              color: mapRoot.fg
              font.family: mapRoot.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }
          ToggleSwitch {
            id: briSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            cursorRing: false
            rounded: mapRoot.corners.pill > 0
            trackHeight: Style.space(18)
            checked: mapRoot.dialogLight ? mapRoot.dialogLight.on : false
            foreground: mapRoot.fg
            accent: mapRoot.accentColor
            onToggled: if (mapRoot.dialogLight) mapRoot.sendCommand({ cmd: "light", id: mapRoot.dialogLight.id, on: !mapRoot.dialogLight.on })
          }
        }

        // Brightness slider
        Item {
          width: parent.width
          height: Math.max(dlgBriLbl.implicitHeight, dlgBriSlider.implicitHeight)
          Text {
            id: dlgBriLbl
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            width: Style.space(66)
            textFormat: Text.PlainText
            text: mapRoot.t("brightness")
            color: mapRoot.dim
            font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
          }
          PanelSlider {
            id: dlgBriSlider
            anchors.left: dlgBriLbl.right; anchors.leftMargin: Style.space(6)
            anchors.right: dlgBriPct.left; anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            bar: mapRoot.bar
            minimum: 1; maximum: 100; step: 1
            fillColor: (mapRoot.dialogLight && mapRoot.dialogLight.on) ? (mapRoot.dialogLight.color || mapRoot.accentColor) : mapRoot.accentColor
            value: mapRoot.dialogLight ? Math.max(1, Math.round(mapRoot.dialogLight.bri)) : 50
            onMoved: function(v) {
              if (mapRoot.dialogLight) mapRoot.sendCommand({ cmd: "light", id: mapRoot.dialogLight.id, on: true, bri: Math.round(v) })
            }
          }
          Text {
            id: dlgBriPct
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: Style.space(34); horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: Math.round(dlgBriSlider.liveValue) + "%"
            color: mapRoot.fg
            font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
          }
        }

        // Footer: Done
        Item {
          width: parent.width
          height: briDoneBtn.implicitHeight
          Button {
            id: briDoneBtn
            anchors.right: parent.right
            radius: mapRoot.corners.control
            text: mapRoot.t("shotDone")
            bordered: true
            selected: true
            accent: mapRoot.accentColor
            foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(12); verticalPadding: Style.space(3)
            onClicked: mapRoot.closeDialog()
          }
        }
      }
    }

    // ---- 4B. RENAME MODAL DIALOG ----
    Rectangle {
      visible: mapRoot.activeDialog === "rename"
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(20), Style.space(300))
      height: renDlgCol.implicitHeight + Style.space(24)
      radius: mapRoot.corners.radius
      color: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 0.97)
      border.width: 1
      border.color: Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.45)

      MouseArea { anchors.fill: parent }

      Column {
        id: renDlgCol
        x: Style.space(12); y: Style.space(12)
        width: parent.width - Style.space(24)
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: mapRoot.t("mapRename")
          color: mapRoot.fg
          font.family: mapRoot.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        KeyTextField {
          id: lampRenameField
          width: parent.width
          radius: mapRoot.corners.control
          maximumLength: 32
          font: Qt.font({ family: mapRoot.fontFamily, pixelSize: Style.font.caption })
          placeholderText: mapRoot.t("mapRenamePlaceholder")
          foreground: mapRoot.fg
          accent: mapRoot.accentColor
          Keys.onEscapePressed: mapRoot.closeDialog()
          onAccepted: {
            if (mapRoot.dialogLampId && text.trim().length > 0) {
              mapRoot.sendCommand({ cmd: "light_rename", id: mapRoot.dialogLampId, name: text.trim() })
              mapRoot.closeDialog()
            }
          }
        }

        Item {
          width: parent.width
          height: renBtnRow.implicitHeight
          Row {
            id: renBtnRow
            anchors.right: parent.right
            spacing: Style.space(6)
            Button {
              radius: mapRoot.corners.control
              text: mapRoot.t("cancel")
              bordered: true
              foreground: mapRoot.dim
              fontFamily: mapRoot.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(10); verticalPadding: Style.space(3)
              onClicked: mapRoot.closeDialog()
            }
            Button {
              radius: mapRoot.corners.control
              text: mapRoot.t("mapRename")
              bordered: true
              selected: true
              accent: mapRoot.accentColor
              foreground: mapRoot.fg
              fontFamily: mapRoot.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(10); verticalPadding: Style.space(3)
              enabled: mapRoot.dialogLampId !== "" && lampRenameField.text.trim().length > 0
              onClicked: {
                mapRoot.sendCommand({ cmd: "light_rename", id: mapRoot.dialogLampId, name: lampRenameField.text.trim() })
                mapRoot.closeDialog()
              }
            }
          }
        }
      }
    }

    // ---- 4C. LAMP ICON MODAL DIALOG (Live preview badge + 12 bold vector icons) ----
    Rectangle {
      visible: mapRoot.activeDialog === "icon"
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(20), Style.space(336))
      height: iconDlgCol.implicitHeight + Style.space(24)
      radius: mapRoot.corners.radius
      color: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 0.97)
      border.width: 1
      border.color: Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.45)

      MouseArea { anchors.fill: parent }

      Column {
        id: iconDlgCol
        x: Style.space(12); y: Style.space(12)
        width: parent.width - Style.space(24)
        spacing: Style.space(10)

        // Header with live colored icon badge preview
        Row {
          width: parent.width
          spacing: Style.space(10)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(32); height: Style.space(32); radius: width * 0.5
            color: (mapRoot.dialogLight && mapRoot.dialogLight.on) ? (mapRoot.dialogLight.color || "#ffd27a") : Qt.rgba(22 / 255, 26 / 255, 36 / 255, 0.92)
            border.width: 1.8
            border.color: mapRoot.accentColor
            LampGlyph {
              anchors.centerIn: parent
              width: Style.space(19); height: Style.space(19)
              iconName: mapRoot.lampIconFor(mapRoot.dialogLampId)
              version: mapRoot.iconVersion
              tint: mapRoot.contrastTintForLight(mapRoot.dialogLight)
            }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(42)
            spacing: Style.space(1)
            Text {
              width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
              text: mapRoot.dialogLight ? String(mapRoot.dialogLight.name || "") : mapRoot.t("mapLampIconTitle")
              color: mapRoot.fg
              font.family: mapRoot.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: mapRoot.t("mapLampIconTitle") + " · " + mapRoot.lampIconLabel(mapRoot.lampIconFor(mapRoot.dialogLampId))
              color: mapRoot.dim
              font.family: mapRoot.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // 12 bold vector icon buttons (4 x 3 grid)
        Grid {
          id: iconGrid
          width: parent.width
          columns: 4
          spacing: Style.space(6)
          readonly property real cellW: Math.floor((width - spacing * 3) / 4)

          Repeater {
            model: mapRoot.lampIconList
            delegate: Rectangle {
              id: icoBtn
              required property var modelData
              readonly property bool active: mapRoot.lampIconFor(mapRoot.dialogLampId) === modelData.id
              width: iconGrid.cellW
              height: Style.space(48)
              radius: mapRoot.corners.control
              color: active
                ? Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.24)
                : (icoBtnM.containsMouse ? Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.11) : Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.04))
              border.width: active ? 1.6 : 1
              border.color: active ? mapRoot.accentColor : Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.14)

              Column {
                anchors.centerIn: parent
                spacing: Style.space(3)
                LampGlyph {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Style.space(20); height: Style.space(20)
                  iconName: icoBtn.modelData.id
                  version: mapRoot.iconVersion
                  tint: icoBtn.active ? mapRoot.accentColor : mapRoot.fg
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: icoBtn.width - Style.space(6)
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: mapRoot.t(icoBtn.modelData.key)
                  color: icoBtn.active ? mapRoot.fg : mapRoot.dim
                  font.family: mapRoot.fontFamily
                  font.pixelSize: Math.max(9, Style.font.caption - 2)
                  font.bold: icoBtn.active
                }
              }

              MouseArea {
                id: icoBtnM
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (mapRoot.dialogLampId) mapRoot.setLampIcon(mapRoot.dialogLampId, icoBtn.modelData.id)
              }
            }
          }
        }

        // Footer: Done
        Item {
          width: parent.width
          height: iconDoneBtn.implicitHeight
          Button {
            id: iconDoneBtn
            anchors.right: parent.right
            radius: mapRoot.corners.control
            text: mapRoot.t("shotDone")
            bordered: true
            selected: true
            accent: mapRoot.accentColor
            foreground: mapRoot.fg
            fontFamily: mapRoot.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(12); verticalPadding: Style.space(3)
            onClicked: mapRoot.closeDialog()
          }
        }
      }
    }

    // ---- 4D. NEW / EDIT RULE MODAL DIALOG ----
    Rectangle {
      visible: mapRoot.activeDialog === "rule"
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(20), Style.space(356))
      height: ruleDlgCol.implicitHeight + Style.space(24)
      radius: mapRoot.corners.radius
      color: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 0.97)
      border.width: 1
      border.color: Qt.rgba(mapRoot.accentColor.r, mapRoot.accentColor.g, mapRoot.accentColor.b, 0.45)

      MouseArea { anchors.fill: parent }

      Column {
        id: ruleDlgCol
        x: Style.space(12); y: Style.space(12)
        width: parent.width - Style.space(24)
        spacing: Style.space(9)

        // Header: New/Edit Rule title + Enabled switch (when editing)
        Item {
          width: parent.width
          height: Math.max(ruleDlgTitle.implicitHeight, ruleEnRow.implicitHeight)
          Text {
            id: ruleDlgTitle
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: mapRoot.ruleEditId !== "" ? mapRoot.t("mapEditRule") : mapRoot.t("mapNewRule")
            color: mapRoot.fg
            font.family: mapRoot.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          Row {
            id: ruleEnRow
            visible: mapRoot.ruleEditId !== ""
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: mapRoot.t("mapRuleEnabled")
              color: mapRoot.dim
              font.family: mapRoot.fontFamily
              font.pixelSize: Style.font.caption
            }
            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              cursorRing: false
              rounded: mapRoot.corners.pill > 0
              trackHeight: Style.space(16)
              checked: mapRoot.ruleEditEnabled
              foreground: mapRoot.fg
              accent: mapRoot.accentColor
              onToggled: mapRoot.ruleEditEnabled = !mapRoot.ruleEditEnabled
            }
          }
        }

        // Pre-filled endpoints pill: ● Lamp A  →  ● Lamp B
        Rectangle {
          width: parent.width
          height: epRow.implicitHeight + Style.space(10)
          radius: mapRoot.corners.control
          color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.06)
          border.width: 1
          border.color: Qt.rgba(mapRoot.fg.r, mapRoot.fg.g, mapRoot.fg.b, 0.14)

          Row {
            id: epRow
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.space(14), implicitWidth)
            spacing: Style.space(6)
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(9); height: Style.space(9); radius: width * 0.5
              color: mapRoot.entityDotColor(mapRoot.ruleEditFromKind, mapRoot.ruleEditFromId)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, (parent.parent.width - Style.space(58)) * 0.48)
              elide: Text.ElideRight; textFormat: Text.PlainText
              text: mapRoot.entityName(mapRoot.ruleEditFromKind, mapRoot.ruleEditFromId)
              color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText; text: "→"
              color: mapRoot.accentColor; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(9); height: Style.space(9); radius: width * 0.5
              color: mapRoot.entityDotColor(mapRoot.ruleEditToKind, mapRoot.ruleEditToId)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, (parent.parent.width - Style.space(58)) * 0.48)
              elide: Text.ElideRight; textFormat: Text.PlainText
              text: mapRoot.entityName(mapRoot.ruleEditToKind, mapRoot.ruleEditToId)
              color: mapRoot.fg; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
            }
          }
        }

        // Rule Type: Follow / Mirror | Exclusive | Companion
        Column {
          width: parent.width
          spacing: Style.space(4)
          Text {
            textFormat: Text.PlainText; text: mapRoot.t("ruleType")
            color: mapRoot.dim; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
          }
          Flow {
            width: parent.width
            spacing: Style.space(5)
            Repeater {
              model: [
                { id: "follow",    key: "mapRuleFollowMirror", col: "#38BDF8" },
                { id: "exclusive", key: "ruleExclusive",       col: "#F43F5E" },
                { id: "companion", key: "ruleCompanion",       col: "#F59E0B" }
              ]
              delegate: Button {
                required property var modelData
                radius: mapRoot.corners.control
                text: mapRoot.t(modelData.key)
                bordered: true
                selected: mapRoot.ruleEditKind === modelData.id
                accent: modelData.col
                foreground: mapRoot.fg
                fontFamily: mapRoot.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8); verticalPadding: Style.space(2)
                onClicked: {
                  mapRoot.ruleEditKind = modelData.id
                  if (modelData.id === "follow") {
                    mapRoot.ruleEditMirrorOff = true
                    mapRoot.ruleEditOnlyIfOff = false
                  } else if (modelData.id === "companion") {
                    mapRoot.ruleEditMirrorOff = false
                    mapRoot.ruleEditOnlyIfOff = true
                  } else {
                    mapRoot.ruleEditMirrorOff = false
                    mapRoot.ruleEditMatchBri = false
                    mapRoot.ruleEditOnlyIfOff = false
                  }
                }
              }
            }
          }
        }

        // Context-aware Trigger State ("When"): Turns on/off | Motion detected/No motion | Opens/Closes | Pressed/Long press
        Row {
          width: parent.width
          spacing: Style.space(6)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText; text: mapRoot.t("mapTriggerState")
            color: mapRoot.dim; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
          }
          Flow {
            width: parent.width - Style.space(52)
            spacing: Style.space(5)
            Repeater {
              model: mapRoot.triggerStateOptionsFor(mapRoot.ruleEditFromKind)
              delegate: Button {
                required property var modelData
                radius: mapRoot.corners.control
                text: mapRoot.t(modelData.key)
                bordered: true
                selected: mapRoot.ruleEditTriggerState === modelData.id
                accent: mapRoot.accentColor
                foreground: mapRoot.fg
                fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
                horizontalPadding: Style.space(8); verticalPadding: Style.space(2)
                onClicked: mapRoot.ruleEditTriggerState = modelData.id
              }
            }
          }
        }

        // Options (hidden for Exclusive; context-aware for sensors)
        Flow {
          visible: mapRoot.ruleEditKind !== "exclusive"
          width: parent.width
          spacing: Style.space(5)
          Button {
            visible: mapRoot.ruleEditFromKind !== "button"
            radius: mapRoot.corners.control
            text: (mapRoot.ruleEditMirrorOff ? "✓ " : "") + mapRoot.t("mapOptAlsoTurnOff")
            bordered: true; selected: mapRoot.ruleEditMirrorOff; accent: mapRoot.accentColor
            foreground: mapRoot.fg; fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: mapRoot.ruleEditMirrorOff = !mapRoot.ruleEditMirrorOff
          }
          Button {
            visible: !mapRoot.isSensorTriggerKind(mapRoot.ruleEditFromKind)
            radius: mapRoot.corners.control
            text: (mapRoot.ruleEditMatchBri ? "✓ " : "") + mapRoot.t("matchBri")
            bordered: true; selected: mapRoot.ruleEditMatchBri; accent: mapRoot.accentColor
            foreground: mapRoot.fg; fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: mapRoot.ruleEditMatchBri = !mapRoot.ruleEditMatchBri
          }
          Button {
            radius: mapRoot.corners.control
            text: (mapRoot.ruleEditOnlyIfOff ? "✓ " : "") + mapRoot.t("mapOptOnlyIfTargetOff")
            bordered: true; selected: mapRoot.ruleEditOnlyIfOff; accent: mapRoot.accentColor
            foreground: mapRoot.fg; fontFamily: mapRoot.fontFamily; fontSize: Style.font.caption
            horizontalPadding: Style.space(7); verticalPadding: Style.space(2)
            onClicked: mapRoot.ruleEditOnlyIfOff = !mapRoot.ruleEditOnlyIfOff
          }
        }

        // Optional time window (HH:MM – HH:MM)
        Column {
          width: parent.width
          spacing: Style.space(3)
          Text {
            textFormat: Text.PlainText; text: mapRoot.t("timeWindow")
            color: mapRoot.dim; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
          }
          Row {
            spacing: Style.space(6)
            KeyTextField {
              id: mapRuleStartField
              width: Style.space(96)
              radius: mapRoot.corners.control
              maximumLength: 5
              font: Qt.font({ family: mapRoot.fontFamily, pixelSize: Style.font.caption })
              placeholderText: mapRoot.t("timeStartPlaceholder")
              foreground: mapRoot.fg
              accent: mapRoot.accentColor
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText; text: "–"
              color: mapRoot.dim; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
            }
            KeyTextField {
              id: mapRuleEndField
              width: Style.space(96)
              radius: mapRoot.corners.control
              maximumLength: 5
              font: Qt.font({ family: mapRoot.fontFamily, pixelSize: Style.font.caption })
              placeholderText: mapRoot.t("timeEndPlaceholder")
              foreground: mapRoot.fg
              accent: mapRoot.accentColor
            }
          }
        }

        // Optional name (auto-generated if empty)
        Column {
          width: parent.width
          spacing: Style.space(3)
          Text {
            textFormat: Text.PlainText; text: mapRoot.t("mapRuleNameOptional")
            color: mapRoot.dim; font.family: mapRoot.fontFamily; font.pixelSize: Style.font.caption
          }
          KeyTextField {
            id: mapRuleNameField
            width: parent.width
            radius: mapRoot.corners.control
            maximumLength: 60
            font: Qt.font({ family: mapRoot.fontFamily, pixelSize: Style.font.caption })
            placeholderText: mapRoot.autoRuleName()
            foreground: mapRoot.fg
            accent: mapRoot.accentColor
            onAccepted: mapRoot.saveRuleFromDialog()
          }
        }

        // Footer: Delete (left, when editing) + Cancel / Save (right)
        Item {
          width: parent.width
          height: Math.max(ruleDelBtn.implicitHeight, ruleActionRow.implicitHeight)

          Button {
            id: ruleDelBtn
            visible: mapRoot.ruleEditId !== ""
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            radius: mapRoot.corners.control
            iconText: "󰩺"
            text: mapRoot.t("deleteTip")
            bordered: true
            foreground: Commons.Color.urgent
            fontFamily: mapRoot.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(9); verticalPadding: Style.space(3)
            onClicked: {
              mapRoot.sendCommand({ cmd: "rule_delete", id: mapRoot.ruleEditId })
              mapRoot.closeDialog()
              mapCanvas.requestPaint()
            }
          }

          Row {
            id: ruleActionRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Button {
              radius: mapRoot.corners.control
              text: mapRoot.t("cancel")
              bordered: true
              foreground: mapRoot.dim
              fontFamily: mapRoot.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(10); verticalPadding: Style.space(3)
              onClicked: mapRoot.closeDialog()
            }
            Button {
              radius: mapRoot.corners.control
              iconText: "󰄬"
              text: mapRoot.t("mapSave")
              bordered: true
              selected: true
              accent: mapRoot.accentColor
              foreground: mapRoot.fg
              fontFamily: mapRoot.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(10); verticalPadding: Style.space(3)
              enabled: {
                if (!mapRoot.ruleEditFromId || !mapRoot.ruleEditToId) return false
                if (mapRoot.ruleEditFromKind === mapRoot.ruleEditToKind && mapRoot.ruleEditFromId === mapRoot.ruleEditToId) return false
                var ts = mapRuleStartField.text.trim()
                var te = mapRuleEndField.text.trim()
                if (ts !== "" || te !== "") return mapRoot.validHHMM(ts) && mapRoot.validHHMM(te)
                return true
              }
              onClicked: mapRoot.saveRuleFromDialog()
            }
          }
        }
      }
    }
  }
}
