function normalized(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/^org\.mpris\.mediaplayer2\./, "")
    .replace(/\.instance[0-9]+$/, "")
    .replace(/[^a-z0-9]+/g, "")
}

function text(value) {
  return String(value || "").trim()
}

function isGenericTitle(title, player) {
  var value = normalized(title)
  if (!value) return true

  var generic = {
    "audioplaying": true,
    "videoplaying": true,
    "mediaplayer": true,
    "nowplaying": true,
    "unknown": true,
    "unknowntitle": true
  }
  if (generic[value]) return true

  var identity = normalized(player && player.identity)
  var desktop = normalized(player && player.desktopEntry)
  return value === identity || value === desktop
}

// Require track metadata instead of treating every audio-producing process as
// media. Games and system sounds normally expose PipeWire streams but no
// MediaSession/MPRIS track, so they never enter the player list.
function isFocusedMediaPlayer(player) {
  if (!player) return false
  if (text(player.trackArtist) || text(player.trackAlbum) || text(player.trackArtUrl)) return true
  return text(player.trackTitle) !== "" && !isGenericTitle(player.trackTitle, player)
}

function playerKey(player) {
  if (!player) return ""
  return String(player.dbusName || player.desktopEntry || player.identity || "")
}

function playerLabel(player) {
  if (!player) return "Media"
  return text(player.identity) || text(player.desktopEntry) || "Media"
}

function focusedPlayers(sourcePlayers) {
  var players = Array.isArray(sourcePlayers) ? sourcePlayers : []
  var result = []
  for (var i = 0; i < players.length; i++) {
    if (isFocusedMediaPlayer(players[i])) result.push(players[i])
  }
  return result
}

function selectFocusedPlayer(activePlayer, sourcePlayers) {
  if (isFocusedMediaPlayer(activePlayer)) return activePlayer

  var players = focusedPlayers(sourcePlayers)
  for (var i = 0; i < players.length; i++) {
    if (players[i].isPlaying) return players[i]
  }
  return players.length > 0 ? players[0] : null
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function prop(props, name) {
  return text(props ? props[name] : "")
}

function playerAppKeys(player) {
  if (!player) return []
  var dbus = String(player.dbusName || "")
    .replace(/^org\.mpris\.MediaPlayer2\./, "")
    .replace(/\.instance[0-9]+$/, "")
  var raw = [player.desktopEntry, player.identity, dbus]
  var keys = []
  for (var i = 0; i < raw.length; i++) {
    var key = normalized(raw[i])
    if (key && keys.indexOf(key) === -1) keys.push(key)
  }
  return keys
}

function nodeAppKeys(node) {
  var props = nodeProps(node)
  var raw = [
    prop(props, "application.name"),
    prop(props, "application.process.binary"),
    prop(props, "application.icon-name"),
    prop(props, "application.desktop"),
    node ? node.description : "",
    node ? node.name : ""
  ]
  var keys = []
  for (var i = 0; i < raw.length; i++) {
    var key = normalized(raw[i])
    if (key && keys.indexOf(key) === -1) keys.push(key)
  }
  return keys
}

function affinity(left, right) {
  if (!left || !right) return 0
  if (left === right) return 3
  if (left.length >= 4 && right.indexOf(left) !== -1) return 2
  if (right.length >= 4 && left.indexOf(right) !== -1) return 2
  return 0
}

function maximumAffinity(left, right) {
  var best = 0
  for (var i = 0; i < left.length; i++) {
    for (var j = 0; j < right.length; j++) {
      best = Math.max(best, affinity(left[i], right[j]))
    }
  }
  return best
}

function streamRole(node) {
  var props = nodeProps(node)
  return normalized(prop(props, "media.role") || prop(props, "media.category"))
}

function isGameStream(node) {
  var role = streamRole(node)
  return role.indexOf("game") !== -1
}

function metadataAffinity(player, node) {
  var props = nodeProps(node)
  var nodeTitles = [
    prop(props, "media.title"),
    prop(props, "media.name")
  ].map(normalized).filter(function(value) { return value !== "" && value !== "playback" })
  var playerTitles = [player && player.trackTitle, player && player.trackAlbum]
    .map(normalized).filter(function(value) { return value !== "" })
  var titleScore = maximumAffinity(playerTitles, nodeTitles)

  var nodeArtist = normalized(prop(props, "media.artist"))
  var playerArtist = normalized(player && player.trackArtist)
  var artistScore = affinity(playerArtist, nodeArtist)
  return { title: titleScore, artist: artistScore }
}

function scoreStream(player, node) {
  if (!player || !node || !node.isStream || !node.audio || isGameStream(node)) {
    return { score: 0, app: 0, metadata: 0 }
  }

  var app = maximumAffinity(playerAppKeys(player), nodeAppKeys(node))
  var metadata = metadataAffinity(player, node)
  var score = app * 20 + metadata.title * 50 + metadata.artist * 20
  var role = streamRole(node)
  if (role.indexOf("music") !== -1 || role.indexOf("movie") !== -1 || role.indexOf("video") !== -1)
    score += 10

  return { score: score, app: app, metadata: Math.max(metadata.title, metadata.artist) }
}

// A title/artist match is strong enough to disambiguate several browser
// streams. With app-only matching, capture only when there is exactly one
// stream for that app. This deliberately prefers a quiet waveform over
// visualizing unrelated audio from a game tab.
function chooseCapture(player, playbackStreams) {
  if (!player || !player.isPlaying) return { node: null, reason: "paused", score: 0 }

  var streams = Array.isArray(playbackStreams) ? playbackStreams : []
  var matches = []
  for (var i = 0; i < streams.length; i++) {
    var scored = scoreStream(player, streams[i])
    if (scored.score > 0)
      matches.push({ node: streams[i], score: scored.score, app: scored.app, metadata: scored.metadata })
  }
  matches.sort(function(a, b) { return b.score - a.score })

  if (matches.length === 0) return { node: null, reason: "unmatched", score: 0 }
  if (matches[0].metadata > 0) return { node: matches[0].node, reason: "metadata", score: matches[0].score }

  var appMatches = matches.filter(function(match) { return match.app > 0 })
  if (appMatches.length === 1)
    return { node: appMatches[0].node, reason: "unique-app", score: appMatches[0].score }

  return { node: null, reason: "ambiguous", score: matches[0].score }
}

function zeroSamples(count) {
  var result = []
  for (var i = 0; i < count; i++) result.push(0)
  return result
}

function parseFrame(line, count) {
  var parts = String(line || "").trim().split(";")
  if (parts.length !== count) return null
  var result = []
  for (var i = 0; i < parts.length; i++) {
    var value = Number(parts[i])
    if (!isFinite(value)) return null
    result.push(Math.max(0, Math.min(1, value)))
  }
  return result
}

if (typeof module !== "undefined") {
  module.exports = {
    normalized: normalized,
    isGenericTitle: isGenericTitle,
    isFocusedMediaPlayer: isFocusedMediaPlayer,
    playerKey: playerKey,
    playerLabel: playerLabel,
    focusedPlayers: focusedPlayers,
    selectFocusedPlayer: selectFocusedPlayer,
    scoreStream: scoreStream,
    chooseCapture: chooseCapture,
    zeroSamples: zeroSamples,
    parseFrame: parseFrame
  }
}
