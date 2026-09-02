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

console.log("MediaModel tests passed")
