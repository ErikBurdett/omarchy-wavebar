const assert = require("node:assert/strict")
const model = require("../MediaModel.js")

function player(overrides = {}) {
  return Object.assign({
    dbusName: "org.mpris.MediaPlayer2.firefox.instance12",
    desktopEntry: "firefox",
    identity: "Mozilla Firefox",
    trackTitle: "A Great Song",
    trackArtist: "An Artist",
    isPlaying: true
  }, overrides)
}

function stream(overrides = {}) {
  return Object.assign({
    isStream: true,
    audio: {},
    ready: true,
    name: "Firefox",
    description: "Firefox",
    properties: { "application.name": "Firefox", "media.name": "Playback" }
  }, overrides)
}

assert.equal(model.isFocusedMediaPlayer(player()), true)
assert.equal(model.isFocusedMediaPlayer(player({ trackTitle: "Firefox", trackArtist: "" })), false)
assert.equal(model.isFocusedMediaPlayer({ identity: "A Game", trackTitle: "" }), false)
assert.equal(model.playerTitle(player({ trackTitle: "x".repeat(500) })).length, 384)
assert.equal(model.playerArtist(player({ trackArtist: "x".repeat(500) })).length, 192)
assert.equal(model.playerIdentity(player({ identity: "x".repeat(500) })).length, 96)
assert.equal(model.inputsOversized(Array(17), []), true)
assert.equal(model.inputsOversized([], Array(65)), true)
assert.deepEqual(model.focusedPlayers(Array(17).fill(player())), [])
assert.deepEqual(model.focusedPlayers([player({ dbusName: "x".repeat(257) })]), [])

const spotifyBridge = player({
  dbusName: "org.mpris.MediaPlayer2.chromium.instance1020772",
  desktopEntry: "",
  identity: "Chromium",
  trackTitle: "The Man Who Controls a UFO Fleet With His Mind - American Alchemy with Jesse Michels | Podcast on Spotify",
  trackArtist: "",
  trackAlbum: "",
  length: 10119.381,
  isPlaying: false
})
const spotifyDirect = player({
  dbusName: "org.mpris.MediaPlayer2.spotify",
  desktopEntry: "spotify",
  identity: "Spotify",
  trackTitle: " The Man Who Controls a UFO Fleet With His Mind",
  trackArtist: "",
  trackAlbum: "American Alchemy with Jesse Michels",
  length: 10119.381,
  isPlaying: false
})

assert.equal(model.duplicatePlayers(spotifyBridge, spotifyDirect), true)
assert.deepEqual(model.focusedPlayers([spotifyBridge, spotifyDirect]), [spotifyDirect])
assert.equal(model.selectFocusedPlayer(spotifyBridge, [spotifyBridge, spotifyDirect]), spotifyDirect)
assert.equal(model.selectFromFocusedPlayers(spotifyBridge, [spotifyDirect]), spotifyDirect)
assert.equal(model.selectFromFocusedPlayers(null, Array(17).fill(spotifyDirect)), null)

const separateBrowser = player({
  dbusName: "org.mpris.MediaPlayer2.firefox.instance77",
  desktopEntry: "firefox",
  identity: "Mozilla Firefox",
  trackTitle: spotifyBridge.trackTitle,
  trackArtist: "",
  trackAlbum: "",
  length: spotifyBridge.length,
  isPlaying: false
})
assert.equal(model.duplicatePlayers(spotifyBridge, separateBrowser), false)

const differentSpotifyEpisode = player({
  dbusName: "org.mpris.MediaPlayer2.spotify",
  desktopEntry: "spotify",
  identity: "Spotify",
  trackTitle: spotifyDirect.trackTitle,
  trackArtist: "",
  trackAlbum: spotifyDirect.trackAlbum,
  length: 2400,
  isPlaying: false
})
assert.equal(model.duplicatePlayers(spotifyBridge, differentSpotifyEpisode), false)

