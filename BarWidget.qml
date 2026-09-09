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
  // All seven toggles parse the same way. `shell.json` is hand-editable, so a
  // toggle can arrive as the string "true" rather than a boolean; comparing
  // with `=== true` would read that as off here while the panel's own switch
  // read it as on, and the widget would disagree with its settings UI.
  readonly property bool showControls: String(setting("showControls", true)).toLowerCase() === "true"
  readonly property bool showTitle: String(setting("showTitle", true)).toLowerCase() === "true"
  readonly property bool showArtist: String(setting("showArtist", false)).toLowerCase() === "true"
  readonly property bool showFullTitle: String(setting("showFullTitle", false)).toLowerCase() === "true"
  readonly property bool groupControls: String(setting("groupControls", false)).toLowerCase() === "true"
  readonly property bool showCover: String(setting("showCover", false)).toLowerCase() === "true"
  readonly property bool hideWhenPaused: String(setting("hideWhenPaused", false)).toLowerCase() === "true"
  readonly property real waveformWidth: Math.min(240,
    Math.max(40, Number(setting("waveformWidth", 72)) || 72))
  readonly property string artUrl: waveformService ? waveformService.trackArtUrl : ""
  readonly property real maxTitleWidth: Math.min(320,
    Math.max(60, Number(setting("maxTitleWidth", 150)) || 150))

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property bool shouldShow: hasMedia && (!hideWhenPaused || playing)

  visible: shouldShow
  implicitWidth: shouldShow
    ? (vertical ? barSize : horizontalContent.implicitWidth + Style.space(10)) : 0
  implicitHeight: shouldShow
    ? (vertical ? verticalContent.implicitHeight + Style.space(10) : barSize) : 0

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

    Item {
      id: prevLeft
      visible: root.showControls && !root.groupControls
      implicitWidth: prevLeftBtn.implicitWidth
      implicitHeight: prevLeftBtn.implicitHeight
      readonly property bool tooltipHovered: prevLeftHover.containsMouse

      Button {
        id: prevLeftBtn
        anchors.fill: parent
        enabled: root.actionEnabled("previous")
        opacity: enabled ? 1 : 0.35
        iconText: "󰒮"
        foreground: root.bar ? root.bar.barForeground : Color.foreground
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        iconSize: Style.font.body
        horizontalPadding: Style.space(3)
        verticalPadding: Style.space(2)
        onClicked: if (root.waveformService) root.waveformService.runAction("previous")
      }

      MouseArea {
        id: prevLeftHover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: if (root.bar) root.bar.showTooltip(prevLeft, "Previous")
        onExited: if (root.bar) root.bar.hideTooltip(prevLeft)
      }
    }
    Item {
      id: mediaButton
      implicitWidth: mediaRow.implicitWidth
      implicitHeight: Math.max(Style.space(24), mediaRow.implicitHeight)
      readonly property bool tooltipHovered: mediaHover.containsMouse

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
          visible: root.showCover && root.artUrl !== "" && !root.vertical
          width: Style.space(18)
          height: Style.space(18)
          clip: true
          anchors.verticalCenter: parent.verticalCenter

          Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.artUrl
          }
        }

        Item {
          visible: root.showTitle && !root.vertical
          width: visible ? (root.showFullTitle
            ? titleText.implicitWidth
            : Math.min(root.maxTitleWidth, titleText.implicitWidth)) : 0
          height: titleText.implicitHeight
          clip: true
          anchors.verticalCenter: parent.verticalCenter

          MarqueeText {
            id: titleText
            width: parent.width
            height: implicitHeight
            text: {
              if (!root.waveformService) return ""
              var title = root.waveformService.title || ""
              if (root.showArtist && root.waveformService.artist) {
                return title + " \u2014 " + root.waveformService.artist
              }
              return title
            }
            foreground: root.bar ? root.bar.barForeground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontPixelSize: Style.font.bodySmall
            active: !root.opened && !root.showFullTitle
          }
        }
      }

      MouseArea {
        id: mediaHover
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
          root.bar.showTooltip(mediaButton, root.waveformService.title
            + (root.waveformService.artist ? " — " + root.waveformService.artist : ""))
        onExited: if (root.bar) root.bar.hideTooltip(mediaButton)
      }
    }

    Row {
      id: controlsGroup
      visible: root.showControls
      spacing: Style.space(3)

      Item {
        id: prevButton
        visible: root.groupControls
        implicitWidth: prevBtn.implicitWidth
        implicitHeight: prevBtn.implicitHeight
        readonly property bool tooltipHovered: prevHover.containsMouse

        Button {
          id: prevBtn
          anchors.fill: parent
          enabled: root.actionEnabled("previous")
          opacity: enabled ? 1 : 0.35
          iconText: "󰒮"
          foreground: root.bar ? root.bar.barForeground : Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          iconSize: Style.font.body
          horizontalPadding: Style.space(3)
          verticalPadding: Style.space(2)
          onClicked: if (root.waveformService) root.waveformService.runAction("previous")
        }

        MouseArea {
          id: prevHover
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
          onEntered: if (root.bar) root.bar.showTooltip(prevButton, "Previous")
          onExited: if (root.bar) root.bar.hideTooltip(prevButton)
        }
      }

      Item {
        id: playButton
        visible: true
        implicitWidth: playBtn.implicitWidth
        implicitHeight: playBtn.implicitHeight
        readonly property bool tooltipHovered: playHover.containsMouse

        Button {
          id: playBtn
          anchors.fill: parent
          enabled: root.actionEnabled("playPause")
          opacity: enabled ? 1 : 0.35
          iconText: root.playing ? "󰏤" : "󰐊"
          foreground: root.bar ? root.bar.barForeground : Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          iconSize: Style.font.body
          horizontalPadding: Style.space(3)
          verticalPadding: Style.space(2)
          onClicked: if (root.waveformService) root.waveformService.runAction("playPause")
        }

        MouseArea {
          id: playHover
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
          onEntered: if (root.bar) root.bar.showTooltip(playButton, root.playing ? "Pause" : "Play")
          onExited: if (root.bar) root.bar.hideTooltip(playButton)
        }
      }

      Item {
        id: nextButton
        visible: true
        implicitWidth: nextBtn.implicitWidth
        implicitHeight: nextBtn.implicitHeight
        readonly property bool tooltipHovered: nextHover.containsMouse

        Button {
          id: nextBtn
          anchors.fill: parent
          enabled: root.actionEnabled("next")
          opacity: enabled ? 1 : 0.35
          iconText: "󰒭"
          foreground: root.bar ? root.bar.barForeground : Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          iconSize: Style.font.body
          horizontalPadding: Style.space(3)
          verticalPadding: Style.space(2)
          onClicked: if (root.waveformService) root.waveformService.runAction("next")
        }

        MouseArea {
          id: nextHover
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
          onEntered: if (root.bar) root.bar.showTooltip(nextButton, "Next")
          onExited: if (root.bar) root.bar.hideTooltip(nextButton)
        }
      }
    }

  }

  Column {
    id: verticalContent
    visible: root.vertical
    anchors.centerIn: parent
    spacing: Style.space(3)

    Button {
      visible: root.showControls
      enabled: root.actionEnabled("playPause")
      iconText: root.playing ? "󰏤" : "󰐊"
      foreground: root.bar ? root.bar.barForeground : Color.foreground
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      iconSize: Style.font.body
      horizontalPadding: Style.space(3)
      verticalPadding: Style.space(2)
      onClicked: if (root.waveformService) root.waveformService.runAction("playPause")
    }

    Item {
      width: Style.space(20)
      height: Style.space(54)

      Waveform {
        anchors.centerIn: parent
        width: parent.height
        height: parent.width
        rotation: 90
        barCount: 13
        samples: root.waveformService ? root.waveformService.samples : []
        active: root.playing
        live: root.waveformService ? root.waveformService.receivingFrames : false
        foreground: root.bar ? root.bar.barForeground : Color.foreground
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
      }
    }
  }
}
