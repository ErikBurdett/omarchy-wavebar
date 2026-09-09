# Changelog

## 1.1.1 — 2026-09-08

### Compatibility

- Stopped depending on Omarchy's `omarchy.media` service. Omarchy 4.0.3
  scopes first-party service access to plugins that declare the `bar`
  capability, which made `firstPartyServiceFor("omarchy.media")` return null
  for WaveBar and left the widget hidden. The plugin now reads MPRIS and
  PipeWire directly through Quickshell's own singletons and reproduces the
  same playback-stream matching and active-source selection, so WaveBar works
  on all Omarchy 4.x releases before and after the capability change.
- Fixed the panel's settings toggles, which stopped writing on Omarchy 4.0.3:
  `mutateShellConfig` is now gated behind the full `bar` capability, so a
  bar-widget plugin saves its own entry with `updateEntryInline` instead.

## 1.1.0 — 2026-09-08

Contributed by [@JaxonWright](https://github.com/JaxonWright) in
[#1](https://github.com/ErikBurdett/omarchy-wavebar/pull/1).

### Media and interface

- Added a `showArtist` setting to display the artist name after the track title
  in the widget (matching the panel tooltip).
- Added a `showFullTitle` setting to show the whole track title without
  truncating or horizontal scrolling.
- Added a `showCover` setting to show the album art thumbnail between the
  waveform and the track title, and as the panel header art.
- Added a `groupControls` setting to keep the previous/play/pause/next buttons
  grouped beside the waveform instead of splitting previous to the far side.
- Added an in-panel **Settings** section (behind a cog button) that toggles
  title, artist, full-title, album-cover, controls, grouped-controls, and
  hide-when-paused options.
- Used squared theming for the waveform bars and progress/volume controls via a
  plugin-local `WavebarSlider`, keeping other Omarchy panels' sliders unchanged.
- Corrected panel tooltips to use the bar's native tooltip targets and made the
  previous button tooltip switch targets when controls are grouped.

### Security

- Reintroduced opt-in album art with a hardened allowlist: only local files and
  trusted cover CDNs (Apple Music, Spotify, YouTube, Tidal/Deezer) over HTTPS
  are ever loaded; all other MPRIS-provided URLs are rejected and treated as no
  cover. The rules live in `MediaModel.js`, so bar and panel share one check and
  the CI unit tests can reach it.
- Matched cover hosts on the parsed authority rather than the raw URL string.
  The string test refused legitimate URLs (an uppercase host, an explicit port)
  and accepted an authority obscured by a backslash or embedded credentials.
- Refused local pseudo-file paths (`/proc`, `/sys`, `/dev`) as cover art, where
  a read is unbounded or returns process state instead of an image.
- Read `showControls`, `showTitle`, and `hideWhenPaused` the same string-safe
  way as the other four settings. A hand-edited `shell.json` can hold the string
  `"true"`, which the widget read as off while the panel's switch read it as on.

## 1.0.3 — 2026-09-04

### Media and interface

- Deduplicated a Spotify podcast whose Chromium bridge names the show rather
  than the app, which left the episode listed twice while it played in the
  desktop client. A bridge that never names the app is now accepted as a
  mirror when both endpoints report exactly the same duration, since only one
  underlying session produces that. Durations that merely agree closely still
  require the app name, so unrelated sessions of a similar length stay apart.

## 1.0.2 — 2026-09-02

### Security and lifecycle

- Replaced PATH-controlled execution with fixed `/usr/bin/python3` and
  `/usr/bin/pw-record` paths, root-ownership and mode validation, capability
  rejection, and a cleared child environment.
- Added strict player, stream, metadata, target, protocol-frame, raw-chunk,
  and user-configurable width limits. Oversized collections now fail closed.
- Removed MPRIS-controlled artwork ingestion so remote, data, special-file,
  and oversized image sources never reach the resident shell.
- Added a race-checked Linux parent-death handshake before recorder execution.
- Added a stable process-group supervisor and subreaper that preserve group
  identity through TERM-to-KILL teardown and reap all adopted descendants.
- Added a nonblocking signal wakeup pipe so interrupted PCM reads cannot delay
  teardown, including when a descendant ignores TERM and keeps stdout open.
- Removed the final PGID-reuse window by detaching the managed group from the
  asynchronous signal handler before its pinned leader is reaped.
- Dependency and unsafe-runtime failures now fail closed, stop automatic retry
  loops, and display a bounded actionable message in the media panel.

### Media and interface

- Deduplicated Spotify/Electron browser mirrors while keeping independent
  browser sessions separate.
- Made source selection immediately play the chosen session and pause the
  previously playing session after a successful switch.
- Restored volume control through the confidently matched PipeWire stream,
  with MPRIS fallback for supported non-browser players.
- Added bounded marquee titles to the bar and source rows.
- Replaced the source repeater with a height-capped, scrollable list.
- Added native Omarchy widget settings for controls, title visibility, paused
  visibility, waveform width, and title width.
- Corrected vertical-bar waveform geometry and control visibility, and made a
  hidden widget occupy no bar space.
- Resolved the helper relative to Omarchy's installed plugin source directory
  while retaining an absolute-path fallback.
- Reused one bounded PipeWire matching result for waveform capture and volume.

### Packaging and validation

- Renamed the listing to **WaveBar: Waveform Media Controller** and added the
  marketplace preview image.
- Documented installation, updates, positioning, settings, dependencies,
  security boundaries, validation, live lifecycle checks, and removal.
- Added manifest-contract, media-model, marquee, process-race, parent-death,
  leader-exits-first, blocked-read, TERM-to-KILL, and descendant-reaping tests.
- Added a least-privilege validation workflow with its external action pinned
  to a full commit SHA.
- Made standalone QML linting deterministic: Omarchy modules are supplied
  explicitly, dynamic host-property diagnostics are narrowly informational,
  every other warning is fatal, and delegate scopes are compiler-bound.
