import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

// Template management: create/edit/delete the recurring baseline blocks with
// per-weekday recurrence, plus the transition-notification toggle. Template
// edits persist immediately via mainInstance; the host also calls saveSettings()
// on close for the notification toggle.
ColumnLayout {
  id: root

  property var pluginApi: null
  readonly property var mainInstance: pluginApi?.mainInstance

  spacing: Style.marginM

  readonly property var palette: ["primary", "secondary", "tertiary", "error"]
  readonly property var weekdayNames: ["S", "M", "T", "W", "T", "F", "S"]

  readonly property var template: mainInstance ? mainInstance.rawTemplate : []

  property bool editNotify: false

  // --- Editor state. editId === "" -> adding. ---
  property bool editing: false
  property string editId: ""
  property string editLabel: ""
  property int editStart: 9 * 60
  property int editEnd: 10 * 60
  property string editColor: "primary"
  property string editNotes: ""
  property var editDays: [0, 1, 2, 3, 4, 5, 6]

  onPluginApiChanged: if (pluginApi) loadSettings()
  Component.onCompleted: if (pluginApi) loadSettings()

  function loadSettings() {
    const s = pluginApi?.pluginSettings
    const d = pluginApi?.manifest?.metadata?.defaultSettings
    root.editNotify = s?.notifyTransitions ?? d?.notifyTransitions ?? false
    notifyToggle.checked = root.editNotify
  }

  // Called by the host when the settings surface closes.
  function saveSettings() {
    if (!pluginApi) return
    pluginApi.pluginSettings.notifyTransitions = root.editNotify
    pluginApi.saveSettings()
    if (mainInstance) mainInstance.notifyTransitions = root.editNotify
  }

  function beginAdd() {
    editing = true; editId = ""; editLabel = ""
    editStart = 9 * 60; editEnd = 10 * 60
    editColor = "primary"; editNotes = ""
    editDays = [0, 1, 2, 3, 4, 5, 6]
  }

  function beginEdit(b) {
    editing = true; editId = b.id; editLabel = b.label
    editStart = b.start; editEnd = b.end
    editColor = b.color; editNotes = b.notes || ""
    editDays = Array.isArray(b.days) ? b.days.slice() : [0, 1, 2, 3, 4, 5, 6]
  }

  function toggleDay(d) {
    var arr = editDays.slice()
    var i = arr.indexOf(d)
    if (i === -1) arr.push(d); else arr.splice(i, 1)
    editDays = arr
  }

  function commitEdit() {
    if (!mainInstance) return
    var e = editEnd <= editStart ? Math.min(1440, editStart + 5) : editEnd
    if (editId === "") {
      mainInstance.addTemplateBlock(editLabel, editStart, e, editColor, editDays, editNotes)
    } else {
      mainInstance.updateTemplateBlock(editId, { "label": editLabel, "start": editStart, "end": e, "color": editColor, "days": editDays, "notes": editNotes })
    }
    editing = false
  }

  function daysSummary(days) {
    if (!Array.isArray(days) || days.length === 7) return pluginApi?.tr("settings.every-day") || "Every day"
    if (days.length === 0) return pluginApi?.tr("settings.never") || "Never"
    var wk = [1, 2, 3, 4, 5]
    if (days.length === 5 && wk.every(d => days.indexOf(d) !== -1)) return pluginApi?.tr("settings.weekdays") || "Weekdays"
    return days.slice().sort().map(d => root.weekdayNames[d]).join(" ")
  }

  // ---------- Header ----------
  RowLayout {
    Layout.fillWidth: true
    NText {
      text: pluginApi?.tr("settings.template-title") || "Recurring template"
      pointSize: Style.fontSizeL
      font.weight: Style.fontWeightBold
      color: Color.mOnSurface
      Layout.fillWidth: true
    }
    NButton {
      text: pluginApi?.tr("panel.add") || "Add block"
      icon: "plus"
      fontSize: Style.fontSizeXS
      onClicked: root.beginAdd()
    }
  }
  NText {
    Layout.fillWidth: true
    text: pluginApi?.tr("settings.template-desc") || "The baseline day. Each day, today's schedule is generated from these blocks; editing today never changes this template."
    pointSize: Style.fontSizeS
    color: Color.mOnSurfaceVariant
    wrapMode: Text.WordWrap
  }

  // ---------- Inline editor ----------
  NBox {
    Layout.fillWidth: true
    visible: root.editing
    implicitHeight: editorCol.implicitHeight + Style.marginM * 2

    ColumnLayout {
      id: editorCol
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginS

      NText {
        text: root.editId === "" ? (pluginApi?.tr("editor.new") || "New block") : (pluginApi?.tr("editor.edit") || "Edit block")
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      NTextInput {
        Layout.fillWidth: true
        placeholderText: pluginApi?.tr("editor.label") || "Label"
        text: root.editLabel
        onTextChanged: root.editLabel = text
      }

      GridLayout {
        columns: 5
        columnSpacing: Style.marginS
        NText { text: pluginApi?.tr("editor.start") || "Start"; color: Color.mOnSurfaceVariant; Layout.alignment: Qt.AlignVCenter }
        NSpinBox { from: 0; to: 23; value: Math.floor(root.editStart / 60); onValueChanged: root.editStart = value * 60 + (root.editStart % 60) }
        NText { text: ":"; color: Color.mOnSurfaceVariant }
        NSpinBox { from: 0; to: 55; stepSize: 5; value: root.editStart % 60; onValueChanged: root.editStart = Math.floor(root.editStart / 60) * 60 + value }
        Item { Layout.fillWidth: true }
        NText { text: pluginApi?.tr("editor.end") || "End"; color: Color.mOnSurfaceVariant; Layout.alignment: Qt.AlignVCenter }
        NSpinBox { from: 0; to: 23; value: Math.floor(root.editEnd / 60); onValueChanged: root.editEnd = value * 60 + (root.editEnd % 60) }
        NText { text: ":"; color: Color.mOnSurfaceVariant }
        NSpinBox { from: 0; to: 55; stepSize: 5; value: root.editEnd % 60; onValueChanged: root.editEnd = Math.floor(root.editEnd / 60) * 60 + value }
        Item { Layout.fillWidth: true }
      }

      // Color palette.
      RowLayout {
        spacing: Style.marginS
        NText { text: pluginApi?.tr("editor.color") || "Color"; color: Color.mOnSurfaceVariant }
        Repeater {
          model: root.palette
          delegate: Rectangle {
            width: 22; height: 22; radius: 11
            color: Color.resolveColorKey(modelData)
            border.width: root.editColor === modelData ? 3 : 0
            border.color: Color.mOnSurface
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.editColor = modelData }
          }
        }
      }

      // Weekday recurrence.
      RowLayout {
        spacing: Style.marginXS
        NText { text: pluginApi?.tr("editor.repeat") || "Repeat"; color: Color.mOnSurfaceVariant }
        Repeater {
          model: 7
          delegate: Rectangle {
            readonly property bool on: root.editDays.indexOf(index) !== -1
            width: 26; height: 26; radius: 13
            color: on ? Color.mPrimary : "transparent"
            border.width: 1
            border.color: on ? Color.mPrimary : Color.mOutline
            NText {
              anchors.centerIn: parent
              text: root.weekdayNames[index]
              color: on ? Color.mOnPrimary : Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleDay(index) }
          }
        }
      }

      NTextInput {
        Layout.fillWidth: true
        placeholderText: pluginApi?.tr("editor.notes") || "Notes (optional)"
        text: root.editNotes
        onTextChanged: root.editNotes = text
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NButton { text: pluginApi?.tr("editor.save") || "Save"; icon: "check"; onClicked: root.commitEdit() }
        NButton { text: pluginApi?.tr("editor.cancel") || "Cancel"; icon: "x"; outlined: true; onClicked: root.editing = false }
        Item { Layout.fillWidth: true }
        NButton {
          visible: root.editId !== ""
          text: pluginApi?.tr("editor.delete") || "Delete"
          icon: "trash"
          backgroundColor: Color.mError
          textColor: Color.mOnError
          onClicked: { root.mainInstance.deleteTemplateBlock(root.editId); root.editing = false }
        }
      }
    }
  }

  // ---------- Template block list ----------
  NText {
    Layout.fillWidth: true
    visible: root.template.length === 0 && !root.editing
    text: pluginApi?.tr("settings.template-empty") || "No template blocks yet. Add blocks to define your standing day plan."
    pointSize: Style.fontSizeS
    color: Color.mOnSurfaceVariant
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.template
    delegate: Rectangle {
      readonly property var b: modelData
      Layout.fillWidth: true
      implicitHeight: tRow.implicitHeight + Style.marginM
      radius: Style.radiusM
      color: "transparent"

      RowLayout {
        id: tRow
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginS

        Rectangle { width: 4; Layout.fillHeight: true; radius: 2; color: Color.resolveColorKey(b.color) }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0
          NText {
            text: b.label
            font.weight: Style.fontWeightMedium
            color: Color.mOnSurface
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
          NText {
            text: (root.mainInstance ? root.mainInstance.fmtTime(b.start) + "–" + root.mainInstance.fmtTime(b.end) : "")
                  + "  ·  " + root.daysSummary(b.days)
                  + (b.notes ? "  ·  " + b.notes : "")
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
        }

        NIconButton {
          icon: "pencil"
          implicitWidth: Style.baseWidgetSize * 0.8
          implicitHeight: Style.baseWidgetSize * 0.8
          onClicked: root.beginEdit(b)
        }
        NIconButton {
          icon: "trash"
          color: Color.mError
          implicitWidth: Style.baseWidgetSize * 0.8
          implicitHeight: Style.baseWidgetSize * 0.8
          onClicked: root.mainInstance.deleteTemplateBlock(b.id)
        }
      }
    }
  }

  NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginS; Layout.bottomMargin: Style.marginS }

  // ---------- Notifications toggle ----------
  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: notifyToggle.implicitHeight
    NToggle {
      id: notifyToggle
      anchors.fill: parent
      label: pluginApi?.tr("settings.notify") || "Notify on block transitions"
      description: pluginApi?.tr("settings.notify-desc") || "Show a toast when the active block changes"
      checked: root.editNotify
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.editNotify = !root.editNotify
        notifyToggle.checked = root.editNotify
        if (root.mainInstance) root.mainInstance.setNotifyTransitions(root.editNotify)
      }
    }
  }
}
