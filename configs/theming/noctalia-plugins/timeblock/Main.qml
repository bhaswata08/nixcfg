import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Main.qml — central state + business logic for the Time Blocks plugin.
//
// Data model (all user-authored, nothing about the schedule is hardcoded):
//   Block record = {
//     id:     stable string id (survives reordering; never the array index)
//     label:  free text
//     start:  minutes since local midnight (int)
//     end:    minutes since local midnight (int)
//     color:  semantic color key resolved via Color.resolveColorKey (e.g. "primary")
//     days:   array of weekday ints [0..6] (0=Sun) the block recurs on (template only)
//     notes:  optional free text
//     skipped:bool (today's instance only — mark a block as skipped without deleting)
//     templateId: id of the template block this instance came from ("" for ad-hoc)
//   }
//
// Two layers:
//   template          -> pluginApi.pluginSettings.template  (the recurring baseline)
//   today's instance  -> pluginApi.pluginSettings.today = { date, blocks }
// Today's instance is derived from the template once per day, then freely edited
// in-place. Editing today never touches the template unless the user explicitly
// calls saveTodayAsTemplate().
Item {
  id: root

  property var pluginApi: null

  // Working copies (reassigned on every mutation so bindings in the widgets fire).
  property var rawTemplate: []
  property var rawToday: []
  property string todayDate: ""

  // Live derived state, refreshed every tick by computeNow().
  property int nowSeconds: 0
  readonly property real nowMinutes: nowSeconds / 60
  property var currentBlock: null
  property string currentBlockId: ""
  property var nextBlock: null
  property int secondsRemaining: 0   // in current block, or until next block during a gap
  property bool inGap: true

  // User settings mirror.
  property bool notifyTransitions: false
  property int pushIncrement: 15
  property int defaultBlockMinutes: 30
  property string defaultColor: "primary"

  readonly property bool hasBlocks: rawToday.length > 0

  // Transition tracking for notifications. "__init__" means "not yet primed".
  property string lastActiveId: "__init__"

  // ============================================================
  // Initialization
  // ============================================================
  property bool _initialized: false

  onPluginApiChanged: if (pluginApi) initialize()
  Component.onCompleted: if (pluginApi) initialize()

  function initialize() {
    if (_initialized) return
    _initialized = true
    const s = pluginApi.pluginSettings
    const d = pluginApi?.manifest?.metadata?.defaultSettings

    if (s.template === undefined) s.template = []
    if (s.today === undefined) s.today = { "date": "", "blocks": [] }
    if (s.notifyTransitions === undefined) s.notifyTransitions = d?.notifyTransitions ?? false
    if (s.pushIncrement === undefined) s.pushIncrement = d?.pushIncrement ?? 15
    if (s.defaultBlockMinutes === undefined) s.defaultBlockMinutes = d?.defaultBlockMinutes ?? 30
    if (s.defaultColor === undefined) s.defaultColor = d?.defaultColor ?? "primary"

    rawTemplate = migrateBlocks((s.template || []).slice(), true)
    notifyTransitions = s.notifyTransitions
    pushIncrement = s.pushIncrement
    defaultBlockMinutes = s.defaultBlockMinutes
    defaultColor = s.defaultColor

    // Load today's instance; regenerate from template if it's for a previous day.
    const stored = s.today || { "date": "", "blocks": [] }
    if (stored.date === todayString() && Array.isArray(stored.blocks)) {
      todayDate = stored.date
      rawToday = sortBlocks(migrateBlocks(stored.blocks.slice(), false))
    } else {
      regenerateToday(true)
    }

    pluginApi.saveSettings()
    computeNow()
    Logger.i("TimeBlock", "Initialized: " + rawTemplate.length + " template blocks, " + rawToday.length + " blocks today")
  }

  // Fill in any missing fields so older saved data keeps working.
  function migrateBlocks(arr, isTemplate) {
    for (var i = 0; i < arr.length; i++) {
      var b = arr[i]
      if (b.id === undefined) b.id = genId()
      if (b.label === undefined) b.label = ""
      if (b.start === undefined) b.start = 0
      if (b.end === undefined) b.end = b.start + 30
      if (b.color === undefined) b.color = "primary"
      if (b.notes === undefined) b.notes = ""
      if (isTemplate) {
        if (!Array.isArray(b.days)) b.days = [0, 1, 2, 3, 4, 5, 6]
      } else {
        if (b.skipped === undefined) b.skipped = false
        if (b.templateId === undefined) b.templateId = ""
      }
    }
    return arr
  }

  // ============================================================
  // Time / date helpers
  // ============================================================
  function pad2(n) { return (n < 10 ? "0" : "") + n }

  function todayString() {
    var d = new Date()
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
  }

  function currentWeekday() { return new Date().getDay() }

  // "9:30" style label from minutes-since-midnight.
  function fmtTime(mins) {
    var m = ((mins % 1440) + 1440) % 1440
    return pad2(Math.floor(m / 60)) + ":" + pad2(m % 60)
  }

  function sortBlocks(arr) {
    return arr.slice().sort(function (a, b) {
      if (a.start !== b.start) return a.start - b.start
      return a.end - b.end
    })
  }

  function genId() {
    return "blk-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e6).toString(36)
  }

  // ============================================================
  // Persistence
  // ============================================================
  function saveTemplate() {
    if (!pluginApi) return
    rawTemplate = sortBlocks(rawTemplate)
    pluginApi.pluginSettings.template = rawTemplate.slice()
    pluginApi.saveSettings()
  }

  function saveToday() {
    if (!pluginApi) return
    rawToday = sortBlocks(rawToday)
    pluginApi.pluginSettings.today = { "date": todayDate, "blocks": rawToday.slice() }
    pluginApi.saveSettings()
    computeNow()
  }

  // ============================================================
  // Today's instance <- template derivation
  // ============================================================
  function regenerateToday(persist) {
    var wd = currentWeekday()
    var out = []
    for (var i = 0; i < rawTemplate.length; i++) {
      var t = rawTemplate[i]
      if (Array.isArray(t.days) && t.days.indexOf(wd) === -1) continue
      out.push({
        "id": genId(),
        "label": t.label,
        "start": t.start,
        "end": t.end,
        "color": t.color,
        "notes": t.notes,
        "skipped": false,
        "templateId": t.id
      })
    }
    rawToday = sortBlocks(out)
    todayDate = todayString()
    lastActiveId = "__init__"
    if (persist !== false) saveToday()
  }

  // ============================================================
  // Live tracking
  // ============================================================
  Timer {
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.computeNow()
  }

  function computeNow() {
    var d = new Date()

    // Midnight rollover: rebuild today's instance from the template.
    if (todayDate !== "" && todayString() !== todayDate) {
      regenerateToday(true)
      return
    }

    nowSeconds = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()
    var nm = nowSeconds / 60

    var cur = null
    var nxt = null
    for (var i = 0; i < rawToday.length; i++) {
      var b = rawToday[i]
      if (b.skipped) continue
      if (nm >= b.start && nm < b.end) {
        // Overlap handling: pick the most-recently-started covering block.
        if (cur === null || b.start > cur.start) cur = b
      } else if (b.start > nm) {
        if (nxt === null || b.start < nxt.start) nxt = b
      }
    }

    currentBlock = cur
    nextBlock = nxt
    currentBlockId = cur ? cur.id : ""
    inGap = (cur === null)

    if (cur) secondsRemaining = Math.max(0, Math.round(cur.end * 60 - nowSeconds))
    else if (nxt) secondsRemaining = Math.max(0, Math.round(nxt.start * 60 - nowSeconds))
    else secondsRemaining = 0

    // Notify on transition between blocks.
    if (lastActiveId === "__init__") {
      lastActiveId = currentBlockId
    } else if (currentBlockId !== lastActiveId) {
      lastActiveId = currentBlockId
      if (notifyTransitions) {
        if (cur) {
          ToastService.showNotice(
            pluginApi?.tr("toast.title") || "Time Blocks",
            (pluginApi?.tr("toast.now") || "Now") + ": " + cur.label + " (" + fmtTime(cur.start) + "–" + fmtTime(cur.end) + ")",
            "calendar-clock")
        } else {
          ToastService.showNotice(
            pluginApi?.tr("toast.title") || "Time Blocks",
            pluginApi?.tr("toast.unscheduled") || "Unscheduled",
            "calendar-clock")
        }
      }
    }
  }

  // ============================================================
  // Today's instance CRUD (used by the Panel)
  // ============================================================
  function addTodayBlock(label, start, end, color, notes) {
    rawToday.push({
      "id": genId(),
      "label": label || (pluginApi?.tr("block.untitled") || "New block"),
      "start": clampMin(start),
      "end": clampMin(end),
      "color": color || defaultColor,
      "notes": notes || "",
      "skipped": false,
      "templateId": ""
    })
    saveToday()
  }

  function updateTodayBlock(id, updates) {
    var idx = indexOf(rawToday, id)
    if (idx === -1) return false
    applyUpdates(rawToday[idx], updates)
    saveToday()
    return true
  }

  function deleteTodayBlock(id) {
    var idx = indexOf(rawToday, id)
    if (idx === -1) return false
    rawToday.splice(idx, 1)
    saveToday()
    return true
  }

  function setTodaySkipped(id, skipped) {
    return updateTodayBlock(id, { "skipped": skipped })
  }

  // ============================================================
  // Quick "override today" actions (low-friction, used often)
  // ============================================================

  // Shrink the current block so it ends right now.
  function endCurrentNow() {
    if (!currentBlock) return false
    var nm = Math.max(currentBlock.start + 1, Math.round(nowMinutes))
    return updateTodayBlock(currentBlock.id, { "end": nm })
  }

  // Insert an ad-hoc block starting now for `durationMin` minutes.
  function insertNowBlock(label, durationMin) {
    var start = Math.round(nowMinutes)
    var dur = durationMin && durationMin > 0 ? durationMin : defaultBlockMinutes
    addTodayBlock(label || (pluginApi?.tr("block.adhoc") || "Ad-hoc"), start, Math.min(1440, start + dur), defaultColor, "")
  }

  // Push every not-yet-started block later by N minutes.
  function pushRemaining(mins) {
    var nm = Math.round(nowMinutes)
    var changed = false
    for (var i = 0; i < rawToday.length; i++) {
      var b = rawToday[i]
      if (b.skipped) continue
      if (b.start >= nm) {
        b.start = clampMin(b.start + mins)
        b.end = clampMin(b.end + mins)
        changed = true
      }
    }
    if (changed) saveToday()
    return changed
  }

  function resetTodayFromTemplate() {
    regenerateToday(true)
    if (pluginApi)
      ToastService.showNotice(pluginApi.tr("toast.title") || "Time Blocks",
                              pluginApi.tr("toast.reset-today") || "Today reset from template", "refresh")
  }

  // Explicit: overwrite the standing template with today's blocks (daily recurrence).
  function saveTodayAsTemplate() {
    var out = []
    for (var i = 0; i < rawToday.length; i++) {
      var b = rawToday[i]
      if (b.skipped) {
        // Skipped blocks are not in the new template, so they came from nothing.
        b.templateId = ""
        continue
      }
      var tid = genId()
      b.templateId = tid
      out.push({
        "id": tid,
        "label": b.label,
        "start": b.start,
        "end": b.end,
        "color": b.color,
        "notes": b.notes,
        "days": [0, 1, 2, 3, 4, 5, 6]
      })
    }
    rawTemplate = sortBlocks(out)
    saveTemplate()
    saveToday()
    if (pluginApi)
      ToastService.showNotice(pluginApi.tr("toast.title") || "Time Blocks",
                              pluginApi.tr("toast.saved-template") || "Template updated from today", "device-floppy")
  }

  // ============================================================
  // Template CRUD (used by Settings)
  // ============================================================
  function addTemplateBlock(label, start, end, color, days, notes) {
    rawTemplate.push({
      "id": genId(),
      "label": label || (pluginApi?.tr("block.untitled") || "New block"),
      "start": clampMin(start),
      "end": clampMin(end),
      "color": color || defaultColor,
      "days": Array.isArray(days) ? days.slice() : [0, 1, 2, 3, 4, 5, 6],
      "notes": notes || ""
    })
    saveTemplate()
  }

  function updateTemplateBlock(id, updates) {
    var idx = indexOf(rawTemplate, id)
    if (idx === -1) return false
    applyUpdates(rawTemplate[idx], updates)
    saveTemplate()
    return true
  }

  function deleteTemplateBlock(id) {
    var idx = indexOf(rawTemplate, id)
    if (idx === -1) return false
    rawTemplate.splice(idx, 1)
    saveTemplate()
    return true
  }

  function setNotifyTransitions(v) {
    notifyTransitions = v
    if (pluginApi) {
      pluginApi.pluginSettings.notifyTransitions = v
      pluginApi.saveSettings()
    }
  }

  // ============================================================
  // Overlap detection (warn, don't block)
  // ============================================================
  // Returns the ids of blocks in `arr` that overlap another non-skipped block.
  function overlappingIds(arr) {
    var res = []
    var a = sortBlocks(arr)
    for (var i = 0; i < a.length; i++) {
      if (a[i].skipped) continue
      for (var j = i + 1; j < a.length; j++) {
        if (a[j].skipped) continue
        if (a[j].start < a[i].end && a[i].start < a[j].end) {
          if (res.indexOf(a[i].id) === -1) res.push(a[i].id)
          if (res.indexOf(a[j].id) === -1) res.push(a[j].id)
        }
      }
    }
    return res
  }

  // ============================================================
  // Small helpers
  // ============================================================
  function clampMin(m) { return Math.max(0, Math.min(1440, Math.round(m))) }

  function indexOf(arr, id) {
    for (var i = 0; i < arr.length; i++) if (arr[i].id === id) return i
    return -1
  }

  function applyUpdates(b, u) {
    if (u.label !== undefined) b.label = u.label
    if (u.start !== undefined) b.start = clampMin(u.start)
    if (u.end !== undefined) b.end = clampMin(u.end)
    if (u.color !== undefined) b.color = u.color
    if (u.notes !== undefined) b.notes = u.notes
    if (u.days !== undefined && Array.isArray(u.days)) b.days = u.days.slice()
    if (u.skipped !== undefined) b.skipped = u.skipped
  }

  // ============================================================
  // IPC — scriptable from keybinds
  // ============================================================
  IpcHandler {
    target: "plugin:timeblock"

    // Open/close the panel.
    function toggle() {
      if (!root.pluginApi) return
      root.pluginApi.withCurrentScreen(function (screen) { root.pluginApi.togglePanel(screen) })
    }

    // Query the currently active block (JSON, or {"active":false} in a gap).
    function current(): string {
      if (!root.currentBlock)
        return JSON.stringify({ "active": false, "next": root.nextBlock ? root.nextBlock.label : null,
                                "secondsUntilNext": root.nextBlock ? root.secondsRemaining : null })
      return JSON.stringify({
        "active": true,
        "id": root.currentBlock.id,
        "label": root.currentBlock.label,
        "start": root.fmtTime(root.currentBlock.start),
        "end": root.fmtTime(root.currentBlock.end),
        "secondsRemaining": root.secondsRemaining
      })
    }

    // Advance past the current block (ends it now; the next block becomes active).
    function next() { root.endCurrentNow() }

    // Override-today actions.
    function endNow() { root.endCurrentNow() }
    function insertNow() { root.insertNowBlock("", 0) }
    function push(mins: string) {
      var n = parseInt(mins)
      root.pushRemaining(isNaN(n) ? root.pushIncrement : n)
    }
    function resetToday() { root.resetTodayFromTemplate() }
  }
}
