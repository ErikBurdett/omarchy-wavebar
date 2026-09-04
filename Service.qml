import QtQuick
import Quickshell
import Quickshell.Io
import "MediaModel.js" as MediaModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "io.github.erikburdett.wavebar"
  readonly property int sampleCount: 24
  property var samples: MediaModel.zeroSamples(sampleCount)
  property bool receivingFrames: false
  property string lastError: ""
  property string frameRemainder: ""
  property bool shuttingDown: false
  property bool fatalHelperError: false
  readonly property bool helperRunning: visualizer.running

  readonly property var mediaService: shell ? shell.firstPartyServiceFor("omarchy.media") : null
  readonly property int maxPlayers: MediaModel.maxPlayerCount()
  readonly property int maxStreams: MediaModel.maxStreamCount()
  readonly property var rawSourcePlayers: mediaService ? mediaService.sourcePlayers : []
  readonly property var rawPlaybackStreams: mediaService ? mediaService.playbackStreams : []
  readonly property bool inputRejected: MediaModel.inputsOversized(
    rawSourcePlayers, rawPlaybackStreams)
  readonly property var sourcePlayers: inputRejected ? [] : rawSourcePlayers
  readonly property var playbackStreams: inputRejected ? [] : rawPlaybackStreams
  readonly property var focusedPlayers: MediaModel.focusedPlayers(sourcePlayers)
  readonly property var activePlayer: MediaModel.selectFromFocusedPlayers(
    mediaService ? mediaService.activePlayer : null, focusedPlayers)
  readonly property bool hasMedia: activePlayer !== null
  readonly property bool playing: activePlayer ? !!activePlayer.isPlaying : false
  readonly property string title: MediaModel.playerTitle(activePlayer)
  readonly property string artist: MediaModel.playerArtist(activePlayer)
  readonly property string album: MediaModel.playerAlbum(activePlayer)
  readonly property string identity: MediaModel.playerIdentity(activePlayer)
  readonly property string trackArtUrl: safeTrackArt(activePlayer && activePlayer.trackArtUrl
    ? activePlayer.trackArtUrl : "")

  // Matching player metadata to PipeWire nodes is the most expensive model
  // pass. Reuse one bounded result for capture and volume instead of scoring
  // the same collection twice on every property update.
  readonly property var streamMatch: MediaModel.chooseVolumeNode(activePlayer, playbackStreams)
  readonly property var captureMatch: !playing
    ? ({ node: null, reason: "paused", score: 0 }) : streamMatch
  readonly property var captureNode: captureMatch ? captureMatch.node : null
  readonly property string captureTarget: MediaModel.captureTarget(captureNode)
  readonly property string captureReason: captureMatch ? String(captureMatch.reason || "unmatched") : "unmatched"
  readonly property bool shouldCapture: playing && captureTarget !== ""
  readonly property var volumeNode: streamMatch ? streamMatch.node : null
  readonly property bool volumeSupported: !!(volumeNode && volumeNode.audio)
    || !!(activePlayer && activePlayer.volumeSupported
      && !MediaModel.isBrowserPlayer(activePlayer))
  readonly property real volume: {
    var value = volumeNode && volumeNode.audio
      ? Number(volumeNode.audio.volume)
      : activePlayer ? Number(activePlayer.volume) : 0
    return isFinite(value) ? Math.max(0, Math.min(1, value)) : 0
  }
  readonly property string volumeBackend: volumeNode && volumeNode.audio
    ? "pipewire" : volumeSupported ? "mpris" : "unavailable"
  readonly property string captureState: inputRejected ? "input-rejected"
    : !hasMedia ? "no-media"
    : !playing ? "paused"
    : receivingFrames ? "live"
    : captureReason === "ambiguous" ? "ambiguous"
    : captureTarget !== "" ? "connecting"
    : "unavailable"

  // Use an argv array and an absolute path; Quickshell does not invoke a
  // shell for Process commands.
  readonly property string pluginSourceDir: {
    var source = manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    if (source.length > 0 && source.length <= 4096 && source.charAt(0) === "/")
      return source.replace(/\/+$/, "")
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/" + pluginId
  }
  readonly property string helperPath: pluginSourceDir + "/waveform.py"
  readonly property string pythonPath: "/usr/bin/python3"

  function playerTitle(player) { return MediaModel.playerTitle(player) }
  function playerArtist(player) { return MediaModel.playerArtist(player) }
  function playerIdentity(player) { return MediaModel.playerIdentity(player) }

  // Album art hardening: only allow local files or trusted cover CDNs (Spotify,
  // YouTube, Apple Music, Tidal/Deezer). Anything else is rejected so we never
  // load an untrusted remote URL supplied by a media player.
  function isSafeTrackArt(url) {
    if (typeof url !== "string" || url === "") return false
    if (url.startsWith("file://")) return true
    if (url.startsWith("/")) return true
    var m = /^https?:\/\/([^\/?#]+)/.exec(url)
    if (!m) return false
    var host = m[1]
    if (host === "localhost" || host === "127.0.0.1") return true
    if (host.endsWith(".mzstatic.com")) return true          // Apple Music
    if (host.endsWith(".scdn.co")) return true               // Spotify
    if (host === "i.ytimg.com" || host.endsWith(".ggpht.com")
      || host.endsWith(".googleusercontent.com")) return true // YouTube
    if (host.endsWith(".tidal.com") || host === "e-cdns-images.dzcdn.net"
      || host.endsWith(".dzcdn.net")) return true            // Tidal / Deezer CDN
    return false
  }

  function safeTrackArt(url) {
    return isSafeTrackArt(url) ? url : ""
  }

  function playerKey(player) {
    return MediaModel.playerKey(player)
  }

  function runAction(action) {
    if (!mediaService || !activePlayer) return false
    var key = playerKey(activePlayer)
    return key !== "" && mediaService.runAction(action, false, key)
  }

  function selectPlayer(key) {
    if (!mediaService) return false
    var safeKey = MediaModel.playerKey({ dbusName: key })
    return safeKey !== "" && mediaService.selectPlayer(safeKey)
  }

  // Clicking a source is an explicit playback request. Start that source even
  // when every player is paused, then pause the previously playing source so
  // switching does not leave two media sessions playing at once.
  function selectAndPlay(key) {
    if (!mediaService || inputRejected) return false

    var safeKey = MediaModel.playerKey({ dbusName: key })
    if (safeKey === "") return false
    var next = mediaService.playerForKey(safeKey)
    if (!next || !MediaModel.isFocusedMediaPlayer(next)) return false

    var current = activePlayer
    var currentKey = playerKey(current)
    var currentWasPlaying = current && current.isPlaying
    if (!mediaService.selectPlayer(safeKey)) return false

    var started = next.isPlaying || mediaService.runAction("play", false, safeKey)
    if (started && currentWasPlaying && currentKey !== safeKey)
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
    var next = Math.max(0, Math.min(1, Number(value) || 0))
    if (volumeNode && volumeNode.audio) {
      volumeNode.audio.volume = next
      return true
    }
    var player = activePlayer
    if (!player || !player.volumeSupported || MediaModel.isBrowserPlayer(player))
      return false
    player.volume = next
    return true
  }

  function resetWaveform() {
    samples = MediaModel.zeroSamples(sampleCount)
    receivingFrames = false
    frameRemainder = ""
    staleTimer.stop()
  }

  function shutdown() {
    if (shuttingDown) return
    shuttingDown = true
    startTimer.stop()
    retryTimer.stop()
    staleTimer.stop()
    visualizer.running = false
    resetWaveform()
  }

  function rejectProtocol(message) {
    lastError = message
    fatalHelperError = true
    visualizer.running = false
    resetWaveform()
  }

  function consumeChunk(chunk) {
    var framed = MediaModel.frameChunk(frameRemainder, chunk)
    if (!framed.ok) {
      rejectProtocol("Waveform output exceeded the protocol limit")
      return
    }
    frameRemainder = framed.remainder
    for (var i = 0; i < framed.frames.length; i++) {
      if (!consumeFrame(framed.frames[i])) return
    }
  }

  function consumeFrame(line) {
    if (String(line || "").length > MediaModel.maxFrameChars()) {
      rejectProtocol("Waveform frame exceeded the protocol limit")
      return false
    }
    var parsed = MediaModel.parseFrame(line, sampleCount)
    if (!parsed) {
      rejectProtocol("Waveform helper emitted an invalid frame")
      return false
    }
    samples = parsed
    receivingFrames = true
    lastError = ""
    staleTimer.restart()
    return true
  }

  function restartVisualizer() {
    if (shuttingDown) return
    fatalHelperError = false
    startTimer.stop()
    retryTimer.stop()
    visualizer.running = false
    resetWaveform()
    if (shouldCapture) startTimer.restart()
  }

  function startVisualizer() {
    if (shuttingDown || fatalHelperError || !shouldCapture || visualizer.running) return false
    // Set this immediately before every exec. Keeping the object behind a
    // function avoids qmllint's QVariantMap/QVariantHash false positive while
    // preserving Quickshell's documented Process environment semantics.
    visualizer.environment = sanitizedVisualizerEnvironment()
    visualizer.exec([
      pythonPath, "-I", "-S", helperPath,
      "--target", captureTarget, "--bars", String(sampleCount)
    ])
    return true
  }

  function sanitizedVisualizerEnvironment() {
    return {
      "LANG": "C.UTF-8",
      "LC_ALL": "C.UTF-8",
      "PATH": "/usr/bin",
      "PYTHONDONTWRITEBYTECODE": "1",
      "PYTHONNOUSERSITE": "1",
      "PYTHONSAFEPATH": "1"
    }
  }

  function handleVisualizerExited(exitCode) {
    root.receivingFrames = false
    if (exitCode !== 0 && root.shouldCapture) {
      if (exitCode === 127) {
        root.fatalHelperError = true
        root.lastError = "Waveform dependencies are unavailable: python and pipewire-audio are required"
      } else if (exitCode === 126) {
        root.fatalHelperError = true
        root.lastError = "Waveform helper rejected an unsafe executable or runtime"
      } else if (!root.fatalHelperError) {
        root.lastError = "Waveform helper exited with code " + String(exitCode)
      }
    }
    if (!root.shuttingDown && !root.fatalHelperError
        && root.shouldCapture && !startTimer.running)
      retryTimer.restart()
  }

  onCaptureTargetChanged: restartVisualizer()
  onPlayingChanged: restartVisualizer()
  Component.onCompleted: {
    // Connecting explicitly avoids a qmllint false positive caused by the
    // Quickshell type description omitting QProcess::ExitStatus. Qt owns and
    // disconnects this connection with the QML component.
    visualizer.exited.connect(root.handleVisualizerExited)
    restartVisualizer()
  }
  Component.onDestruction: root.shutdown()

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
    running: !root.shuttingDown && !root.fatalHelperError
      && root.shouldCapture && !root.receivingFrames
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
    command: [
      root.pythonPath, "-I", "-S", root.helperPath,
      "--target", root.captureTarget, "--bars", String(root.sampleCount)
    ]
    running: false
    clearEnvironment: true

    stdout: SplitParser {
      // Empty-marker mode emits raw QProcess chunks and does not retain an
      // unterminated line. WaveBar applies its own strict framing ceiling.
      splitMarker: ""
      onRead: function(chunk) { root.consumeChunk(chunk) }
    }

    // The helper sends only a fixed diagnostic on its own stderr and discards
    // pw-record stderr. Leaving this channel unbound avoids a resident parser.
  }

  IpcHandler {
    target: root.pluginId

    function status(): string {
      return JSON.stringify({
        hasMedia: root.hasMedia,
        playing: root.playing,
        title: root.title,
        artist: root.artist,
        identity: root.identity,
        sourceCount: root.focusedPlayers.length,
        inputRejected: root.inputRejected,
        volume: root.volume,
        volumeBackend: root.volumeBackend,
        captureState: root.captureState,
        captureReason: root.captureReason,
        captureTarget: root.captureTarget,
        lastError: root.lastError,
        helperPath: root.helperPath,
        helperRunning: root.helperRunning,
        fatalHelperError: root.fatalHelperError,
        shuttingDown: root.shuttingDown,
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
    function setVolume(value: real): string { return root.setVolume(value) ? "ok" : "unhandled" }
  }
}
