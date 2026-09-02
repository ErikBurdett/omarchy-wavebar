import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.erikburdett.wavebar"

  readonly property var waveformService: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property var activePlayer: waveformService ? waveformService.activePlayer : null
  readonly property bool hasMedia: waveformService ? waveformService.hasMedia : false
  readonly property bool playing: waveformService ? waveformService.playing : false
  readonly property bool showControls: Boolean(setting("showControls", true))
  readonly property bool showTitle: Boolean(setting("showTitle", true))
  readonly property bool hideWhenPaused: Boolean(setting("hideWhenPaused", false))
  readonly property real waveformWidth: Math.min(240,
    Math.max(40, Number(setting("waveformWidth", 72)) || 72))
  readonly property real maxTitleWidth: Math.min(320,
    Math.max(60, Number(setting("maxTitleWidth", 150)) || 150))

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  visible: hasMedia && (!hideWhenPaused || playing)
  implicitWidth: vertical ? barSize : horizontalContent.implicitWidth + Style.space(10)
  implicitHeight: vertical ? verticalContent.implicitHeight + Style.space(10) : barSize

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.settings = root.settings
    panelLoader.item.anchorItem = root
    panelLoader.item.hostWidget = root
    panelLoader.item.service = root.waveformService
  }

  function actionEnabled(action) {
    var player = activePlayer
    if (!player) return false
    if (action === "previous") return !!player.canGoPrevious
    if (action === "next") return !!player.canGoNext
    return !!(player.canTogglePlaying || player.canPlay || player.canPause)
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onWaveformServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Row {
    id: horizontalContent
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: Style.space(3)

    Button {
      visible: root.showControls
      enabled: root.actionEnabled("previous")
      opacity: enabled ? 1 : 0.35
      iconText: "󰒮"
      foreground: root.bar ? root.bar.barForeground : Color.foreground
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      iconSize: Style.font.body
      horizontalPadding: Style.space(3)
      verticalPadding: Style.space(2)
      tooltipText: "Previous"
      onClicked: if (root.waveformService) root.waveformService.runAction("previous")
    }

    Item {
      id: mediaButton
      implicitWidth: mediaRow.implicitWidth
      implicitHeight: Math.max(Style.space(24), mediaRow.implicitHeight)

      Row {
        id: mediaRow
        anchors.centerIn: parent
        spacing: Style.space(6)

        Waveform {
          width: root.waveformWidth
          height: Style.space(18)
          barCount: Math.min(48, Math.max(10, Math.round(width / 4)))
          samples: root.waveformService ? root.waveformService.samples : []
          active: root.playing
          live: root.waveformService ? root.waveformService.receivingFrames : false
          foreground: root.bar ? root.bar.barForeground : Color.foreground
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          visible: root.showTitle && !root.vertical
          width: visible ? Math.min(root.maxTitleWidth, titleText.implicitWidth) : 0
          height: titleText.implicitHeight
          clip: true
          anchors.verticalCenter: parent.verticalCenter

          MarqueeText {
            id: titleText
            width: parent.width
            height: implicitHeight
            text: root.waveformService ? root.waveformService.title : ""
            foreground: root.bar ? root.bar.barForeground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontPixelSize: Style.font.bodySmall
            active: !root.opened
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.toggle()
        onWheel: function(wheel) {
          if (!root.waveformService) return
          root.waveformService.runAction(wheel.angleDelta.y > 0 ? "previous" : "next")
        }
        onEntered: if (root.bar && root.waveformService)
          root.bar.showTooltip(root, root.waveformService.title
            + (root.waveformService.artist ? " — " + root.waveformService.artist : ""))
        onExited: if (root.bar) root.bar.hideTooltip(root)
      }
    }

    Button {
      visible: root.showControls
      enabled: root.actionEnabled("playPause")
      opacity: enabled ? 1 : 0.35
      iconText: root.playing ? "󰏤" : "󰐊"
      foreground: root.bar ? root.bar.barForeground : Color.foreground
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      iconSize: Style.font.body
      horizontalPadding: Style.space(4)
      verticalPadding: Style.space(2)
      tooltipText: root.playing ? "Pause" : "Play"
      onClicked: if (root.waveformService) root.waveformService.runAction("playPause")
    }

    Button {
      visible: root.showControls
      enabled: root.actionEnabled("next")
      opacity: enabled ? 1 : 0.35
      iconText: "󰒭"
      foreground: root.bar ? root.bar.barForeground : Color.foreground
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      iconSize: Style.font.body
      horizontalPadding: Style.space(3)
      verticalPadding: Style.space(2)
      tooltipText: "Next"
      onClicked: if (root.waveformService) root.waveformService.runAction("next")
    }
  }

  Column {
    id: verticalContent
    visible: root.vertical
    anchors.centerIn: parent
    spacing: Style.space(3)

    Button {
      enabled: root.actionEnabled("playPause")
      iconText: root.playing ? "󰏤" : "󰐊"
      foreground: root.bar ? root.bar.barForeground : Color.foreground
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      iconSize: Style.font.body
      horizontalPadding: Style.space(3)
      verticalPadding: Style.space(2)
      onClicked: if (root.waveformService) root.waveformService.runAction("playPause")
    }

    Waveform {
      width: Style.space(20)
      height: Style.space(54)
      rotation: 90
      barCount: 13
      samples: root.waveformService ? root.waveformService.samples : []
      active: root.playing
      live: root.waveformService ? root.waveformService.receivingFrames : false
      foreground: root.bar ? root.bar.barForeground : Color.foreground

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
      }
    }
  }
}
