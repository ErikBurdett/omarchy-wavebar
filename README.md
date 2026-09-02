# WaveBar: Waveform Media Controller

WaveBar is a standalone Omarchy bar plugin that combines a live audio
waveform with focused MPRIS playback controls for browsers, Spotify, and other
desktop media players.

## Features

- Shows meaningful browser and desktop-player media exposed through MPRIS.
- Supports Spotify and other MPRIS-compatible players.
- Ignores games, notification sounds, and generic application audio.
- Visualizes only a confidently matched local PipeWire playback stream.
- Provides previous, play/pause, next, seek, volume, and source controls.
- Controls the matched local PipeWire stream volume for browsers whose MPRIS
  endpoint ignores volume writes.
- Selecting a media source immediately starts it and pauses the prior source.
- Keeps long titles inside the widget and source list with horizontal scrolling.
- Can live in the left, center, or right section of the Omarchy bar.

## How media filtering works

WaveBar uses Omarchy's built-in `omarchy.media` MPRIS service and requires
meaningful track metadata. Games and ordinary audio streams are not shown just
because they make sound.

For the waveform, the selected player is matched to a PipeWire playback
stream. A track-title or artist match wins. An app-only match is accepted only
when exactly one stream belongs to that app. If several browser streams are
indistinguishable, playback controls remain available but the waveform stays
quiet rather than visualizing an unrelated game or tab.

## Install

```sh
omarchy plugin add https://github.com/ErikBurdett/omarchy-wavebar.git --enable
```

## Usage

- Use the bar buttons for previous, play/pause, and next.
- Click the waveform or title to open the details panel.
- Scroll over the waveform or title for previous or next.
- In the panel, Space toggles playback, Left/Right seek five seconds, and P/N
  select previous/next.
- Click any entry under **Media sources** to select and immediately play it.

Browser media must expose MPRIS/Media Session metadata. Spotify and other
desktop players work through their normal MPRIS interface. A remote Spotify
Connect device can still be controlled, but it has no local PipeWire audio to
visualize.

## Choose the bar position

Use Omarchy's bar settings UI, or place WaveBar from the command line:

```sh
omarchy bar move io.github.erikburdett.wavebar --section left
omarchy bar move io.github.erikburdett.wavebar --section center
omarchy bar move io.github.erikburdett.wavebar --section right
```

You can also position it relative to another widget:

```sh
omarchy bar move io.github.erikburdett.wavebar --after omarchy.workspaces
omarchy bar move io.github.erikburdett.wavebar --before omarchy.tray
```

The manifest uses `left` only as the initial default. Omarchy preserves the
user's chosen placement in `~/.config/omarchy/shell.json`.

Widget display settings can be added inline to the same entry:

```json
{
  "id": "io.github.erikburdett.wavebar",
  "showControls": true,
  "showTitle": true,
  "hideWhenPaused": false,
  "waveformWidth": 72,
  "maxTitleWidth": 150
}
```

`waveformWidth` is constrained to 40–240 pixels and `maxTitleWidth` to
60–320 pixels.

## Dependencies and security

- Omarchy 4 / Quattro shell
- Quickshell's MPRIS and PipeWire services
- `pw-record` from PipeWire
- `setpriv` from util-linux
- Python 3 standard library

WaveBar opens no network connections and rejects MPRIS-provided artwork rather
than loading an untrusted URL or file. It uses only local MPRIS and PipeWire
services. Media collections, metadata fields, capture targets, waveform frames,
and user-configurable widths all have explicit limits.

The service invokes fixed `/usr/bin/python3`, `/usr/bin/setpriv`, and
`/usr/bin/pw-record` paths with a cleared environment and no shell. Its helper
validates system-executable ownership and modes, discards recorder diagnostics,
and supervises the recorder in a separate process group with TERM-to-KILL
cleanup and guaranteed reaping. WaveBar requests no elevated privileges, writes
no user configuration, and includes no installer. It runs inside the existing
`omarchy-shell`; it never starts another Quickshell process.

## Validate

```sh
PLUGIN_DIR="$HOME/.config/omarchy/plugins/io.github.erikburdett.wavebar"
omarchy plugin validate "$PLUGIN_DIR"
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell \
  "$PLUGIN_DIR/Service.qml" "$PLUGIN_DIR/BarWidget.qml" \
  "$PLUGIN_DIR/Panel.qml" "$PLUGIN_DIR/Waveform.qml" \
  "$PLUGIN_DIR/MarqueeText.qml"
node "$PLUGIN_DIR/tests/test_media_model.js"
python3 "$PLUGIN_DIR/tests/test_waveform.py"
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
  qmltestrunner -input "$PLUGIN_DIR/tests" -import /usr/share/omarchy/shell
```

Inspect the live service:

```sh
omarchy-shell io.github.erikburdett.wavebar status
```

## Remove

```sh
omarchy plugin remove io.github.erikburdett.wavebar
```

## License

[MIT](./LICENSE) © 2026 Erik Burdett
