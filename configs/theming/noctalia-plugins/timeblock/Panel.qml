import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Widgets

// Full day view: a proportional time axis with a "now" line, plus an editable
// list of today's blocks and the low-friction "override today" actions.
// All edits here mutate today's instance only — never the saved template.
Item {
  id: root

  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property bool panelReady: mainInstance !== null && mainInstance !== undefined

  property real contentPreferredWidth: 560 * Style.uiScaleRatio
  property real contentPreferredHeight: 620 * Style.uiScaleRatio
  anchors.fill: parent

  // Palette offered when picking a block color (semantic theme keys).
  readonly property var palette: ["primary", "secondary", "tertiary", "error"]

  // Live view of today's blocks (already sorted by Main).
  readonly property var blocks: mainInstance ? mainInstance.rawToday : []
  readonly property int nowMin: mainInstance ? Math.round(mainInstance.nowMinutes) : 0
  readonly property var overlaps: mainInstance ? mainInstance.overlappingIds(blocks) : []

  // --- Editor state (inline form). editId === "" -> adding a new block. ---
  property bool editing: false
  property string editId: ""
  property string editLabel: ""
  property int editStart: 9 * 60
  property int editEnd: 10 * 60
  property string editColor: "primary"
  property string editNotes: ""

  function beginAdd() {
    editing = true
    editId = ""
    editLabel = ""
    var base = mainInstance ? Math.round(mainInstance.nowMinutes / 5) * 5 : 540
    editStart = base
    editEnd = Math.min(1440, base + (mainInstance ? mainInstance.defaultBlockMinutes : 30))
    editColor = mainInstance ? mainInstance.defaultColor : "primary"
    editNotes = ""
  }

  function beginEdit(b) {
    editing = true
    editId = b.id
    editLabel = b.label
    editStart = b.start
    editEnd = b.end
    editColor = b.color
    editNotes = b.notes || ""
  }

  function commitEdit() {
    if (!mainInstance) return
    var s = editStart
    var e = editEnd
    if (e <= s) e = Math.min(1440, s + 5)
    if (editId === "") {
      mainInstance.addTodayBlock(editLabel, s, e, editColor, editNotes)
    } else {
      mainInstance.updateTodayBlock(editId, { "label": editLabel, "start": s, "end": e, "color": editColor, "notes": editNotes })
    }
    editing = false
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"
    visible: panelReady

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      // ---------- Header ----------
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NIcon { icon: "calendar-clock"; pointSize: Style.fontSizeXL; color: Color.mPrimary }
        NText {
          text: pluginApi?.tr("panel.title") || "Time Blocks"
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
        }
        Item { Layout.fillWidth: true }
        NText {
          text: Qt.formatDate(new Date(), "ddd, MMM d")
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
        }
        NIconButton {
          icon: "plus"
          tooltipText: pluginApi?.tr("panel.add") || "Add block"
          onClicked: root.beginAdd()
        }
      }

      // ---------- Proportional time axis with "now" line ----------
      NBox {
        id: axisBox
        Layout.fillWidth: true
        Layout.preferredHeight: 64
        visible: root.blocks.length > 0

        // Compute a day window that covers all blocks and the current time.
        property int winStart: {
          var lo = root.nowMin
          for (var i = 0; i < root.blocks.length; i++) lo = Math.min(lo, root.blocks[i].start)
          return Math.max(0, Math.floor(lo / 60) * 60)
        }
        property int winEnd: {
          var hi = root.nowMin
          for (var i = 0; i < root.blocks.length; i++) hi = Math.max(hi, root.blocks[i].end)
          return Math.min(1440, Math.ceil(hi / 60) * 60)
        }
        property int span: Math.max(1, winEnd - winStart)

        Item {
          id: axis
          anchors.fill: parent
          anchors.margins: Style.marginS

          Repeater {
            model: root.blocks
            delegate: Rectangle {
              readonly property var b: modelData
              visible: !b.skipped
              x: axis.width * (b.start - axisBox.winStart) / axisBox.span
              width: Math.max(2, axis.width * (b.end - b.start) / axisBox.span)
              y: 4
              height: axis.height - 20
              radius: Style.radiusS
              color: Qt.alpha(Color.resolveColorKey(b.color), b.id === root.mainInstance?.currentBlockId ? 0.95 : 0.6)
              border.width: b.id === root.mainInstance?.currentBlockId ? 2 : 0
              border.color: Color.mOnSurface

              NText {
                anchors.centerIn: parent
                width: parent.width - 4
                visible: parent.width > 42
                text: b.label
                pointSize: Style.fontSizeXS
                color: Color.mOnPrimary
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.beginEdit(b)
              }
            }
          }

          // Hour ticks / labels along the bottom.
          Repeater {
            model: Math.floor(axisBox.span / 60) + 1
            delegate: NText {
              readonly property int mins: axisBox.winStart + index * 60
              x: axis.width * (mins - axisBox.winStart) / axisBox.span - width / 2
              anchors.bottom: parent.bottom
              text: root.mainInstance ? root.mainInstance.fmtTime(mins) : ""
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }
          }

          // "Now" line.
          Rectangle {
            visible: root.nowMin >= axisBox.winStart && root.nowMin <= axisBox.winEnd
            width: 2
            height: axis.height - 12
            color: Color.mError
            x: axis.width * (root.nowMin - axisBox.winStart) / axisBox.span
            Rectangle { width: 8; height: 8; radius: 4; color: Color.mError; anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top }
          }
        }
      }

      // ---------- Quick override-today actions ----------
      Flow {
        Layout.fillWidth: true
        spacing: Style.marginS
        visible: !root.editing

        NButton {
          text: pluginApi?.tr("action.end-now") || "End now"
          icon: "player-stop"
          fontSize: Style.fontSizeXS
          enabled: root.mainInstance && root.mainInstance.currentBlock !== null
          onClicked: root.mainInstance.endCurrentNow()
        }
        NButton {
          text: pluginApi?.tr("action.insert-now") || "Insert now"
          icon: "plus"
          fontSize: Style.fontSizeXS
          onClicked: root.mainInstance.insertNowBlock("", 0)
        }
        NButton {
          text: "+" + (root.mainInstance ? root.mainInstance.pushIncrement : 15) + "m"
          icon: "arrow-right"
          fontSize: Style.fontSizeXS
          enabled: root.blocks.length > 0
          onClicked: root.mainInstance.pushRemaining(root.mainInstance.pushIncrement)
        }
        NButton {
          text: pluginApi?.tr("action.reset-today") || "Reset today"
          icon: "refresh"
          fontSize: Style.fontSizeXS
          onClicked: root.mainInstance.resetTodayFromTemplate()
        }
        NButton {
          text: pluginApi?.tr("action.save-template") || "Save as template"
          icon: "device-floppy"
          fontSize: Style.fontSizeXS
          enabled: root.blocks.length > 0
          onClicked: root.mainInstance.saveTodayAsTemplate()
        }
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

          // Start / end time via hour + minute spinners.
          GridLayout {
            columns: 5
            columnSpacing: Style.marginS
            rowSpacing: Style.marginXS

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

          NTextInput {
            Layout.fillWidth: true
            placeholderText: pluginApi?.tr("editor.notes") || "Notes (optional)"
            text: root.editNotes
            onTextChanged: root.editNotes = text
          }

          NText {
            Layout.fillWidth: true
            visible: root.editEnd <= root.editStart
            text: pluginApi?.tr("editor.warn-times") || "End time must be after start — it will be nudged."
            color: Color.mError
            pointSize: Style.fontSizeXS
            wrapMode: Text.WordWrap
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            NButton {
              text: pluginApi?.tr("editor.save") || "Save"
              icon: "check"
              onClicked: root.commitEdit()
            }
            NButton {
              text: pluginApi?.tr("editor.cancel") || "Cancel"
              icon: "x"
              outlined: true
              onClicked: root.editing = false
            }
            Item { Layout.fillWidth: true }
            NButton {
              visible: root.editId !== ""
              text: pluginApi?.tr("editor.delete") || "Delete"
              icon: "trash"
              backgroundColor: Color.mError
              textColor: Color.mOnError
              onClicked: { root.mainInstance.deleteTodayBlock(root.editId); root.editing = false }
            }
          }
        }
      }

      // ---------- Block list ----------
      NScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ColumnLayout {
          width: parent.width
          spacing: Style.marginS

          // Empty / setup state.
          ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.marginXL
            spacing: Style.marginS
            visible: root.blocks.length === 0
            NIcon { icon: "calendar-off"; pointSize: Style.fontSizeXXL; color: Color.mOnSurfaceVariant; Layout.alignment: Qt.AlignHCenter }
            NText {
              Layout.alignment: Qt.AlignHCenter
              text: pluginApi?.tr("panel.empty-title") || "No blocks scheduled today"
              color: Color.mOnSurface
              font.weight: Style.fontWeightMedium
            }
            NText {
              Layout.alignment: Qt.AlignHCenter
              text: pluginApi?.tr("panel.empty-hint") || "Add a block, or build a recurring template in Settings."
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }
          }

          Repeater {
            model: root.blocks
            delegate: Rectangle {
              id: blockCard
              readonly property var b: modelData
              readonly property bool isCurrent: root.mainInstance && b.id === root.mainInstance.currentBlockId
              readonly property bool isOverlap: root.overlaps.indexOf(b.id) !== -1
              Layout.fillWidth: true
              implicitHeight: rowLayout.implicitHeight + Style.marginM
              radius: Style.radiusM
              color: isCurrent ? Color.mSurfaceVariant : "transparent"
              border.width: isCurrent ? 1 : 0
              border.color: Color.resolveColorKey(b.color)
              opacity: b.skipped ? 0.45 : 1.0

              RowLayout {
                id: rowLayout
                anchors.fill: parent
                anchors.margins: Style.marginS
                spacing: Style.marginS

                // Color stripe.
                Rectangle { width: 4; Layout.fillHeight: true; radius: 2; color: Color.resolveColorKey(b.color) }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0
                  RowLayout {
                    spacing: Style.marginS
                    NText {
                      text: b.label
                      font.weight: Style.fontWeightMedium
                      color: Color.mOnSurface
                      font.strikeout: b.skipped
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                    NText {
                      visible: blockCard.isCurrent
                      text: pluginApi?.tr("panel.now") || "NOW"
                      pointSize: Style.fontSizeXS
                      font.weight: Style.fontWeightBold
                      color: Color.mPrimary
                    }
                    NIcon {
                      visible: blockCard.isOverlap
                      icon: "alert-triangle"
                      pointSize: Style.fontSizeS
                      color: Color.mError
                    }
                  }
                  NText {
                    text: (root.mainInstance ? root.mainInstance.fmtTime(b.start) + "–" + root.mainInstance.fmtTime(b.end) : "")
                          + (b.notes ? "  ·  " + b.notes : "")
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                }

                NIconButton {
                  icon: b.skipped ? "eye" : "eye-off"
                  tooltipText: b.skipped ? (pluginApi?.tr("panel.unskip") || "Un-skip") : (pluginApi?.tr("panel.skip") || "Skip")
                  implicitWidth: Style.baseWidgetSize * 0.8
                  implicitHeight: Style.baseWidgetSize * 0.8
                  onClicked: root.mainInstance.setTodaySkipped(b.id, !b.skipped)
                }
                NIconButton {
                  icon: "pencil"
                  tooltipText: pluginApi?.tr("editor.edit") || "Edit"
                  implicitWidth: Style.baseWidgetSize * 0.8
                  implicitHeight: Style.baseWidgetSize * 0.8
                  onClicked: root.beginEdit(b)
                }
                NIconButton {
                  icon: "trash"
                  tooltipText: pluginApi?.tr("editor.delete") || "Delete"
                  color: Color.mError
                  implicitWidth: Style.baseWidgetSize * 0.8
                  implicitHeight: Style.baseWidgetSize * 0.8
                  onClicked: root.mainInstance.deleteTodayBlock(b.id)
                }
              }
            }
          }
        }
      }
    }
  }
}