// Spotify titles a podcast media session with the show, never with itself, so
// the bridge carries no app name to match on. The identical duration is the
// only evidence the pair shares one session, and without it the episode is
// listed twice.
const podcastBridge = player({
  dbusName: "org.mpris.MediaPlayer2.chromium.instance405136",
  desktopEntry: "",
  identity: "Chromium",
  trackTitle: "#427 - \"I Infilitrate Secret Societies\" Epstein, Bohemian Grove & Bilderberg Group | Jon Ronson \u2022 Danny Jones Podcast",
  trackArtist: "",
  trackAlbum: "",
  length: 11331.621,
  isPlaying: true
})
const podcastDirect = player({
  dbusName: "org.mpris.MediaPlayer2.spotify",
  desktopEntry: "spotify",
  identity: "Spotify",
  trackTitle: "#427 - \"I Infilitrate Secret Societies\" Epstein, Bohemian Grove & Bilderberg Group | Jon Ronson",
  trackArtist: "",
  trackAlbum: "",
  length: 11331.621,
  isPlaying: true
})
assert.equal(model.duplicatePlayers(podcastBridge, podcastDirect), true)
assert.deepEqual(model.focusedPlayers([podcastBridge, podcastDirect]), [podcastDirect])

// A duration that only nearly agrees is not evidence of a shared session, so a
// bridge that never names the app stays separate.
const nearMissDirect = player({
  dbusName: "org.mpris.MediaPlayer2.spotify",
  desktopEntry: "spotify",
  identity: "Spotify",
  trackTitle: podcastDirect.trackTitle,
  trackArtist: "",
  trackAlbum: "",
  length: podcastDirect.length + 1,
  isPlaying: true
})
assert.equal(model.duplicatePlayers(podcastBridge, nearMissDirect), false)

const unique = stream()
assert.equal(model.chooseCapture(player(), [unique]).node, unique)
assert.equal(model.chooseVolumeNode(player({ isPlaying: false }), [unique]).node, unique)
assert.equal(model.chooseCapture(player(), [unique, stream({ name: "Firefox 2" })]).reason, "ambiguous")

const titled = stream({
  name: "Firefox Music",
  properties: { "application.name": "Firefox", "media.title": "A Great Song" }
})
assert.equal(model.chooseCapture(player(), [unique, titled]).node, titled)

const game = stream({
  properties: { "application.name": "Firefox", "media.role": "Game" }
})
assert.equal(model.chooseCapture(player(), [game]).reason, "unmatched")
assert.equal(model.chooseCapture(player(), Array(65).fill(unique)).reason, "too-many-streams")
assert.equal(model.captureTarget({ name: "x".repeat(257) }), "")
assert.equal(model.captureTarget({ name: "safe-node" }), "safe-node")
assert.equal(model.captureTarget({ name: "unsafe\nnode" }), "")

assert.deepEqual(model.parseFrame("0;0.5;1", 3), [0, 0.5, 1])
assert.equal(model.parseFrame("0;wat;1", 3), null)

const partial = model.frameChunk("", "0;0.5")
assert.equal(partial.ok, true)
assert.equal(partial.remainder, "0;0.5")
assert.deepEqual(model.frameChunk(partial.remainder, ";1\n").frames, ["0;0.5;1"])
assert.equal(model.frameChunk("", "x".repeat(385)).ok, false)
assert.equal(model.frameChunk("", "x".repeat(model.maxRawChunkChars() + 1)).ok, false)
assert.equal(model.frameChunk("", "\n".repeat(33)).ok, false)

// Album art allowlist. Every case below is one a player can put in
// `mpris:artUrl`, so each is a claim the README makes about what gets loaded.
const art = model.isSafeTrackArt

// Trusted cover CDNs, over HTTPS.
assert.equal(art("https://i.scdn.co/image/ab67616d"), true)
assert.equal(art("https://is1-ssl.mzstatic.com/image/thumb/x.jpg"), true)
assert.equal(art("https://i.ytimg.com/vi/x/hqdefault.jpg"), true)
assert.equal(art("https://resources.tidal.com/images/x.jpg"), true)
assert.equal(art("https://e-cdns-images.dzcdn.net/images/cover/x.jpg"), true)

// The authority is parsed, not string-matched: case and an explicit port are
// legitimate and must be accepted.
assert.equal(art("https://I.SCDN.CO/image/ab"), true)
assert.equal(art("https://i.scdn.co:8443/image/ab"), true)

