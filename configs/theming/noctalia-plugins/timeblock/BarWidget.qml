import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import qs.Services.System

// Compact bar indicator: shows the active block's label + time remaining,
// or "Unscheduled" during a gap. Left-click opens the panel; right-click menu
// exposes the quick override actions.
Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property var current: mainInstance ? mainInstance.currentBlock : null
  readonly property bool inGap: mainInstance ? mainInstance.inGap : true
  readonly property bool hasBlocks: mainInstance ? mainInstance.hasBlocks : false

  readonly property string barPosition: Settings.data.bar.position || "top"
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"

  readonly property color accent: current && mainInstance
                                  ? Color.resolveColorKey(current.color)
                                  : Color.mOnSurfaceVariant

  readonly property real contentWidth: {
    if (barIsVertical) return Style.capsuleHeight
    return contentRow.implicitWidth + Style.marginM * 2
  }
  implicitWidth: contentWidth
  implicitHeight: Style.capsuleHeight

  // Short remaining string: "1h05m" / "45m" / "<1m".
  function fmtRemaining(seconds) {
    if (seconds <= 0) return ""
    var mins = Math.ceil(seconds / 60)
    var h = Math.floor(mins / 60)
    var m = mins % 60
    if (h > 0) return h + "h" + (m < 10 ? "0" : "") + m + "m"
    if (mins < 1) return "<1m"
    return m + "m"
  }

  readonly property string labelText: {
    if (!mainInstance || !hasBlocks) return pluginApi?.tr("bar.empty") || "No schedule"
    if (current) return current.label
    return pluginApi?.tr("bar.unscheduled") || "Unscheduled"
  }

  readonly property string subText: {
    if (!mainInstance || !hasBlocks) return ""
    if (current) return fmtRemaining(mainInstance.secondsRemaining) + " " + (pluginApi?.tr("bar.left") || "left")
    if (mainInstance.nextBlock) return (pluginApi?.tr("bar.in") || "in") + " " + fmtRemaining(mainInstance.secondsRemaining)
    return ""
  }

  Rectangle {
    id: visualCapsule
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.contentWidth
    height: root.implicitHeight
    radius: Style.radiusL
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.marginS

      // Category color dot / clock icon.
      Rectangle {
        visible: !root.barIsVertical && root.current !== null
        width: Style.fontSizeS
        height: Style.fontSizeS
        radius: width / 2
        color: root.accent
        Layout.alignment: Qt.AlignVCenter
      }

      NIcon {
        visible: root.barIsVertical || root.current === null
        icon: root.current ? "calendar-clock" : "calendar-off"
        applyUiScale: false
        color: mouseArea.containsMouse ? Color.mOnHover : (root.current ? root.accent : Color.mOnSurface)
      }

      NText {
        visible: !root.barIsVertical
        text: root.labelText
        pointSize: Style.barFontSize
        font.weight: root.current ? Style.fontWeightMedium : Style.fontWeightRegular
        color: mouseArea.containsMouse ? Color.mOnHover : (root.current ? root.accent : Color.mOnSurface)
        elide: Text.ElideRight
        Layout.maximumWidth: 160
      }

      NText {
        visible: !root.barIsVertical && root.subText.length > 0
        text: root.subText
        family: Settings.data.ui.fontFixed
        pointSize: Style.barFontSize
        color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu
    model: {
      var items = []
      if (mainInstance && mainInstance.currentBlock) {
        items.push({ "label": pluginApi.tr("action.end-now") || "End current now", "action": "end-now", "icon": "player-stop" })
      }
      items.push({ "label": pluginApi.tr("action.insert-now") || "Insert block now", "action": "insert-now", "icon": "plus" })
      if (mainInstance && mainInstance.hasBlocks) {
        items.push({ "label": (pluginApi.tr("action.push") || "Push remaining") + " +" + (mainInstance ? mainInstance.pushIncrement : 15) + "m", "action": "push", "icon": "arrow-right" })
      }
      items.push({ "label": pluginApi.tr("action.reset-today") || "Reset today from template", "action": "reset-today", "icon": "refresh" })
      items.push({ "label": pluginApi.tr("panel.settings") || "Settings", "action": "widget-settings", "icon": "settings" })
      return items
    }
    onTriggered: action => {
      contextMenu.close()
      PanelService.closeContextMenu(screen)
      if (action === "widget-settings") {
        BarService.openPluginSettings(screen, pluginApi.manifest)
      } else if (mainInstance) {
        if (action === "end-now") mainInstance.endCurrentNow()
        else if (action === "insert-now") mainInstance.insertNowBlock("", 0)
        else if (action === "push") mainInstance.pushRemaining(mainInstance.pushIncrement)
        else if (action === "reset-today") mainInstance.resetTodayFromTemplate()
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
      if (mouse.button === Qt.LeftButton) {
        if (pluginApi) pluginApi.openPanel(root.screen, root)
      } else if (mouse.button === Qt.RightButton) {
        PanelService.showContextMenu(contextMenu, root, screen)
      }
    }
  }
}
