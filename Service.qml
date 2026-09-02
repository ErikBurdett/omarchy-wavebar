import QtQuick
import Quickshell
import Quickshell.Io
import "MediaModel.js" as MediaModel

Item {
  id: root

  property var shell: null
  readonly property int sampleCount: 24
  property var samples: MediaModel.zeroSamples(sampleCount)
  property bool receivingFrames: false
  property string lastError: ""

  readonly property var mediaService: shell ? shell.firstPartyServiceFor("omarchy.media") : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []
  readonly property var focusedPlayers: MediaModel.focusedPlayers(sourcePlayers)
  readonly property var activePlayer: MediaModel.selectFocusedPlayer(
    mediaService ? mediaService.activePlayer : null, sourcePlayers)
  readonly property bool hasMedia: activePlayer !== null
  readonly property bool playing: activePlayer ? !!activePlayer.isPlaying : false
  readonly property string title: activePlayer ? String(activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? String(activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer ? String(activePlayer.trackAlbum || "") : ""
  readonly property string identity: activePlayer ? MediaModel.playerLabel(activePlayer) : ""
  readonly property string artUrl: activePlayer ? String(activePlayer.trackArtUrl || "") : ""

  readonly property var playbackStreams: mediaService ? mediaService.playbackStreams : []
  readonly property var captureMatch: MediaModel.chooseCapture(activePlayer, playbackStreams)
  readonly property var captureNode: captureMatch ? captureMatch.node : null
  readonly property string captureTarget: captureNode ? String(captureNode.name || "") : ""
  readonly property string captureReason: captureMatch ? String(captureMatch.reason || "unmatched") : "unmatched"
  readonly property bool shouldCapture: playing && captureTarget !== ""
  readonly property string captureState: !hasMedia ? "no-media"
    : !playing ? "paused"
    : receivingFrames ? "live"
    : captureReason === "ambiguous" ? "ambiguous"
    : captureTarget !== "" ? "connecting"
    : "unavailable"

  // Use an argv array and an absolute path; Quickshell does not invoke a
  // shell for Process commands.
  readonly property string helperPath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/io.github.erikburdett.wavebar/waveform.py"

  function playerKey(player) {
    return mediaService ? mediaService.playerKey(player) : MediaModel.playerKey(player)
  }

  function runAction(action) {
    if (!mediaService || !activePlayer) return false
    return mediaService.runAction(action, false, playerKey(activePlayer))
  }

  function selectPlayer(key) {
    if (!mediaService) return false
    return mediaService.selectPlayer(key)
  }

  // Clicking a source is an explicit playback request. Start that source even
  // when every player is paused, then pause the previously playing source so
  // switching does not leave two media sessions playing at once.
  function selectAndPlay(key) {
    if (!mediaService) return false

    var next = mediaService.playerForKey(key)
    if (!next || !MediaModel.isFocusedMediaPlayer(next)) return false

    var current = activePlayer
    var currentKey = playerKey(current)
    var currentWasPlaying = current && current.isPlaying
    if (!mediaService.selectPlayer(key)) return false

    var started = next.isPlaying || mediaService.runAction("play", false, key)
    if (started && currentWasPlaying && currentKey !== key)
      mediaService.pausePlayer(current)
    return started
  }

  function seekTo(position) {
    var player = activePlayer
    if (!player || !player.canSeek || !player.positionSupported) return false
    var maximum = player.lengthSupported ? Math.max(0, Number(player.length) || 0) : Number(position)
    player.position = Math.max(0, Math.min(maximum, Number(position) || 0))
    return true
  }

  function setVolume(value) {
    var player = activePlayer
    if (!player || !player.volumeSupported) return false
    player.volume = Math.max(0, Math.min(1, Number(value) || 0))
    return true
  }

  function resetWaveform() {
    samples = MediaModel.zeroSamples(sampleCount)
    receivingFrames = false
    staleTimer.stop()
  }

  function consumeFrame(line) {
    var parsed = MediaModel.parseFrame(line, sampleCount)
    if (!parsed) return
    samples = parsed
    receivingFrames = true
    lastError = ""
    staleTimer.restart()
  }

  function restartVisualizer() {
    startTimer.stop()
    retryTimer.stop()
    visualizer.running = false
    resetWaveform()
    if (shouldCapture) startTimer.restart()
  }

  function startVisualizer() {
    if (!shouldCapture || visualizer.running) return false
    visualizer.exec([helperPath, "--target", captureTarget, "--bars", String(sampleCount)])
    return true
  }

  onCaptureTargetChanged: restartVisualizer()
  onPlayingChanged: restartVisualizer()
  Component.onCompleted: restartVisualizer()

  Timer {
    id: startTimer
    interval: 80
    repeat: false
    onTriggered: {
      if (!root.shouldCapture) return
      root.lastError = ""
      root.startVisualizer()
    }
  }

  Timer {
    id: retryTimer
    interval: 1500
    repeat: false
    onTriggered: root.startVisualizer()
  }

  // QProcess can fail before emitting exited (for example while the user's
  // PipeWire session is still settling during login). Keep a low-frequency
  // watchdog active until the first frame arrives so startup self-heals.
  Timer {
    id: watchdogTimer
    interval: 2000
    repeat: true
    running: root.shouldCapture && !root.receivingFrames
    onTriggered: root.startVisualizer()
  }

  Timer {
    id: staleTimer
    interval: 800
    repeat: false
    onTriggered: root.receivingFrames = false
  }

  Process {
    id: visualizer
    command: [root.helperPath, "--target", root.captureTarget, "--bars", String(root.sampleCount)]
    running: false

    stdout: SplitParser {
      onRead: function(line) { root.consumeFrame(line) }
    }

    stderr: SplitParser {
      onRead: function(line) {
        var message = String(line || "").trim()
        if (message !== "") root.lastError = message
      }
    }

    onExited: function(_exitCode, _exitStatus) {
      root.receivingFrames = false
      if (root.shouldCapture && !startTimer.running) retryTimer.restart()
    }
  }

  IpcHandler {
    target: "io.github.erikburdett.wavebar"

    function status(): string {
      return JSON.stringify({
        hasMedia: root.hasMedia,
        playing: root.playing,
        title: root.title,
        artist: root.artist,
        identity: root.identity,
        captureState: root.captureState,
        captureReason: root.captureReason,
        captureTarget: root.captureTarget,
        lastError: root.lastError,
        helperPath: root.helperPath,
        helperRunning: visualizer.running,
        startPending: startTimer.running,
        retryPending: retryTimer.running,
        watchdogRunning: watchdogTimer.running
      })
    }

    function restart(): string {
      root.restartVisualizer()
      return "ok"
    }

    function playSource(key: string): string {
      return root.selectAndPlay(key) ? "ok" : "unhandled"
    }

    function playPause(): string { return root.runAction("playPause") ? "ok" : "unhandled" }
    function next(): string { return root.runAction("next") ? "ok" : "unhandled" }
    function previous(): string { return root.runAction("previous") ? "ok" : "unhandled" }
  }
}