// ...and an authority hidden behind a backslash or credentials is not.
assert.equal(art("https://evil.com\\.scdn.co/x.png"), false)
assert.equal(art("https://i.scdn.co@evil.com/x.png"), false)
assert.equal(art("https://evilscdn.co/x.png"), false)
assert.equal(art("https://scdn.co.evil.com/x.png"), false)

// Unlisted hosts, plaintext, and non-HTTP schemes are refused.
assert.equal(art("https://evil.example/x.png"), false)
assert.equal(art("http://i.scdn.co/image/ab"), false)
assert.equal(art("data:image/png;base64,iVBORw0KGgo="), false)
assert.equal(art("javascript:alert(1)"), false)
assert.equal(art(""), false)
assert.equal(art(null), false)
assert.equal(art("https://i.scdn.co/" + "x".repeat(2048)), false)

// Local files are allowed, but not the pseudo-filesystems, where a read is
// unbounded (/dev/zero) or is process state rather than a picture.
assert.equal(art("/home/user/.cache/cover.png"), true)
assert.equal(art("file:///home/user/.cache/cover.png"), true)
assert.equal(art("file://localhost/home/user/cover.png"), true)
assert.equal(art("file://evil.example/home/user/cover.png"), false)
assert.equal(art("/dev/zero"), false)
assert.equal(art("/proc/self/environ"), false)
assert.equal(art("/sys/kernel/notes"), false)
assert.equal(art("file:///proc/self/environ"), false)
assert.equal(art("file:///proc/self/../self/environ"), false)
// Percent-encoding must not smuggle a refused path past the prefix check.
assert.equal(art("file:///%70roc/self/environ"), false)
assert.equal(art("/tmp/../proc/self/environ"), false)

assert.equal(model.safeTrackArt("https://i.scdn.co/image/ab"), "https://i.scdn.co/image/ab")
assert.equal(model.safeTrackArt("/dev/zero"), "")

console.log("MediaModel tests passed")

// Direct PipeWire and MPRIS ownership (Omarchy 4.0 scoped plugin shell).
assert.deepEqual(model.toArray(null), [])
assert.deepEqual(model.toArray({ length: 2, 0: "a", 1: "b" }), ["a", "b"])
assert.equal(model.playbackStreams({ length: 1, 0: stream({ isSink: true }) }).length, 1)
assert.equal(model.isPlaybackStream(stream({ isSink: true })), true)
assert.equal(model.isPlaybackStream(stream({ isSink: false, type: "AudioOutStream" })), true)
assert.equal(model.isPlaybackStream(stream({ isSink: false, type: "AudioInStream" })), false)
assert.equal(model.isPlaybackStream(stream({ isStream: false, isSink: true })), false)
assert.deepEqual(model.playbackStreams(null), [])
assert.equal(model.playbackStreams([
  stream({ isSink: true }),
  stream({ isSink: true, audio: null }),
  stream({ isSink: false, type: "AudioInStream" }),
  null
]).length, 1)

const tabA = player({ dbusName: "org.mpris.MediaPlayer2.chromium.instance1", isPlaying: false, trackTitle: "Tab A" })
const tabB = player({ dbusName: "org.mpris.MediaPlayer2.chromium.instance2", isPlaying: true, trackTitle: "Tab B" })
assert.equal(model.playerForKey([tabA, tabB], tabB.dbusName), tabB)
assert.equal(model.playerForKey([tabA, tabB], ""), null)
assert.equal(model.playerForKey([tabA, tabB], "x".repeat(257)), null)
// The audible source wins over a paused pick.
assert.equal(model.chooseActivePlayer(tabA.dbusName, [tabA, tabB]), tabB)
// A playing pick stays selected.
assert.equal(model.chooseActivePlayer(tabB.dbusName, [tabA, tabB]), tabB)
// With nothing playing the pick is kept rather than jumping to the first.
const pausedB = player({ dbusName: tabB.dbusName, isPlaying: false, trackTitle: "Tab B" })
assert.equal(model.chooseActivePlayer(pausedB.dbusName, [tabA, pausedB]), pausedB)
assert.equal(model.chooseActivePlayer("", [tabA, pausedB]), tabA)
assert.equal(model.chooseActivePlayer("", []), null)
assert.equal(model.chooseActivePlayer("", Array(17).fill(tabA)), null)

console.log("media model tests passed")
