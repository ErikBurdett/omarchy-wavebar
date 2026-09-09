pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.erikburdett.wavebar"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property real displayedPosition: 0

  readonly property var player: service ? service.activePlayer : null
  readonly property bool playing: service ? service.playing : false
  readonly property bool hasLength: player && player.positionSupported
    && player.lengthSupported && Number(player.length) > 0
  property bool showSettings: false

  readonly property string artUrl: service ? service.trackArtUrl : ""

  function open() {
    controller.show()
    updatePosition()
  }

  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(hostWidget || root, direction)
    return false
  }

  function updatePosition() {
    if (player && player.positionSupported) displayedPosition = Math.max(0, Number(player.position) || 0)
    else displayedPosition = 0
  }

  function formatDuration(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var hours = Math.floor(value / 3600)
    var minutes = Math.floor((value % 3600) / 60)
    var remainder = value % 60
    if (hours > 0)
      return hours + ":" + String(minutes).padStart(2, "0") + ":" + String(remainder).padStart(2, "0")
    return minutes + ":" + String(remainder).padStart(2, "0")
  }

  function setBooleanSetting(key, value) {
    var shell = root.bar && root.bar.shell
    if (!shell) return
    // Omarchy 4.0.3 gates mutateShellConfig behind full-bar capability, so a
    // bar-widget plugin saves its own entry inline instead. updateEntryInline
    // replaces the whole entry, so carry every current setting forward.
    if (typeof shell.updateEntryInline === "function") {
      var next = {}
      if (Util.isPlainObject(root.settings)) {
        for (var k in root.settings) if (k !== "id") next[k] = root.settings[k]
      }
      next[key] = !!value
      if (shell.updateEntryInline(root.moduleName, next)) return
    }
    if (typeof shell.mutateShellConfig !== "function") return
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
      for (var region in config.bar.layout) {
        var entries = config.bar.layout[region]
        if (!Array.isArray(entries)) continue
        for (var i = 0; i < entries.length; i++) {
          var entry = entries[i]
          if (entry && entry.id === root.moduleName) {
            entry[key] = !!value
            return
          }
        }
      }
    })
  }

  function captureMessage() {
    if (!service) return "Media service is loading"
    if (service.inputRejected) return "Media inputs exceeded safety limits"
    if (service.lastError) return service.lastError
    if (service.captureState === "live") return "Live · " + service.identity
    if (service.captureState === "connecting") return "Connecting to the media stream…"
    if (service.captureState === "ambiguous")
      return "Waveform paused: several streams belong to this app"
    if (service.captureState === "unavailable" && playing)
      return "Controls are live; no safe local audio stream was matched"
    if (service.captureState === "paused") return "Paused"
    return "Waiting for browser or app media"
  }

  onPlayerChanged: updatePosition()
  Timer {
    interval: 500
    repeat: true
    running: root.opened && root.player && root.player.positionSupported && !positionSlider.dragging
    onTriggered: root.updatePosition()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight,
      Style.space(root.showSettings ? 1180 : 620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: if (root.service) root.service.runAction("playPause")
      onMoveRequested: function(dx, _dy) {
        if (dx !== 0 && root.service && root.player && root.player.canSeek)
          root.service.seekTo(root.displayedPosition + dx * 5)
      }
      onTextKey: function(key) {
        if (!root.service) return
        if (key === "n" || key === "N") root.service.runAction("next")
        else if (key === "p" || key === "P") root.service.runAction("previous")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(10)

            BorderSurface {
              width: Style.space(72)
              height: Style.space(72)
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.barForeground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.barForeground, Color.accent)
              clip: true

              Image {
                anchors.fill: parent
                anchors.margins: Style.space(2)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                source: root.artUrl
                visible: source !== ""
              }

              Text {
                anchors.centerIn: parent
                visible: root.artUrl === ""
                text: "󰝚"
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.displayLarge
              }
            }

            Column {
              width: parent.width - Style.space(82)
              spacing: Style.space(3)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.service && root.service.title ? root.service.title : "Nothing playing"
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text !== ""
                textFormat: Text.PlainText
                text: root.service ? root.service.artist : ""
                color: Qt.darker(root.barForeground, 1.35)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.service ? root.service.identity : ""
                color: Qt.darker(root.barForeground, 1.55)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }

          BorderSurface {
            width: parent.width
            height: Style.space(88)
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.barForeground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.barForeground, Color.accent)

            Waveform {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              barCount: 24
              samples: root.service ? root.service.samples : []
              active: root.playing
              live: root.service ? root.service.receivingFrames : false
              foreground: root.barForeground
              gap: Style.space(2)
              minimumBarHeight: Style.space(2)
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.captureMessage()
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            visible: root.hasLength
            spacing: Style.space(6)

            Text {
              width: Style.space(42)
              text: root.formatDuration(positionSlider.dragging ? positionSlider.liveValue : root.displayedPosition)
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            WavebarSlider {
              id: positionSlider
              width: parent.width - Style.space(90)
              bar: root.bar
              minimum: 0
              maximum: root.player ? Math.max(1, Number(root.player.length) || 1) : 1
              value: root.displayedPosition
              step: 5
              onMoved: function(value) { root.displayedPosition = value }
              onReleased: function(value) {
                if (root.service) root.service.seekTo(value)
                root.displayedPosition = value
              }
            }

            Text {
              width: Style.space(42)
              text: root.formatDuration(root.player ? root.player.length : 0)
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            Button {
              iconText: "󰒮"
              foreground: root.barForeground
              iconSize: Style.font.icon
              enabled: root.player && root.player.canGoPrevious
              opacity: enabled ? 1 : 0.35
              tooltipText: "Previous (P)"
              onClicked: if (root.service) root.service.runAction("previous")
            }

            Button {
              iconText: root.playing ? "󰏤" : "󰐊"
              foreground: root.barForeground
              iconSize: Style.font.icon
              enabled: root.player && (root.player.canTogglePlaying || root.player.canPlay || root.player.canPause)
              opacity: enabled ? 1 : 0.35
              tooltipText: root.playing ? "Pause (Space)" : "Play (Space)"
              onClicked: if (root.service) root.service.runAction("playPause")
            }

            Button {
              iconText: "󰒭"
              foreground: root.barForeground
              iconSize: Style.font.icon
              enabled: root.player && root.player.canGoNext
              opacity: enabled ? 1 : 0.35
              tooltipText: "Next (N)"
              onClicked: if (root.service) root.service.runAction("next")
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "󰕾"
              visible: root.service && root.service.volumeSupported
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.icon
              anchors.verticalCenter: parent.verticalCenter
            }

            WavebarSlider {
              width: parent.width - Style.space(28) - settingsButton.implicitWidth
              visible: root.service && root.service.volumeSupported
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              minimum: 0
              maximum: 1
              step: 0.05
              value: root.service ? root.service.volume : 0
              onMoved: function(value) { if (root.service) root.service.setVolume(value) }
              onReleased: function(value) { if (root.service) root.service.setVolume(value) }
            }

            Button {
              id: settingsButton
              iconText: ""
              foreground: root.barForeground
              iconSize: Style.font.icon
              anchors.verticalCenter: parent.verticalCenter
              tooltipText: root.showSettings ? "Hide settings" : "Settings"
              onClicked: root.showSettings = !root.showSettings
            }
          }

          PanelSeparator {
            visible: root.service && root.service.focusedPlayers.length > 1
            foreground: root.barForeground
          }

          Column {
            id: sourceList
            width: parent.width
            visible: root.service && root.service.focusedPlayers.length > 1
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "Media sources"
              foreground: root.barForeground
            }

            ListView {
              id: sourceView
              width: parent.width
              height: Math.min(contentHeight, Style.space(210))
              spacing: Style.space(4)
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height

              QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

              model: root.service
                ? root.service.focusedPlayers.slice(0, root.service.maxPlayers) : []

              delegate: Button {
                id: sourceButton
                required property var modelData
                required property int index
                readonly property var sourcePlayer: modelData
                readonly property bool isCurrent: root.player && root.service
                  && root.service.playerKey(root.player) === root.service.playerKey(sourcePlayer)
                readonly property string sourceTitle: root.service
                  ? (root.service.playerTitle(sourcePlayer)
                    || root.service.playerIdentity(sourcePlayer) || "Media") : "Media"
                readonly property string sourceArtist: root.service
                  ? root.service.playerArtist(sourcePlayer) : ""

                width: ListView.view.width
                height: sourceButton.implicitHeight
                clip: true
                leftAlign: true
                foreground: root.barForeground
                selected: isCurrent
                iconText: sourcePlayer && sourcePlayer.isPlaying ? "󰏤" : "󰐊"
                text: ""
                tooltipText: sourceTitle + (sourceArtist ? " — " + sourceArtist : "")
                onClicked: if (root.service) root.service.selectAndPlay(root.service.playerKey(sourcePlayer))

                MarqueeText {
                  z: 1
                  anchors.left: parent.left
                  anchors.leftMargin: sourceButton.horizontalPadding + Style.space(22)
                  anchors.right: parent.right
                  anchors.rightMargin: sourceButton.horizontalPadding
                  anchors.verticalCenter: parent.verticalCenter
                  height: implicitHeight
                  text: sourceButton.sourceTitle
                  foreground: sourceButton.selected
                    ? Style.selectedStateColor(root.barForeground, Color.accent)
                    : root.barForeground
                  fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                  fontPixelSize: Style.font.bodySmall
                  fontBold: sourceButton.selected
                  active: sourceButton.hot || sourceButton.isCurrent
                }
              }
            }
          }

          Column {
            width: parent.width
            visible: root.showSettings
            spacing: Style.space(4)

            PanelSeparator {
              foreground: root.barForeground
            }

            PanelSectionHeader {
              text: "Settings"
              foreground: root.barForeground
            }

            Toggle {
              width: parent.width
              label: "Show track title"
              description: "Show the scrolling track title beside the waveform."
              checked: String(root.setting("showTitle", true)).toLowerCase() === "true"
              foreground: root.barForeground
              accent: Color.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.setBooleanSetting("showTitle",
                String(root.setting("showTitle", true)).toLowerCase() !== "true")
            }

            Toggle {
              width: parent.width
              visible: String(root.setting("showTitle", true)).toLowerCase() === "true"
              label: "Show artist in title"
              description: "Show the artist name after the track title."
              checked: String(root.setting("showArtist", false)).toLowerCase() === "true"
              foreground: root.barForeground
              accent: Color.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.setBooleanSetting("showArtist",
                String(root.setting("showArtist", false)).toLowerCase() !== "true")
            }

            Toggle {
              width: parent.width
              visible: String(root.setting("showTitle", true)).toLowerCase() === "true"
              label: "Show full track info"
              description: "Show the whole track title (and artist) without scrolling or clipping, instead of truncating and scrolling long titles."
              checked: String(root.setting("showFullTitle", false)).toLowerCase() === "true"
              foreground: root.barForeground
              accent: Color.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.setBooleanSetting("showFullTitle",
                String(root.setting("showFullTitle", false)).toLowerCase() !== "true")
            }

            Toggle {
              width: parent.width
              label: "Show album cover"
              description: "Show the album art thumbnail between the waveform and the track title when a cover is available."
              checked: String(root.setting("showCover", false)).toLowerCase() === "true"
              foreground: root.barForeground
              accent: Color.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.setBooleanSetting("showCover",
                String(root.setting("showCover", false)).toLowerCase() !== "true")
            }

            Toggle {
              width: parent.width
              label: "Show playback controls"
              description: "Show previous, play/pause, and next buttons in the bar."
              checked: String(root.setting("showControls", true)).toLowerCase() === "true"
              foreground: root.barForeground
              accent: Color.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.setBooleanSetting("showControls",
                String(root.setting("showControls", true)).toLowerCase() !== "true")
            }

            Toggle {
              width: parent.width
              visible: String(root.setting("showControls", true)).toLowerCase() === "true"
              label: "Group playback controls"
              description: "Keep previous next to play/pause and next, beside the waveform."
              checked: String(root.setting("groupControls", false)).toLowerCase() === "true"
              foreground: root.barForeground
              accent: Color.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.setBooleanSetting("groupControls",
                String(root.setting("groupControls", false)).toLowerCase() !== "true")
            }

            Toggle {
              width: parent.width
              label: "Hide when paused"
              description: "Remove WaveBar from the bar while playback is paused."
              checked: String(root.setting("hideWhenPaused", false)).toLowerCase() === "true"
              foreground: root.barForeground
              accent: Color.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.setBooleanSetting("hideWhenPaused",
                String(root.setting("hideWhenPaused", false)).toLowerCase() !== "true")
            }
          }
        }
      }
    }
  }
}
