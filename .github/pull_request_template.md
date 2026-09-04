## What this changes

<!-- What the change does, and why. Link an issue if there is one. -->

## How it was tested

<!-- Describe what you actually exercised, not just what you ran. -->

## Checklist

- [ ] Ran the checks in the [Validate](../README.md#validate) section of the README
- [ ] Ran `omarchy-restart-shell` and confirmed the change took effect in a live shell
- [ ] `journalctl --user | grep -i wavebar` reports no warnings for WaveBar
- [ ] Opened the panel and exercised the affected UI
- [ ] Added a `## Unreleased` entry to `CHANGELOG.md`
- [ ] Left `version` in `manifest.json` unchanged
- [ ] New widget settings appear in both `barWidget.defaults` and `barWidget.schema`
- [ ] Any new QML file declares `pragma ComponentBehavior: Bound`
- [ ] Documentation claims still match what the code does

<!--
Reminder: a QML type that never resolves is not a parse error. It passes the
unit tests and the manifest validator, then fails to load at a user's login.
Restarting the shell and reading the log is the only way to catch it.
-->
