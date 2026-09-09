import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "MediaModel.js" as MediaModel

// Standalone media backend. Omarchy 4.0.3 scopes first-party service access
// behind the plugin "bar" capability, so firstPartyServiceFor("omarchy.media")
// returns null for third-party plugins and the widget's hasMedia stays false.
// Quickshell's Mpris and Pipewire singletons are process-wide and equally
// reachable from any plugin, so WaveBar builds the playbackStreams /
// sourcePlayers / activePlayer surface itself instead of depending on the
// bar host. Core selection and ordering logic mirrors omarchy.media so the
// widget behaves identically on Omarchy releases before and after the 4.0.3
// capability change.
Item {
  id: root

  property string preferredPlayerKey: ""
  property var playerStartedAt: ({})
  property int playSerial: 0

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var playbackStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && isPlaybackStream(n) && n.audio) list.push(n)
    }
    return list
  }
  readonly property var sourcePlayers: orderedSourcePlayers()
  readonly property var activePlayer: selectActivePlayer()

  function nodeProps(node) {
    return node && node.ready && node.properties ? node.properties : {}
  }

  function isProxyPlayer(player) {
    var dbusName = String(player && player.dbusName || "").toLowerCase()
    var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
    return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
  }

  function hasMetadata(player) {
    return !!(player && (player.trackTitle || player.trackArtist || player.identity || player.desktopEntry))
  }

  function hasTrackMetadata(player) {
    return !!(player && (player.trackTitle || player.trackArtist || player.trackAlbum || player.trackArtUrl))
  }

  function playerCanControl(player) {
    return !!(player && (player.canTogglePlaying || player.canPlay || player.canPause || player.canGoNext || player.canGoPrevious))
  }

  function canHandleAction(player, action) {
    if (!player) return false
    if (action === "next") return !!player.canGoNext
    if (action === "previous") return !!player.canGoPrevious
    if (action === "play") return !!(player.canPlay || player.canTogglePlaying)
    if (action === "pause") return !!(player.canPause || player.canTogglePlaying)
    if (action === "playPause") return !!(player.canTogglePlaying || player.canPlay || player.canPause)
    return false
  }

  function isPlaybackStream(node) {
    if (!node || !node.isStream) return false
    if (node.isSink === true) return true
    var mediaClass = String(node.type || "")
    return mediaClass.indexOf("Stream/Output/Audio") !== -1
      || mediaClass.indexOf("AudioOutStream") !== -1
      || mediaClass.indexOf("Output") !== -1
  }

  function streamLabelKey(label) {
    var key = String(label || "").toLowerCase()
    key = key.replace(/^pipewire alsa \[/, "")
    key = key.replace(/\]$/, "")
    key = key.replace(/^alsa playback \[/, "")
    key = key.replace(/[^a-z0-9]+/g, "")
    return key
  }

  function rawStreamLabel(node) {
    if (!node) return ""
    var p = nodeProps(node)
    return p["application.name"]
      || node.description
      || p["media.name"]
      || p["node.name"]
      || node.name
  }

  function playerAppLabel(player) {
    if (!player) return ""
    var dbus = String(player.dbusName || "")
    dbus = dbus.replace(/^org\.mpris\.MediaPlayer2\./, "")
    dbus = dbus.replace(/\.instance[0-9]+$/, "")
    return player.desktopEntry || player.identity || dbus
  }

  function playerHasPlaybackStream(player) {
    var playerKeyValue = streamLabelKey(playerAppLabel(player))
    if (!playerKeyValue) return false
    for (var i = 0; i < playbackStreams.length; i++) {
      var streamKey = streamLabelKey(rawStreamLabel(playbackStreams[i]))
      if (!streamKey) continue
      if (streamKey === playerKeyValue
          || streamKey.indexOf(playerKeyValue) !== -1
          || playerKeyValue.indexOf(streamKey) !== -1)
        return true
    }
    return false
  }

  function labelFor(player) {
    if (!player) return ""
    return player.trackTitle || player.identity || player.desktopEntry || ""
  }

  function playerKey(player) {
    return MediaModel.playerKey(player)
  }

  function playerForKey(key) {
    if (!key) return null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (playerKey(p) === key) return p
    }
    return null
  }

  function playerOrder(player, fallback) {
    var key = playerKey(player)
    var value = key ? playerStartedAt[key] : undefined
    return value === undefined ? fallback : value
  }

  function syncPlayingOrder() {
    var next = {}
    var alive = {}
    var serial = playSerial

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      var key = playerKey(p)
      if (!key) continue

      alive[key] = true
      if (!p.isPlaying) continue

      if (playerStartedAt[key] === undefined) {
        serial += 1
        next[key] = serial
      } else {
        next[key] = playerStartedAt[key]
      }
    }

    if (preferredPlayerKey && !alive[preferredPlayerKey]) preferredPlayerKey = ""

    playSerial = serial
    playerStartedAt = next
  }

  function orderedSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (hasMetadata(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      if (a.isPlaying && b.isPlaying) {
        var orderDelta = playerOrder(a, 1000) - playerOrder(b, 1000)
        if (orderDelta !== 0) return orderDelta
      }
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function oldestPlayingPlayer(requirePlaybackStream) {
    var oldest = null
    var oldestOrder = 0
    var playingProxy = null
    var proxyOrder = 0

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxyPlayer = isProxyPlayer(p)
      if (p.isPlaying) {
        if (requirePlaybackStream && !playerHasPlaybackStream(p)) continue

        var order = playerOrder(p, i + 1000)
        if (!proxyPlayer && (!oldest || order < oldestOrder)) {
          oldest = p
          oldestOrder = order
        } else if (proxyPlayer && (!playingProxy || order < proxyOrder)) {
          playingProxy = p
          proxyOrder = order
        }
      }
    }

    return oldest || playingProxy || null
  }

  function selectActivePlayer() {
    var preferred = null
    var trackPlayer = null
    var trackProxy = null
    var streamPlayer = null
    var streamProxy = null
    var controllablePlayer = null
    var controllableProxy = null
    var identityPlayer = null
    var identityProxy = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxy = isProxyPlayer(p)

      if (preferredPlayerKey && playerKey(p) === preferredPlayerKey && hasMetadata(p)) preferred = p

      if (playerHasPlaybackStream(p)) {
        if (!proxy && !streamPlayer) streamPlayer = p
        else if (proxy && !streamProxy) streamProxy = p
      } else if (hasTrackMetadata(p)) {
        if (!proxy && !trackPlayer) trackPlayer = p
        else if (proxy && !trackProxy) trackProxy = p
      } else if (playerCanControl(p)) {
        if (!proxy && !controllablePlayer) controllablePlayer = p
        else if (proxy && !controllableProxy) controllableProxy = p
      } else if (hasMetadata(p)) {
        if (!proxy && !identityPlayer) identityPlayer = p
        else if (proxy && !identityProxy) identityProxy = p
      }
    }

    if (preferred && preferred.isPlaying) return preferred
    var streamCandidate = streamPlayer || streamProxy
    var streamPreferred = preferred && playerHasPlaybackStream(preferred) ? preferred : null
    return oldestPlayingPlayer(true) || oldestPlayingPlayer(false) || streamPreferred || streamCandidate || preferred || trackPlayer || trackProxy || controllablePlayer || controllableProxy || identityPlayer || identityProxy || null
  }

  function selectPlayer(key) {
    var player = playerForKey(key)
    if (!player || !hasMetadata(player)) return false
    preferredPlayerKey = playerKey(player)
    return true
  }

  function pausePlayer(player) {
    if (!player) return false
    if (player.canPause) {
      player.pause()
      return true
    }
    if (player.canTogglePlaying && player.isPlaying) {
      player.togglePlaying()
      return true
    }
    return false
  }

  function playerForAction(action, targetKey) {
    var targeted = playerForKey(targetKey)
    if (targeted) return targeted

    if (action === "pause" || action === "playPause") {
      var oldest = oldestPlayingPlayer(true) || oldestPlayingPlayer(false)
      if (oldest) return oldest
    }

    if (canHandleAction(activePlayer, action)) return activePlayer

    var list = sourcePlayers
    for (var i = 0; i < list.length; i++) {
      if (canHandleAction(list[i], action)) return list[i]
    }

    return activePlayer
  }

  function runAction(action, showFeedback, targetKey) {
    var player = playerForAction(action, targetKey)
    var key = playerKey(player)
    var handled = false

    if (action === "next") {
      if (player && player.canGoNext) {
        player.next()
        handled = true
      }
    } else if (action === "previous") {
      if (player && player.canGoPrevious) {
        player.previous()
        handled = true
      }
    } else if (action === "play") {
      if (player && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying && !player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "pause") {
      if (player && player.canPause) {
        player.pause()
        handled = true
      } else if (player && player.canTogglePlaying && player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "playPause") {
      if (player && player.isPlaying && player.canPause) {
        player.pause()
        handled = true
      } else if (player && !player.isPlaying && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying) {
        player.togglePlaying()
        handled = true
      }
    }

    if (handled && key) preferredPlayerKey = key
    return handled
  }

  // Recompute play-order reactively instead of polling. onPlayersChanged
  // covers players appearing/disappearing, and each live player's
  // isPlayingChanged signal is wired below so the ordering stays current.
  // (omarchy.media reaches the isPlayingChanged handlers through an
  // Instantiator, but qmllint 6.11 treats any delegate reference to the
  // component root as an unqualified access, so the connections are made in
  // root scope and torn down on destruction instead.)
  Component.onCompleted: {
    root.syncPlayingOrder()
    root.wireIsPlayingSignals()
  }
  onPlayersChanged: {
    root.syncPlayingOrder()
    root.wireIsPlayingSignals()
  }
  Component.onDestruction: root.unwireIsPlayingSignals()

  property var isPlayingConnections: ({})

  function wireIsPlayingSignals() {
    var alive = {}
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue
      var key = playerKey(p)
      if (!key) continue
      alive[key] = true
      if (isPlayingConnections[key]) continue
      var fn = function() { root.syncPlayingOrder() }
      p.isPlayingChanged.connect(fn)
      isPlayingConnections[key] = { player: p, fn: fn }
    }
    for (var stale in isPlayingConnections) {
      if (alive[stale]) continue
      var entry = isPlayingConnections[stale]
      entry.player.isPlayingChanged.disconnect(entry.fn)
      delete isPlayingConnections[stale]
    }
  }

  function unwireIsPlayingSignals() {
    for (var k in isPlayingConnections) {
      var entry = isPlayingConnections[k]
      entry.player.isPlayingChanged.disconnect(entry.fn)
    }
    isPlayingConnections = ({})
  }

  PwObjectTracker { objects: root.playbackStreams }
}