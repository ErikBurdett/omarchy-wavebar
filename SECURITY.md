# Security policy

## Reporting a vulnerability

Please report privately through GitHub's
[private vulnerability reporting](https://github.com/ErikBurdett/omarchy-wavebar/security/advisories/new)
rather than opening a public issue. Include the plugin version from
`manifest.json`, your Omarchy version (`cat /usr/share/omarchy/version`), and
the steps or media source that triggers the behaviour.

Expect an acknowledgement within a week. Fixes are released on `main`, which is
what users' installs fast-forward to.

## Supported versions

Only the current `main` is supported. `omarchy plugin update` fast-forwards
every install to it, so there are no maintained release branches to backport
to.

## What is in scope

WaveBar runs inside the resident `omarchy-shell` process, so a bug here has the
shell's privileges for the whole session. These areas are the ones worth
scrutiny:

- **Subprocess execution.** The waveform recorder runs `/usr/bin/python3` and
  `/usr/bin/pw-record` at fixed absolute paths with a cleared environment, and
  validates ownership and mode before executing. Anything that reintroduces
  PATH-controlled execution, or lets a media source influence the argument
  vector, is a vulnerability.
- **MPRIS metadata as untrusted input.** Titles, artists, album names, and
  artwork URLs come from whatever players are running and must never be treated
  as trusted. They are bounded in length and rejected when oversized.
- **Artwork loading.** Cover art is off by default. When enabled, only local
  paths and an allowlist of cover CDNs are loaded; every other URL is refused.
  A bypass that causes a request to an unlisted host is a vulnerability.
- **Configuration writes.** The panel writes only the plugin's own settings
  into `~/.config/omarchy/shell.json`. Writing anything outside that entry, or
  without the user acting, is a vulnerability.

## What is not in scope

- Behaviour of a media player, PipeWire, or Omarchy itself. Report those
  upstream.
- Anything that requires an attacker to already be able to run code as your
  user, since the plugin runs with exactly those privileges.
