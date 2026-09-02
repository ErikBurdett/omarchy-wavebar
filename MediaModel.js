var MAX_PLAYER_COUNT = 16
var MAX_STREAM_COUNT = 64
var MAX_TITLE_LENGTH = 384
var MAX_METADATA_LENGTH = 192
var MAX_IDENTITY_LENGTH = 96
var MAX_KEY_LENGTH = 256
var MAX_NODE_LENGTH = 256
var MAX_FRAME_CHARS = 384
var MAX_RAW_CHUNK_CHARS = 4096
var MAX_FRAMES_PER_CHUNK = 32

function boundedText(value, maxLength) {
  var limit = Math.max(0, Math.min(2048, Math.floor(Number(maxLength) || MAX_METADATA_LENGTH)))
  return String(value || "").slice(0, limit)
}

function strictText(value, maxLength) {
  var raw = String(value || "")
  return raw.length <= maxLength ? raw : ""
}

function normalized(value, maxLength) {
  return boundedText(value, maxLength || MAX_METADATA_LENGTH)
    .toLowerCase()
    .replace(/^org\.mpris\.mediaplayer2\./, "")
    .replace(/\.instance[0-9]+$/, "")
    .replace(/[^a-z0-9]+/g, "")
}

function text(value, maxLength) {
  return boundedText(value, maxLength || MAX_METADATA_LENGTH).trim()
}

function playerTitle(player) {
  return text(player && player.trackTitle, MAX_TITLE_LENGTH)
}

function playerArtist(player) {
  return text(player && player.trackArtist, MAX_METADATA_LENGTH)
}

function playerAlbum(player) {
  return text(player && player.trackAlbum, MAX_METADATA_LENGTH)
}

function playerIdentity(player) {
  return text(player && player.identity, MAX_IDENTITY_LENGTH)
}

function playerDesktopEntry(player) {
  return text(player && player.desktopEntry, MAX_IDENTITY_LENGTH)
}

function maxPlayerCount() { return MAX_PLAYER_COUNT }
function maxStreamCount() { return MAX_STREAM_COUNT }
function maxFrameChars() { return MAX_FRAME_CHARS }
function maxRawChunkChars() { return MAX_RAW_CHUNK_CHARS }

function oversizedCollection(values, maximum) {
  if (values === null || values === undefined) return false
  return !Array.isArray(values) || values.length > maximum
}

function inputsOversized(players, streams) {
  return oversizedCollection(players, MAX_PLAYER_COUNT)
    || oversizedCollection(streams, MAX_STREAM_COUNT)
}

function isGenericTitle(title, player) {
  var value = normalized(title, MAX_TITLE_LENGTH)
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

  var identity = normalized(playerIdentity(player), MAX_IDENTITY_LENGTH)
  var desktop = normalized(playerDesktopEntry(player), MAX_IDENTITY_LENGTH)
  return value === identity || value === desktop
}

// Require track metadata instead of treating every audio-producing process as
// media. Games and system sounds normally expose PipeWire streams but no
// MediaSession/MPRIS track, so they never enter the player list.
function isFocusedMediaPlayer(player) {
  if (!player) return false
  if (playerArtist(player) || playerAlbum(player)) return true
  return playerTitle(player) !== "" && !isGenericTitle(playerTitle(player), player)
}

function playerKey(player) {
  if (!player) return ""
  return strictText(player.dbusName || player.desktopEntry || player.identity || "", MAX_KEY_LENGTH)
}

function playerLabel(player) {
  if (!player) return "Media"
  return playerIdentity(player) || playerDesktopEntry(player) || "Media"
}

function isBrowserPlayer(player) {
  if (!player) return false
  var value = normalized([
    playerIdentity(player),
    playerDesktopEntry(player),
    strictText(player.dbusName, MAX_KEY_LENGTH).replace(/^org\.mpris\.MediaPlayer2\./, "")
  ].join(" "), MAX_KEY_LENGTH + MAX_IDENTITY_LENGTH * 2)
  var browserKeys = [
    "chromium", "googlechrome", "chrome", "firefox", "brave",
    "microsoftedge", "vivaldi", "zenbrowser"
  ]
  for (var i = 0; i < browserKeys.length; i++) {
    if (value.indexOf(browserKeys[i]) !== -1) return true
  }
  return false
}

function mediaLength(player) {
  var value = Number(player && player.length)
  return isFinite(value) && value > 0 ? value : 0
}

