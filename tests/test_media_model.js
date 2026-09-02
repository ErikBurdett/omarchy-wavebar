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

const unique = stream()
assert.equal(model.chooseCapture(player(), [unique]).node, unique)
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

assert.deepEqual(model.parseFrame("0;0.5;1", 3), [0, 0.5, 1])
assert.equal(model.parseFrame("0;wat;1", 3), null)

console.log("MediaModel tests passed")
