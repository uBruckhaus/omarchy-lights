pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "I18n.js" as I18n

// Animated Help & Feature Guide page.
// Uses a single lightweight 20 fps Timer running ONLY while visible (zero idle CPU cost).
Column {
  id: helpRoot

  property color fg: Commons.Color.popups.text
  property color dim: Qt.darker(fg, 1.45)
  property color accentColor: Commons.Color.accent
  property bool hasSkin: false
  property string fontFamily: Style.font.family
  property var corners: ({ radius: Style.cornerRadius, control: Style.cornerRadius, small: 4, pill: 999 })
  property string lang: "en"
  property int selectedIndex: -1

  signal backRequested()
  signal tryFeature(string target)

  onVisibleChanged: if (!visible) selectedIndex = -1

  function t(key, args) { return I18n.tr(lang, key, args) }

  spacing: Style.space(10)

  readonly property color cardBorderColor: hasSkin
    ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.30)
    : Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property color cardFillColor: hasSkin
    ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.07)
    : Qt.rgba(fg.r, fg.g, fg.b, 0.04)

  // Single shared 20 fps phase clock (runs strictly while HelpPage is visible)
  property real animPhase: 0.0
  Timer {
    interval: 50
    repeat: true
    running: helpRoot.visible
    onTriggered: helpRoot.animPhase = (helpRoot.animPhase + 0.012) % 1.0
  }

  readonly property var featureItems: [
    {
      id: "lights", target: "lights",
      titleKey: "helpLightsTitle", descKey: "helpLightsDesc",
      steps: ["helpLightsStep1", "helpLightsStep2", "helpLightsStep3"],
      tipKey: "helpLightsTip"
    },
    {
      id: "map", target: "map",
      titleKey: "helpMapTitle", descKey: "helpMapDesc",
      steps: ["helpMapStep1", "helpMapStep2", "helpMapStep3", "helpMapStep4"],
      tipKey: "helpMapTip"
    },
    {
      id: "rules", target: "map_rules",
      titleKey: "helpRulesTitle", descKey: "helpRulesDesc",
      steps: ["helpRulesStep1", "helpRulesStep2", "helpRulesStep3", "helpRulesStep4"],
      tipKey: "helpRulesTip"
    },
    {
      id: "motion", target: "map",
      titleKey: "helpMotionTitle", descKey: "helpMotionDesc",
      steps: ["helpMotionStep1", "helpMotionStep2", "helpMotionStep3", "helpMotionStep4"],
      tipKey: "helpMotionTip"
    },
    {
      id: "schedules", target: "schedules",
      titleKey: "helpSchedulesTitle", descKey: "helpSchedulesDesc",
      steps: ["helpSchedulesStep1", "helpSchedulesStep2", "helpSchedulesStep3"],
      tipKey: "helpSchedulesTip"
    },
    {
      id: "synth", target: "synth",
      titleKey: "helpSynthTitle", descKey: "helpSynthDesc",
      steps: ["helpSynthStep1", "helpSynthStep2", "helpSynthStep3"],
      tipKey: "helpSynthTip"
    },
    {
      id: "skins", target: "settings",
      titleKey: "helpSkinsTitle", descKey: "helpSkinsDesc",
      steps: ["helpSkinsStep1", "helpSkinsStep2", "helpSkinsStep3"],
      tipKey: "helpSkinsTip"
    },
    {
      id: "askAi", target: "settings",
      titleKey: "helpAskAiTitle", descKey: "helpAskAiDesc",
      steps: ["helpAskAiStep1", "helpAskAiStep2", "helpAskAiStep3"],
      tipKey: "helpAskAiTip"
    },
    {
      id: "mcp", target: "settings",
      titleKey: "helpMcpTitle", descKey: "helpMcpDesc",
      steps: ["helpMcpStep1", "helpMcpStep2", "helpMcpStep3"],
      tipKey: "helpMcpTip"
    }
  ]

  readonly property var selectedFeature: (selectedIndex >= 0 && selectedIndex < featureItems.length)
    ? featureItems[selectedIndex]
    : null

  function lerp(a, b, t) { return a + (b - a) * t }

  function lerpRgb(c1, c2, t) {
    var r = Math.round(lerp(c1[0], c2[0], t))
    var g = Math.round(lerp(c1[1], c2[1], t))
    var b = Math.round(lerp(c1[2], c2[2], t))
    return [r, g, b]
  }

  function rgbaStr(rgb, a) {
    return "rgba(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + "," + a.toFixed(3) + ")"
  }

  function roundedRectPath(ctx, x, y, w, h, r) {
    var rad = Math.min(r, w * 0.5, h * 0.5)
    ctx.beginPath()
    ctx.moveTo(x + rad, y)
    ctx.lineTo(x + w - rad, y)
    ctx.quadraticCurveTo(x + w, y, x + w, y + rad)
    ctx.lineTo(x + w, y + h - rad)
    ctx.quadraticCurveTo(x + w, y + h, x + w - rad, y + h)
    ctx.lineTo(x + rad, y + h)
    ctx.quadraticCurveTo(x, y + h, x, y + h - rad)
    ctx.lineTo(x, y + rad)
    ctx.quadraticCurveTo(x, y, x + rad, y)
    ctx.closePath()
  }

  function drawFeaturePreview(ctx, featureId, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch)
    var w = 120.0
    var h = 80.0
    var scale = Math.min(cw / w, ch / h)
    var offX = (cw - w * scale) * 0.5
    var offY = (ch - h * scale) * 0.5
    ctx.save()
    ctx.translate(offX, offY)
    ctx.scale(scale, scale)

    if (featureId === "lights") {
      // 1. Color-cycling bulb orb + animated brightness slider
      var palette = [
        [255, 196, 86],
        [255, 96, 118],
        [56, 189, 248],
        [168, 85, 247]
      ]
      var seg = p * palette.length
      var i0 = Math.floor(seg) % palette.length
      var i1 = (i0 + 1) % palette.length
      var frac = seg - Math.floor(seg)
      var rgb = lerpRgb(palette[i0], palette[i1], frac)
      var bri = 0.45 + 0.50 * (0.5 + 0.5 * Math.sin(p * Math.PI * 2))

      // Radial light halo
      var cx = w * 0.5, cy = h * 0.39
      var glowR = 16 + bri * 22
      var grad = ctx.createRadialGradient(cx, cy, 2, cx, cy, glowR)
      grad.addColorStop(0.0, rgbaStr(rgb, 0.72 * bri))
      grad.addColorStop(0.55, rgbaStr(rgb, 0.24 * bri))
      grad.addColorStop(1.0, rgbaStr(rgb, 0.0))
      ctx.fillStyle = grad
      ctx.beginPath()
      ctx.arc(cx, cy, glowR, 0, Math.PI * 2)
      ctx.fill()

      // Bulb circle + bulb silhouette
      ctx.fillStyle = rgbaStr(rgb, 0.95)
      ctx.beginPath()
      ctx.arc(cx, cy, 12, 0, Math.PI * 2)
      ctx.fill()
      ctx.strokeStyle = "rgba(255,255,255,0.75)"
      ctx.lineWidth = 1.2
      ctx.stroke()

      ctx.fillStyle = "#111620"
      ctx.beginPath()
      ctx.arc(cx, cy - 1.5, 4.5, Math.PI * 0.78, Math.PI * 0.22, false)
      ctx.lineTo(cx + 2.2, cy + 3.8)
      ctx.lineTo(cx - 2.2, cy + 3.8)
      ctx.closePath()
      ctx.fill()
      ctx.strokeStyle = "#111620"
      ctx.lineWidth = 1.3
      ctx.beginPath()
      ctx.moveTo(cx - 2.0, cy + 5.6); ctx.lineTo(cx + 2.0, cy + 5.6)
      ctx.stroke()

      // Animated brightness slider
      var sx = 18, sy = h - 15, sw = w - 36
      ctx.fillStyle = "rgba(255,255,255,0.16)"
      roundedRectPath(ctx, sx, sy - 2, sw, 4, 2)
      ctx.fill()
      var fillW = Math.max(6, sw * bri)
      ctx.fillStyle = rgbaStr(rgb, 0.92)
      roundedRectPath(ctx, sx, sy - 2, fillW, 4, 2)
      ctx.fill()
      ctx.fillStyle = "#ffffff"
      ctx.beginPath()
      ctx.arc(sx + fillW, sy, 4.2, 0, Math.PI * 2)
      ctx.fill()

    } else if (featureId === "map") {
      // 2. 2-room floorplan + gliding lamp + radial glow + fading hover tooltip pill
      ctx.fillStyle = "rgba(255,255,255,0.10)"
      for (var gx = 10; gx < w; gx += 12) {
        for (var gy = 10; gy < h; gy += 12) {
          ctx.fillRect(gx, gy, 1.2, 1.2)
        }
      }
      // Two rooms
      ctx.strokeStyle = "rgba(210,224,245,0.40)"
      ctx.fillStyle = "rgba(255,255,255,0.04)"
      ctx.lineWidth = 1.2
      roundedRectPath(ctx, 10, 12, 48, 56, 4); ctx.fill(); ctx.stroke()
      roundedRectPath(ctx, 62, 12, 48, 56, 4); ctx.fill(); ctx.stroke()

      // Gliding lamp position (smooth figure-8 / room-to-room glide)
      var wave = 0.5 - 0.5 * Math.cos(p * Math.PI * 2)
      var lx = lerp(34, 86, wave)
      var ly = 44 + Math.sin(p * Math.PI * 4) * 6

      // Radial warm glow
      var mgrad = ctx.createRadialGradient(lx, ly, 1, lx, ly, 24)
      mgrad.addColorStop(0.0, "rgba(255,210,122,0.62)")
      mgrad.addColorStop(0.55, "rgba(255,210,122,0.18)")
      mgrad.addColorStop(1.0, "rgba(255,210,122,0.0)")
      ctx.fillStyle = mgrad
      ctx.beginPath()
      ctx.arc(lx, ly, 24, 0, Math.PI * 2)
      ctx.fill()

      // Lamp dot
      ctx.fillStyle = "#ffd27a"
      ctx.beginPath()
      ctx.arc(lx, ly, 6.5, 0, Math.PI * 2)
      ctx.fill()
      ctx.strokeStyle = "#ffffff"
      ctx.lineWidth = 1.3
      ctx.stroke()

      // Fading hover tooltip pill above lamp
      var tipAlpha = Math.max(0.0, Math.min(1.0, Math.sin(p * Math.PI * 2) * 1.4))
      if (tipAlpha > 0.05) {
        ctx.save()
        ctx.globalAlpha = tipAlpha
        var tw = 42, th = 13
        var tx = Math.max(6, Math.min(w - tw - 6, lx - tw * 0.5))
        var ty = ly - 23
        ctx.fillStyle = "rgba(10,13,20,0.92)"
        roundedRectPath(ctx, tx, ty, tw, th, 6)
        ctx.fill()
        ctx.strokeStyle = "rgba(255,255,255,0.30)"
        ctx.lineWidth = 1
        ctx.stroke()
        ctx.fillStyle = "rgba(248,250,252,0.88)"
        roundedRectPath(ctx, tx + 7, ty + 5, tw - 14, 3, 1.5)
        ctx.fill()
        ctx.restore()
      }

    } else if (featureId === "rules") {
      // 3. Animated Bezier curve tracing from Lamp A to Lamp B and lighting Lamp B
      var ax = 26, ay = 46
      var bx = 94, by = 46
      var cx2 = 60, cy2 = 16
      var drawT = Math.min(1.0, p / 0.55)
      var bLit = p >= 0.52

      // Guide dashed curve
      ctx.save()
      ctx.strokeStyle = "rgba(56,189,248,0.22)"
      ctx.lineWidth = 1.5
      ctx.setLineDash([3, 3])
      ctx.beginPath()
      ctx.moveTo(ax, ay)
      ctx.quadraticCurveTo(cx2, cy2, bx, by)
      ctx.stroke()
      ctx.restore()

      // Progressive Bezier trace
      ctx.strokeStyle = "#38BDF8"
      ctx.lineWidth = 2.2
      ctx.beginPath()
      var steps = 22
      for (var s = 0; s <= steps; s++) {
        var u = (s / steps) * drawT
        var inv = 1.0 - u
        var px = inv * inv * ax + 2 * inv * u * cx2 + u * u * bx
        var py = inv * inv * ay + 2 * inv * u * cy2 + u * u * by
        if (s === 0) ctx.moveTo(px, py)
        else ctx.lineTo(px, py)
      }
      ctx.stroke()

      // Moving pulse dot along curve
      var invP = 1.0 - drawT
      var dotX = invP * invP * ax + 2 * invP * drawT * cx2 + drawT * drawT * bx
      var dotY = invP * invP * ay + 2 * invP * drawT * cy2 + drawT * drawT * by
      ctx.fillStyle = "#22D3EE"
      ctx.beginPath()
      ctx.arc(dotX, dotY, 3.0, 0, Math.PI * 2)
      ctx.fill()

      // Lamp A (always lit)
      var gA = ctx.createRadialGradient(ax, ay, 2, ax, ay, 18)
      gA.addColorStop(0.0, "rgba(255,210,122,0.55)")
      gA.addColorStop(1.0, "rgba(255,210,122,0.0)")
      ctx.fillStyle = gA; ctx.beginPath(); ctx.arc(ax, ay, 18, 0, Math.PI * 2); ctx.fill()
      ctx.fillStyle = "#ffd27a"
      ctx.beginPath(); ctx.arc(ax, ay, 8.5, 0, Math.PI * 2); ctx.fill()
      ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 1.3; ctx.stroke()

      // Lamp B (lights up when pulse arrives!)
      var litAmt = bLit ? Math.min(1.0, (p - 0.52) / 0.14) * (p > 0.88 ? Math.max(0.0, (1.0 - p) / 0.12) : 1.0) : 0.0
      if (litAmt > 0.02) {
        var gB = ctx.createRadialGradient(bx, by, 2, bx, by, 21)
        gB.addColorStop(0.0, "rgba(56,189,248," + (0.65 * litAmt).toFixed(3) + ")")
        gB.addColorStop(1.0, "rgba(56,189,248,0.0)")
        ctx.fillStyle = gB; ctx.beginPath(); ctx.arc(bx, by, 21, 0, Math.PI * 2); ctx.fill()
      }
      ctx.fillStyle = litAmt > 0.1 ? rgbaStr(lerpRgb([28, 34, 46], [56, 189, 248], litAmt), 0.96) : "rgba(28,34,46,0.95)"
      ctx.beginPath(); ctx.arc(bx, by, 8.5, 0, Math.PI * 2); ctx.fill()
      ctx.strokeStyle = litAmt > 0.1 ? "#ffffff" : "rgba(255,255,255,0.38)"
      ctx.lineWidth = 1.3; ctx.stroke()

    } else if (featureId === "motion") {
      // 4. Expanding emerald/cyan radar waves from MotionAware lamp & rounded-square sensor
      var mlx = 36, mly = 42
      var msx = 84, msy = 42
      for (var ring = 0; ring < 3; ring++) {
        var rp = (p + ring / 3.0) % 1.0
        var rr = 9 + rp * 22
        var ra = (1.0 - rp) * 0.72
        ctx.strokeStyle = "rgba(16,185,129," + ra.toFixed(3) + ")"
        ctx.lineWidth = 1.6
        ctx.beginPath(); ctx.arc(mlx, mly, rr, 0, Math.PI * 2); ctx.stroke()

        var rp2 = (p + 0.16 + ring / 3.0) % 1.0
        var rr2 = 9 + rp2 * 22
        var ra2 = (1.0 - rp2) * 0.65
        ctx.strokeStyle = "rgba(34,211,238," + ra2.toFixed(3) + ")"
        ctx.beginPath(); ctx.arc(msx, msy, rr2, 0, Math.PI * 2); ctx.stroke()
      }
      // Circular MotionAware lamp with emerald corner badge
      ctx.fillStyle = "#ffd27a"
      ctx.beginPath(); ctx.arc(mlx, mly, 9, 0, Math.PI * 2); ctx.fill()
      ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 1.2; ctx.stroke()
      ctx.fillStyle = "#10B981"
      ctx.beginPath(); ctx.arc(mlx + 7, mly - 7, 4.2, 0, Math.PI * 2); ctx.fill()
      ctx.strokeStyle = "#0c1018"; ctx.lineWidth = 1.2; ctx.stroke()

      // Rounded-square physical sensor node
      ctx.fillStyle = "rgba(16,185,129,0.28)"
      roundedRectPath(ctx, msx - 9, msy - 9, 18, 18, 4.5)
      ctx.fill()
      ctx.strokeStyle = "#10B981"; ctx.lineWidth = 1.5; ctx.stroke()
      ctx.fillStyle = "#10B981"
      ctx.beginPath(); ctx.arc(msx, msy, 2.8, 0, Math.PI * 2); ctx.fill()

    } else if (featureId === "schedules") {
      // 5. Animated sun/moon arc lighting house windows
      var isNight = p >= 0.5
      var subP = isNight ? (p - 0.5) * 2.0 : p * 2.0
      var ang = Math.PI + subP * Math.PI
      var ox = w * 0.5 + Math.cos(ang) * 42
      var oy = 46 + Math.sin(ang) * 32

      // Dashed sky arc
      ctx.save()
      ctx.strokeStyle = "rgba(255,255,255,0.16)"
      ctx.lineWidth = 1
      ctx.setLineDash([2, 3])
      ctx.beginPath()
      ctx.arc(w * 0.5, 46, 42, Math.PI, 0)
      ctx.stroke()
      ctx.restore()

      // Sun or Moon
      if (!isNight) {
        ctx.fillStyle = "#F59E0B"
        ctx.beginPath(); ctx.arc(ox, oy, 6.2, 0, Math.PI * 2); ctx.fill()
      } else {
        ctx.fillStyle = "#93C5FD"
        ctx.beginPath(); ctx.arc(ox, oy, 5.8, 0, Math.PI * 2); ctx.fill()
        ctx.fillStyle = "#0c1018"
        ctx.beginPath(); ctx.arc(ox + 2.5, oy - 1.4, 4.6, 0, Math.PI * 2); ctx.fill()
      }

      // House silhouette
      var hx = w * 0.5 - 20, hy = 46, hw = 40, hh = 24
      ctx.fillStyle = "rgba(210,224,245,0.14)"
      ctx.strokeStyle = "rgba(210,224,245,0.45)"
      ctx.lineWidth = 1.2
      ctx.beginPath()
      ctx.moveTo(hx - 4, hy + 2)
      ctx.lineTo(w * 0.5, hy - 12)
      ctx.lineTo(hx + hw + 4, hy + 2)
      ctx.closePath()
      ctx.fill(); ctx.stroke()
      ctx.fillRect(hx, hy + 2, hw, hh - 2)
      ctx.strokeRect(hx, hy + 2, hw, hh - 2)

      // Windows glow warmly at night
      var winLit = isNight ? Math.sin(subP * Math.PI) : 0.0
      ctx.fillStyle = winLit > 0.05 ? rgbaStr([255, 206, 98], 0.25 + 0.72 * winLit) : "rgba(255,255,255,0.10)"
      ctx.fillRect(hx + 6, hy + 8, 9, 9)
      ctx.fillRect(hx + 25, hy + 8, 9, 9)

    } else if (featureId === "synth") {
      // 6. Animated 3-band Bass / Mids / Treble bars + pulsing beat indicator
      var bass = 0.25 + 0.72 * Math.abs(Math.sin(p * Math.PI * 4))
      var mids = 0.22 + 0.68 * Math.abs(Math.sin(p * Math.PI * 6 + 1.1))
      var treb = 0.18 + 0.74 * Math.abs(Math.sin(p * Math.PI * 8 + 2.3))
      var bars = [
        { v: bass, col: "#ff2e93" },
        { v: (bass + mids) * 0.5, col: "#ec4899" },
        { v: mids, col: "#f59e0b" },
        { v: (mids + treb) * 0.5, col: "#38bdf8" },
        { v: treb, col: "#00d2ff" }
      ]
      var bw = 11, gap = 6
      var totalW = bars.length * bw + (bars.length - 1) * gap
      var startX = (w - totalW) * 0.5
      var maxH = 44
      var baseY = h - 12
      for (var bi = 0; bi < bars.length; bi++) {
        var bh = Math.max(6, bars[bi].v * maxH)
        var bx2 = startX + bi * (bw + gap)
        ctx.fillStyle = "rgba(255,255,255,0.08)"
        roundedRectPath(ctx, bx2, baseY - maxH, bw, maxH, 3)
        ctx.fill()
        ctx.fillStyle = bars[bi].col
        roundedRectPath(ctx, bx2, baseY - bh, bw, bh, 3)
        ctx.fill()
      }
      // Beat pulse dot top-right
      var beatOn = bass > 0.78
      ctx.fillStyle = beatOn ? "#ff2e93" : "rgba(255,255,255,0.22)"
      ctx.beginPath()
      ctx.arc(w - 14, 13, beatOn ? 4.8 : 3.4, 0, Math.PI * 2)
      ctx.fill()

    } else if (featureId === "skins") {
      // 7. Mini app card cycling through 6 skins + F12 / Esc keycaps
      var skinCols = [
        [56, 189, 248],   // Native
        [255, 46, 147],   // Synthwave
        [245, 158, 11],   // Cozy
        [34, 197, 94],    // Terminal
        [168, 85, 247],   // Disco
        [94, 234, 212]    // Zen
      ]
      var sSeg = p * skinCols.length
      var si0 = Math.floor(sSeg) % skinCols.length
      var si1 = (si0 + 1) % skinCols.length
      var sFrac = sSeg - Math.floor(sSeg)
      var sc = lerpRgb(skinCols[si0], skinCols[si1], sFrac)

      // Mini panel card
      ctx.fillStyle = rgbaStr(sc, 0.14)
      ctx.strokeStyle = rgbaStr(sc, 0.78)
      ctx.lineWidth = 1.4
      roundedRectPath(ctx, 12, 10, 56, 60, 6)
      ctx.fill(); ctx.stroke()
      // Top accent bar + dummy rows
      ctx.fillStyle = rgbaStr(sc, 0.90)
      roundedRectPath(ctx, 18, 17, 26, 4, 2); ctx.fill()
      ctx.fillStyle = "rgba(255,255,255,0.16)"
      roundedRectPath(ctx, 18, 27, 44, 10, 3); ctx.fill()
      roundedRectPath(ctx, 18, 41, 44, 10, 3); ctx.fill()
      ctx.fillStyle = rgbaStr(sc, 0.85)
      ctx.beginPath(); ctx.arc(54, 32, 3, 0, Math.PI * 2); ctx.fill()
      ctx.beginPath(); ctx.arc(54, 46, 3, 0, Math.PI * 2); ctx.fill()

      // Keycaps: F12 & Esc
      var keys = [{ label: "F12", y: 18 }, { label: "Esc", y: 44 }]
      for (var ki = 0; ki < keys.length; ki++) {
        var pressedKey = (ki === 0 && p < 0.5) || (ki === 1 && p >= 0.5)
        ctx.fillStyle = pressedKey ? rgbaStr(sc, 0.28) : "rgba(255,255,255,0.08)"
        ctx.strokeStyle = pressedKey ? rgbaStr(sc, 0.90) : "rgba(255,255,255,0.32)"
        ctx.lineWidth = 1.2
        roundedRectPath(ctx, 76, keys[ki].y, 32, 19, 4)
        ctx.fill(); ctx.stroke()
        ctx.fillStyle = "#f8fafc"
        ctx.font = "bold 9px sans-serif"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText(keys[ki].label, 92, keys[ki].y + 10)
      }

    } else if (featureId === "askAi") {
      // 8. Prompt bubble + pulsing 4-point sparkle sending signal beam to warm glowing lamp
      var bxA = 10, byA = 20, bwA = 48, bhA = 28
      ctx.fillStyle = "rgba(168,85,247,0.16)"
      ctx.strokeStyle = "rgba(192,132,252,0.75)"
      ctx.lineWidth = 1.2
      roundedRectPath(ctx, bxA, byA, bwA, bhA, 6)
      ctx.fill(); ctx.stroke()

      // Animated typing lines inside bubble
      var line1W = 14 + 22 * Math.min(1.0, p / 0.35)
      var line2W = p > 0.25 ? 8 + 18 * Math.min(1.0, (p - 0.25) / 0.30) : 0
      ctx.fillStyle = "rgba(248,250,252,0.75)"
      roundedRectPath(ctx, bxA + 7, byA + 8, line1W, 3.2, 1.5); ctx.fill()
      if (line2W > 2) {
        ctx.fillStyle = "rgba(192,132,252,0.85)"
        roundedRectPath(ctx, bxA + 7, byA + 16, line2W, 3.2, 1.5); ctx.fill()
      }

      // Pulsing 4-point sparkle star above bubble corner
      var spX = bxA + bwA - 2, spY = byA - 2
      var spR = 5.5 + 2.2 * Math.sin(p * Math.PI * 4)
      ctx.fillStyle = "#c084fc"
      ctx.beginPath()
      ctx.moveTo(spX, spY - spR)
      ctx.quadraticCurveTo(spX, spY, spX + spR, spY)
      ctx.quadraticCurveTo(spX, spY, spX, spY + spR)
      ctx.quadraticCurveTo(spX, spY, spX - spR, spY)
      ctx.quadraticCurveTo(spX, spY, spX, spY - spR)
      ctx.closePath()
      ctx.fill()

      // Signal beam from bubble to lamp
      var beamT = p < 0.35 ? 0.0 : Math.min(1.0, (p - 0.35) / 0.35)
      var lxA = 95, lyA = 44
      ctx.save()
      ctx.strokeStyle = "rgba(192,132,252,0.22)"
      ctx.lineWidth = 1.4
      ctx.setLineDash([3, 3])
      ctx.beginPath()
      ctx.moveTo(bxA + bwA, byA + bhA * 0.5)
      ctx.quadraticCurveTo(72, 26, lxA - 10, lyA)
      ctx.stroke()
      ctx.restore()

      if (beamT > 0.02) {
        var invB = 1.0 - beamT
        var sx0 = bxA + bwA, sy0 = byA + bhA * 0.5
        var scx = 72, scy = 26
        var ex0 = lxA - 10, ey0 = lyA
        var bDotX = invB * invB * sx0 + 2 * invB * beamT * scx + beamT * beamT * ex0
        var bDotY = invB * invB * sy0 + 2 * invB * beamT * scy + beamT * beamT * ey0
        ctx.fillStyle = "#38bdf8"
        ctx.beginPath(); ctx.arc(bDotX, bDotY, 3.2, 0, Math.PI * 2); ctx.fill()
      }

      // Responding lamp orb on the right
      var lampLit = p >= 0.62 ? Math.min(1.0, (p - 0.62) / 0.14) * (p > 0.90 ? Math.max(0.0, (1.0 - p) / 0.10) : 1.0) : 0.15
      var lGrad = ctx.createRadialGradient(lxA, lyA, 2, lxA, lyA, 16 + lampLit * 12)
      lGrad.addColorStop(0.0, rgbaStr([255, 210, 122], 0.70 * lampLit))
      lGrad.addColorStop(1.0, "rgba(255,210,122,0.0)")
      ctx.fillStyle = lGrad
      ctx.beginPath(); ctx.arc(lxA, lyA, 16 + lampLit * 12, 0, Math.PI * 2); ctx.fill()

      ctx.fillStyle = rgbaStr(lerpRgb([30, 36, 48], [255, 210, 122], lampLit), 0.96)
      ctx.beginPath(); ctx.arc(lxA, lyA, 10, 0, Math.PI * 2); ctx.fill()
      ctx.strokeStyle = lampLit > 0.3 ? "#ffffff" : "rgba(255,255,255,0.35)"
      ctx.lineWidth = 1.3; ctx.stroke()

      // "LOCAL" tiny pill bottom-left
      ctx.fillStyle = "rgba(16,185,129,0.20)"
      ctx.strokeStyle = "rgba(16,185,129,0.70)"
      ctx.lineWidth = 1
      roundedRectPath(ctx, 10, 56, 40, 14, 7)
      ctx.fill(); ctx.stroke()
      ctx.fillStyle = "#34d399"
      ctx.font = "bold 7.5px sans-serif"
      ctx.textAlign = "center"
      ctx.textBaseline = "middle"
      ctx.fillText("LOCAL", 30, 63.5)

    } else if (featureId === "mcp") {
      // 9. Local stdio MCP pipeline: [AI] <-> [MCP + lock] <-> [Hue Lamp]
      var yMid = 40
      var xLeft = 22, xMid = 60, xRight = 98

      // Connecting stdio rails
      ctx.strokeStyle = "rgba(56,189,248,0.35)"
      ctx.lineWidth = 1.6
      ctx.beginPath()
      ctx.moveTo(xLeft + 12, yMid); ctx.lineTo(xMid - 14, yMid)
      ctx.moveTo(xMid + 14, yMid); ctx.lineTo(xRight - 11, yMid)
      ctx.stroke()

      // Animated bidirectional JSON-RPC packets
      var fwd = (p * 2.0) % 1.0
      var rev = (p * 2.0 + 0.5) % 1.0
      ctx.fillStyle = "#38bdf8"
      ctx.beginPath(); ctx.arc(lerp(xLeft + 12, xMid - 14, fwd), yMid - 3.5, 2.4, 0, Math.PI * 2); ctx.fill()
      ctx.fillStyle = "#10b981"
      ctx.beginPath(); ctx.arc(lerp(xMid + 14, xRight - 11, fwd), yMid - 3.5, 2.4, 0, Math.PI * 2); ctx.fill()
      ctx.fillStyle = "#93c5fd"
      ctx.beginPath(); ctx.arc(lerp(xMid - 14, xLeft + 12, rev), yMid + 3.5, 2.1, 0, Math.PI * 2); ctx.fill()
      ctx.fillStyle = "#ffd27a"
      ctx.beginPath(); ctx.arc(lerp(xRight - 11, xMid + 14, rev), yMid + 3.5, 2.1, 0, Math.PI * 2); ctx.fill()

      // Left node: External AI Agent
      ctx.fillStyle = "rgba(56,189,248,0.18)"
      ctx.strokeStyle = "#38bdf8"
      ctx.lineWidth = 1.3
      roundedRectPath(ctx, xLeft - 12, yMid - 13, 24, 26, 5)
      ctx.fill(); ctx.stroke()
      ctx.fillStyle = "#e0f2fe"
      ctx.font = "bold 8.5px sans-serif"
      ctx.textAlign = "center"
      ctx.textBaseline = "middle"
      ctx.fillText("AI", xLeft, yMid + 0.5)

      // Center node: MCP stdio gateway with emerald privacy lock badge
      ctx.fillStyle = "rgba(16,185,129,0.20)"
      ctx.strokeStyle = "#10b981"
      ctx.lineWidth = 1.4
      roundedRectPath(ctx, xMid - 14, yMid - 15, 28, 30, 6)
      ctx.fill(); ctx.stroke()
      ctx.fillStyle = "#d1fae5"
      ctx.font = "bold 8px sans-serif"
      ctx.fillText("MCP", xMid, yMid + 1)

      // Small lock icon above MCP box (credentials stay local)
      ctx.strokeStyle = "#34d399"
      ctx.lineWidth = 1.2
      ctx.beginPath()
      ctx.arc(xMid, yMid - 21, 3.2, Math.PI, 0)
      ctx.stroke()
      ctx.fillStyle = "#10b981"
      roundedRectPath(ctx, xMid - 4.5, yMid - 21, 9, 6.5, 1.5)
      ctx.fill()

      // Right node: Hue Bridge / Lamp glow
      var pulse = 0.55 + 0.45 * Math.sin(p * Math.PI * 4)
      var hGrad = ctx.createRadialGradient(xRight, yMid, 2, xRight, yMid, 16)
      hGrad.addColorStop(0.0, rgbaStr([255, 210, 122], 0.65 * pulse))
      hGrad.addColorStop(1.0, "rgba(255,210,122,0.0)")
      ctx.fillStyle = hGrad
      ctx.beginPath(); ctx.arc(xRight, yMid, 16, 0, Math.PI * 2); ctx.fill()
      ctx.fillStyle = "#ffd27a"
      ctx.beginPath(); ctx.arc(xRight, yMid, 9.5, 0, Math.PI * 2); ctx.fill()
      ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 1.2; ctx.stroke()

      // Bottom "STDIO" label
      ctx.fillStyle = "rgba(255,255,255,0.50)"
      ctx.font = "bold 7.5px sans-serif"
      ctx.fillText("LOCAL STDIO", w * 0.5, h - 10)
    }
    ctx.restore()
  }

  // Header bar ("← Back · ⌫" + HELP & GUIDE)
  PanelSeparator { width: parent.width; foreground: helpRoot.fg }

  Row {
    spacing: Style.space(12)
    Button {
      radius: helpRoot.corners.control
      anchors.verticalCenter: parent.verticalCenter
      text: helpRoot.selectedIndex >= 0
        ? helpRoot.t("helpAllFeatures")
        : (helpRoot.t("back") + " · ⌫")
      iconText: "󰁍"
      bordered: true
      foreground: helpRoot.fg
      fontFamily: helpRoot.fontFamily
      tooltipText: helpRoot.t("backTip")
      onClicked: {
        if (helpRoot.selectedIndex >= 0) helpRoot.selectedIndex = -1
        else helpRoot.backRequested()
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(Style.space(80), helpRoot.width - Style.space(150))
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: helpRoot.selectedFeature
        ? helpRoot.t(helpRoot.selectedFeature.titleKey).toUpperCase()
        : helpRoot.t("helpGuide").toUpperCase()
      color: helpRoot.fg
      font.family: helpRoot.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }
  }

  PanelSeparator { width: parent.width; foreground: helpRoot.fg }

  // =========================================================================
  // OVERVIEW MODE (selectedIndex < 0): 9 clickable animated feature cards
  // =========================================================================
  Column {
    visible: helpRoot.selectedIndex < 0
    width: parent.width
    spacing: Style.space(10)

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: helpRoot.t("helpIntro")
      color: helpRoot.dim
      font.family: helpRoot.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: helpRoot.featureItems
      delegate: Rectangle {
        id: featCard
        required property int index
        required property var modelData
        width: helpRoot.width
        height: Math.max(previewFrame.height, textCol.implicitHeight) + Style.space(16)
        radius: helpRoot.corners.radius
        color: cardMouse.containsMouse
          ? Qt.rgba(helpRoot.accentColor.r, helpRoot.accentColor.g, helpRoot.accentColor.b, 0.14)
          : helpRoot.cardFillColor
        border.width: 1
        border.color: cardMouse.containsMouse
          ? Qt.rgba(helpRoot.accentColor.r, helpRoot.accentColor.g, helpRoot.accentColor.b, 0.65)
          : helpRoot.cardBorderColor
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
          x: Style.space(8)
          y: Style.space(8)
          width: parent.width - Style.space(16)
          spacing: Style.space(10)

          Rectangle {
            id: previewFrame
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(120)
            height: Style.space(80)
            radius: helpRoot.corners.control
            color: Qt.rgba(0.05, 0.06, 0.10, 0.90)
            border.width: 1
            border.color: cardMouse.containsMouse
              ? Qt.rgba(helpRoot.accentColor.r, helpRoot.accentColor.g, helpRoot.accentColor.b, 0.55)
              : Qt.rgba(helpRoot.fg.r, helpRoot.fg.g, helpRoot.fg.b, 0.16)
            clip: true

            Canvas {
              id: animCanvas
              anchors.fill: parent
              renderTarget: Canvas.Image
              onAvailableChanged: if (available) requestPaint()
              Component.onCompleted: requestPaint()
              onPaint: {
                var ctx = getContext("2d")
                helpRoot.drawFeaturePreview(ctx, featCard.modelData.id, width, height, helpRoot.animPhase)
              }
              Connections {
                target: helpRoot
                function onAnimPhaseChanged() {
                  if (helpRoot.visible && helpRoot.selectedIndex < 0) animCanvas.requestPaint()
                }
              }
            }
          }

          Column {
            id: textCol
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - previewFrame.width - chevronTxt.implicitWidth - Style.space(18)
            spacing: Style.space(4)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: helpRoot.t(featCard.modelData.titleKey)
              color: helpRoot.fg
              font.family: helpRoot.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: helpRoot.t(featCard.modelData.descKey)
              color: helpRoot.dim
              font.family: helpRoot.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: helpRoot.t("helpTapGuide") + " ›"
              color: cardMouse.containsMouse ? helpRoot.accentColor : Qt.rgba(helpRoot.accentColor.r, helpRoot.accentColor.g, helpRoot.accentColor.b, 0.80)
              font.family: helpRoot.fontFamily
              font.pixelSize: Math.max(9, Style.font.caption - 1)
              font.bold: true
            }
          }

          Text {
            id: chevronTxt
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "›"
            color: cardMouse.containsMouse ? helpRoot.accentColor : helpRoot.dim
            font.family: helpRoot.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }

        MouseArea {
          id: cardMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: helpRoot.selectedIndex = featCard.index
        }
      }
    }
  }

  // =========================================================================
  // DETAIL WALKTHROUGH VIEW (selectedIndex >= 0)
  // =========================================================================
  Column {
    visible: helpRoot.selectedFeature !== null
    width: parent.width
    spacing: Style.space(12)

    // Large crisp scaled animated preview canvas
    Rectangle {
      id: detailPreviewFrame
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(parent.width, Style.space(320))
      height: Style.space(184)
      radius: helpRoot.corners.radius
      color: Qt.rgba(0.05, 0.06, 0.10, 0.94)
      border.width: 1
      border.color: Qt.rgba(helpRoot.accentColor.r, helpRoot.accentColor.g, helpRoot.accentColor.b, 0.40)
      clip: true

      Canvas {
        id: detailCanvas
        anchors.fill: parent
        renderTarget: Canvas.Image
        onAvailableChanged: if (available) requestPaint()
        onWidthChanged: if (available) requestPaint()
        onHeightChanged: if (available) requestPaint()
        onPaint: {
          if (!helpRoot.selectedFeature) return
          var ctx = getContext("2d")
          helpRoot.drawFeaturePreview(ctx, helpRoot.selectedFeature.id, width, height, helpRoot.animPhase)
        }
        Connections {
          target: helpRoot
          function onAnimPhaseChanged() {
            if (helpRoot.visible && helpRoot.selectedIndex >= 0) detailCanvas.requestPaint()
          }
          function onSelectedIndexChanged() {
            if (helpRoot.visible && helpRoot.selectedIndex >= 0) detailCanvas.requestPaint()
          }
        }
      }
    }

    // Plain-language title & description
    Column {
      width: parent.width
      spacing: Style.space(4)

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: helpRoot.selectedFeature ? helpRoot.t(helpRoot.selectedFeature.titleKey) : ""
        color: helpRoot.fg
        font.family: helpRoot.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: helpRoot.selectedFeature ? helpRoot.t(helpRoot.selectedFeature.descKey) : ""
        color: helpRoot.dim
        font.family: helpRoot.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // Numbered "How to do it" walkthrough card
    Rectangle {
      width: parent.width
      height: stepsCol.implicitHeight + Style.space(18)
      radius: helpRoot.corners.radius
      color: helpRoot.cardFillColor
      border.width: 1
      border.color: helpRoot.cardBorderColor

      Column {
        id: stepsCol
        x: Style.space(10)
        y: Style.space(9)
        width: parent.width - Style.space(20)
        spacing: Style.space(8)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: helpRoot.t("helpHowTo").toUpperCase()
          color: helpRoot.accentColor
          font.family: helpRoot.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.8
        }

        Repeater {
          model: helpRoot.selectedFeature ? helpRoot.selectedFeature.steps : []
          delegate: Row {
            id: stepRow
            required property int index
            required property string modelData
            width: stepsCol.width
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(20)
              height: Style.space(20)
              radius: width * 0.5
              color: Qt.rgba(helpRoot.accentColor.r, helpRoot.accentColor.g, helpRoot.accentColor.b, 0.22)
              border.width: 1
              border.color: Qt.rgba(helpRoot.accentColor.r, helpRoot.accentColor.g, helpRoot.accentColor.b, 0.65)
              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: String(stepRow.index + 1)
                color: helpRoot.accentColor
                font.family: helpRoot.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Text {
              width: parent.width - Style.space(28)
              anchors.verticalCenter: parent.verticalCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: helpRoot.t(stepRow.modelData)
              color: helpRoot.fg
              font.family: helpRoot.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }

    // Quick Tip box
    Rectangle {
      width: parent.width
      height: tipCol.implicitHeight + Style.space(16)
      radius: helpRoot.corners.control
      color: Qt.rgba(helpRoot.accentColor.r, helpRoot.accentColor.g, helpRoot.accentColor.b, 0.10)
      border.width: 1
      border.color: Qt.rgba(helpRoot.accentColor.r, helpRoot.accentColor.g, helpRoot.accentColor.b, 0.36)

      Column {
        id: tipCol
        x: Style.space(10)
        y: Style.space(8)
        width: parent.width - Style.space(20)
        spacing: Style.space(3)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "✦  " + helpRoot.t("helpQuickTip")
          color: helpRoot.accentColor
          font.family: helpRoot.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: helpRoot.selectedFeature ? helpRoot.t(helpRoot.selectedFeature.tipKey) : ""
          color: helpRoot.fg
          font.family: helpRoot.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // Footer action row: "← All features" + "Try it now →"
    Item {
      width: parent.width
      height: Math.max(allFeatBtn.implicitHeight, tryNowBtn.implicitHeight)

      Button {
        id: allFeatBtn
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        radius: helpRoot.corners.control
        text: helpRoot.t("helpAllFeatures")
        iconText: "󰁍"
        bordered: true
        foreground: helpRoot.dim
        fontFamily: helpRoot.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(10)
        verticalPadding: Style.space(4)
        onClicked: helpRoot.selectedIndex = -1
      }

      Button {
        id: tryNowBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        radius: helpRoot.corners.control
        text: helpRoot.t("helpTryNow") + " →"
        bordered: true
        selected: true
        accent: helpRoot.accentColor
        foreground: helpRoot.fg
        fontFamily: helpRoot.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(12)
        verticalPadding: Style.space(4)
        onClicked: {
          if (helpRoot.selectedFeature) helpRoot.tryFeature(helpRoot.selectedFeature.target)
        }
      }
    }
  }
}