// Electron media apps can publish both their canonical MPRIS endpoint and a
// Chromium Media Session endpoint from the same process. Treat them as one
// source only when the bridge title contains the canonical track and app,
// their playback state agrees, and their durations agree. The conservative
// checks keep independent browser tabs and genuinely separate sessions apart.
function isBrowserMirror(browser, direct) {
  if (!isBrowserPlayer(browser) || isBrowserPlayer(direct)) return false
  if (!!browser.isPlaying !== !!direct.isPlaying) return false

  var directTitle = normalized(playerTitle(direct), MAX_TITLE_LENGTH)
  var browserMetadata = normalized([
    playerTitle(browser),
    playerArtist(browser),
    playerAlbum(browser)
  ].join(" "), MAX_TITLE_LENGTH + MAX_METADATA_LENGTH * 2)
  if (directTitle.length < 6 || browserMetadata.indexOf(directTitle) === -1) return false

  var appKeys = [playerDesktopEntry(direct), playerIdentity(direct)]
    .map(function(value) { return normalized(value, MAX_IDENTITY_LENGTH) })
    .filter(function(value) { return value.length >= 4 })
  var mentionsApp = false
  for (var i = 0; i < appKeys.length; i++) {
    if (browserMetadata.indexOf(appKeys[i]) !== -1) {
      mentionsApp = true
      break
    }
  }
  if (!mentionsApp) return false

  var browserLength = mediaLength(browser)
  var directLength = mediaLength(direct)
  if (browserLength > 0 && directLength > 0)
    return Math.abs(browserLength - directLength) <= 2

  return normalized(playerTitle(browser), MAX_TITLE_LENGTH) === directTitle
}

function duplicatePlayers(left, right) {
  return isBrowserMirror(left, right) || isBrowserMirror(right, left)
}

function focusedPlayers(sourcePlayers) {
  var players = Array.isArray(sourcePlayers) ? sourcePlayers : []
  if (players.length > MAX_PLAYER_COUNT) return []
  var result = []
  for (var i = 0; i < players.length; i++) {
    var candidate = players[i]
    if (!playerKey(candidate) || !isFocusedMediaPlayer(candidate)) continue

    var duplicateIndex = -1
    for (var j = 0; j < result.length; j++) {
      if (duplicatePlayers(result[j], candidate)) {
        duplicateIndex = j
        break
      }
    }

    if (duplicateIndex === -1) result.push(candidate)
    else if (isBrowserPlayer(result[duplicateIndex]) && !isBrowserPlayer(candidate))
      result[duplicateIndex] = candidate
  }
  return result
}

function selectFromFocusedPlayers(activePlayer, focused) {
  var players = Array.isArray(focused) ? focused : []
  if (players.length > MAX_PLAYER_COUNT) return null
  if (isFocusedMediaPlayer(activePlayer)) {
    var activeKey = playerKey(activePlayer)
    for (var i = 0; i < players.length; i++) {
      if (playerKey(players[i]) === activeKey) return activePlayer
      if (duplicatePlayers(activePlayer, players[i])) return players[i]
    }
  }

  for (var j = 0; j < players.length; j++) {
    if (players[j].isPlaying) return players[j]
  }
  return players.length > 0 ? players[0] : null
}

