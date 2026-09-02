# Media Waveform for Omarchy

A focused media controller for the Omarchy bar with a live waveform, MPRIS
playback controls, browser media detection, Spotify support, and optional
`rosakodu.dock` hosting.

## Features

- Shows meaningful browser and desktop-player media exposed through MPRIS.
- Supports Spotify and other MPRIS-compatible players.
- Ignores games, notification sounds, and generic application audio.
- Visualizes only a confidently matched local PipeWire playback stream.
- Provides previous, play/pause, next, seek, volume, and source controls.
- Selecting a media source immediately starts it and pauses the prior source.
- Can live in the left, center, or right section of the Omarchy bar.
- Can be hosted as a compact media control by `rosakodu.dock`.

## How media filtering works

The plugin uses Omarchy's built-in `omarchy.media` MPRIS service and requires
meaningful track metadata. Games and ordinary audio streams are not shown just
because they make sound.

For the waveform, the selected player is matched to a PipeWire playback
stream. A track-title or artist match wins. An app-only match is accepted only
when exactly one stream belongs to that app. If several browser streams are
indistinguishable, playback controls remain available but the waveform stays
quiet rather than visualizing an unrelated game or tab.

## Install

```sh
omarchy plugin add https://github.com/ErikBurdett/omarchy-media-waveform.git --enable
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

Use Omarchy's bar settings UI, or place the controller from the command line:

```sh
omarchy bar move io.github.erikburdett.media-waveform --section left
omarchy bar move io.github.erikburdett.media-waveform --section center
omarchy bar move io.github.erikburdett.media-waveform --section right
```

You can also position it relative to another widget:

```sh
omarchy bar move io.github.erikburdett.media-waveform --after omarchy.workspaces
omarchy bar move io.github.erikburdett.media-waveform --before omarchy.tray
```

The manifest uses `left` only as the initial default. Omarchy preserves the
user's chosen placement in `~/.config/omarchy/shell.json`.

Widget display settings can be added inline to the same entry:

```json
{
  "id": "io.github.erikburdett.media-waveform",
  "showControls": true,
  "showTitle": true,
  "hideWhenPaused": false,
  "waveformWidth": 72,
  "maxTitleWidth": 150
}
```

## Use it in rosakodu.dock

Media Waveform implements the dock's generic hosted-widget contract without
taking a hard dependency on the dock. With both plugins installed and enabled,
add it using the dock IPC API:

```sh
omarchy-shell rosakodu.dock addWidget io.github.erikburdett.media-waveform
```

Then choose the dock's widget side in **Dock Settings → Dock Widgets**, or run:

```sh
omarchy-shell rosakodu.dock setWidgetPosition left
omarchy-shell rosakodu.dock setWidgetPosition right
```

The dock currently limits its widget list to two entries. Adding Media
Waveform may replace another non-Apps dock widget; removing it returns the
widget to its saved Omarchy bar position:

```sh
omarchy-shell rosakodu.dock removeWidget io.github.erikburdett.media-waveform
```

## Dependencies and security

- Omarchy 4 / Quattro shell
- Quickshell's MPRIS and PipeWire services
- `pw-record` from PipeWire
- Python 3 standard library

The helper runs as the current user, opens no network connection, invokes no
shell, and requests no elevated privileges. It starts one `pw-record` child
only while a confidently matched local media stream is playing. The plugin
runs inside the existing `omarchy-shell`; it never starts another Quickshell
process.

## Validate

```sh
PLUGIN_DIR="$HOME/.config/omarchy/plugins/io.github.erikburdett.media-waveform"
omarchy plugin validate "$PLUGIN_DIR"
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell \
  "$PLUGIN_DIR/Service.qml" "$PLUGIN_DIR/BarWidget.qml" \
  "$PLUGIN_DIR/Panel.qml" "$PLUGIN_DIR/Waveform.qml"
node "$PLUGIN_DIR/tests/test_media_model.js"
python3 "$PLUGIN_DIR/tests/test_waveform.py"
```

Inspect the live service:

```sh
omarchy-shell io.github.erikburdett.media-waveform status
```

## Remove

If the controller is hosted by the dock, return it to the bar first, then
remove the plugin:

```sh
omarchy-shell rosakodu.dock removeWidget io.github.erikburdett.media-waveform
omarchy plugin remove io.github.erikburdett.media-waveform
```

## License

[MIT](./LICENSE) © 2026 Erik Burdett
