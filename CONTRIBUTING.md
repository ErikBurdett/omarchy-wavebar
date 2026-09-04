# Contributing to WaveBar

Thanks for helping. WaveBar runs inside the long-lived `omarchy-shell`
Quickshell process, which makes a few things different from an ordinary
project. Please read the two sections below before opening a pull request —
they cover the mistakes that are easiest to make here and hardest to catch.

## Restart the shell after editing QML

Quickshell holds the compiled component. Neither `omarchy-shell shell
rescanPlugins` nor disabling and re-enabling the plugin drops it, so the old
code keeps running and you end up testing the previous version:

```sh
omarchy-restart-shell
```

Do this before concluding anything about a QML change, and confirm the change
actually took effect.

## Run it, do not only lint it

A QML type that never resolves is not a parse error. `qmlformat -n` accepts it,
the unit tests pass, `omarchy plugin validate` passes, and the component then
fails to load at a user's login. The only way to catch this is to run the
plugin and read the shell log:

```sh
omarchy-restart-shell
journalctl --user --since "1 minute ago" | grep -i wavebar
```

A clean run prints no warnings for WaveBar. Open the panel and exercise what
you changed before submitting.

## Before you open a pull request

1. Run every check in the [Validate](./README.md#validate) section of the
   README. CI runs the manifest, Python, JavaScript, and `qmllint` checks, so
   a failure there will find you anyway.
2. Restart the shell and confirm the log is clean, as above.
3. Add a `## Unreleased` entry to [CHANGELOG.md](./CHANGELOG.md) describing the
   change and why it was made.
4. Leave `version` in `manifest.json` alone. The maintainer bumps it when
   cutting a release, so that pull requests never conflict over it.
5. If you add a widget setting, add it to **both** `barWidget.defaults` and
   `barWidget.schema` in `manifest.json`. `tests/test_manifest.py` asserts the
   two agree key for key.

New QML files must declare `pragma ComponentBehavior: Bound`, including files
vendored from Omarchy. The lint gate does not exempt unqualified access, and
Omarchy's own copies are never linted by this repository, so they arrive with
warnings that only surface here.

## How releases reach users

`main` is the release channel. `omarchy plugin add` clones the default branch
and `omarchy plugin update` fast-forwards to it, so anything merged to `main`
ships to every user on their next update. There is no staging between `main`
and the people running this plugin.

Two consequences worth knowing:

- `main` is never force-pushed or rebased. The updater fast-forwards, so a
  rewritten history fails for every existing user with an error that blames
  their local changes. Mistakes are corrected by reverting forward.
- Users are shown `git diff` of the incoming change and asked to confirm it
  before it is applied, so commit messages and diffs are read by people, not
  just by maintainers. Write them accordingly.

## Reporting security issues

Please do not open a public issue. See [SECURITY.md](./SECURITY.md).