function selectFocusedPlayer(activePlayer, sourcePlayers) {
  return selectFromFocusedPlayers(activePlayer, focusedPlayers(sourcePlayers))
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function captureTarget(node) {
  var value = strictText(node && node.name, MAX_NODE_LENGTH).trim()
  if (!value || /[\u0000-\u001f\u007f]/.test(value)) return ""
  return value
}

function prop(props, name) {
  return text(props ? props[name] : "", MAX_NODE_LENGTH)
}

function playerAppKeys(player) {
  if (!player) return []
  var dbus = strictText(player.dbusName, MAX_KEY_LENGTH)
    .replace(/^org\.mpris\.MediaPlayer2\./, "")
    .replace(/\.instance[0-9]+$/, "")
  var raw = [playerDesktopEntry(player), playerIdentity(player), dbus]
  var keys = []
  for (var i = 0; i < raw.length; i++) {
    var key = normalized(raw[i], MAX_KEY_LENGTH)
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
    text(node ? node.description : "", MAX_NODE_LENGTH),
    text(node ? node.name : "", MAX_NODE_LENGTH)
  ]
  var keys = []
  for (var i = 0; i < raw.length; i++) {
    var key = normalized(raw[i], MAX_NODE_LENGTH)
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
  return normalized(prop(props, "media.role") || prop(props, "media.category"), MAX_NODE_LENGTH)
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
  ].map(function(value) { return normalized(value, MAX_NODE_LENGTH) })
    .filter(function(value) { return value !== "" && value !== "playback" })
  var playerTitles = [playerTitle(player), playerAlbum(player)]
    .map(function(value) { return normalized(value, MAX_TITLE_LENGTH) })
    .filter(function(value) { return value !== "" })
  var titleScore = maximumAffinity(playerTitles, nodeTitles)

  var nodeArtist = normalized(prop(props, "media.artist"), MAX_NODE_LENGTH)
  var artist = normalized(playerArtist(player), MAX_METADATA_LENGTH)
  var artistScore = affinity(artist, nodeArtist)
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
function chooseMatchingStream(player, playbackStreams) {
  if (!player) return { node: null, reason: "no-player", score: 0 }
  var streams = Array.isArray(playbackStreams) ? playbackStreams : []
  if (streams.length > MAX_STREAM_COUNT)
    return { node: null, reason: "too-many-streams", score: 0 }
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

function chooseCapture(player, playbackStreams) {
  if (!player || !player.isPlaying) return { node: null, reason: "paused", score: 0 }
  return chooseMatchingStream(player, playbackStreams)
}

function chooseVolumeNode(player, playbackStreams) {
  return chooseMatchingStream(player, playbackStreams)
}

function zeroSamples(count) {
  var result = []
  for (var i = 0; i < count; i++) result.push(0)
  return result
}

function parseFrame(line, count) {
  if (!Number.isInteger(count) || count < 1 || count > 96) return null
  var raw = boundedText(line, MAX_FRAME_CHARS + 1)
  if (raw.length > MAX_FRAME_CHARS) return null
  var parts = raw.trim().split(";")
  if (parts.length !== count) return null
  var result = []
  for (var i = 0; i < parts.length; i++) {
    var value = Number(parts[i])
    if (!isFinite(value)) return null
    result.push(Math.max(0, Math.min(1, value)))
  }
  return result
}

// SplitParser normally retains data until it sees a newline. WaveBar instead
// asks it for raw chunks and performs bounded framing here, so an incomplete
// line can never grow without limit inside the resident shell.
function frameChunk(remainder, incoming) {
  var prefix = String(remainder || "")
  var chunk = String(incoming || "")
  if (prefix.length > MAX_FRAME_CHARS || chunk.length > MAX_RAW_CHUNK_CHARS)
    return { ok: false, frames: [], remainder: "" }

  var data = prefix + chunk
  var frames = []
  var start = 0
  for (var i = 0; i < data.length; i++) {
    if (data.charCodeAt(i) !== 10) continue
    if (frames.length >= MAX_FRAMES_PER_CHUNK || i - start > MAX_FRAME_CHARS)
      return { ok: false, frames: [], remainder: "" }
    var line = data.slice(start, i)
    if (line.endsWith("\r")) line = line.slice(0, -1)
    frames.push(line)
    start = i + 1
  }

  var tail = data.slice(start)
  if (tail.length > MAX_FRAME_CHARS)
    return { ok: false, frames: [], remainder: "" }
  return { ok: true, frames: frames, remainder: tail }
}

if (typeof module !== "undefined") {
  module.exports = {
    normalized: normalized,
    boundedText: boundedText,
    isGenericTitle: isGenericTitle,
    isFocusedMediaPlayer: isFocusedMediaPlayer,
    playerKey: playerKey,
    playerLabel: playerLabel,
    playerTitle: playerTitle,
    playerArtist: playerArtist,
    playerAlbum: playerAlbum,
    playerIdentity: playerIdentity,
    maxPlayerCount: maxPlayerCount,
    maxStreamCount: maxStreamCount,
    maxFrameChars: maxFrameChars,
    maxRawChunkChars: maxRawChunkChars,
    inputsOversized: inputsOversized,
    captureTarget: captureTarget,
    isBrowserPlayer: isBrowserPlayer,
    duplicatePlayers: duplicatePlayers,
    focusedPlayers: focusedPlayers,
    selectFromFocusedPlayers: selectFromFocusedPlayers,
    selectFocusedPlayer: selectFocusedPlayer,
    scoreStream: scoreStream,
    chooseCapture: chooseCapture,
    chooseVolumeNode: chooseVolumeNode,
    zeroSamples: zeroSamples,
    parseFrame: parseFrame,
    frameChunk: frameChunk
  }
}
