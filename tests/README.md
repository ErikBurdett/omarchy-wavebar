# Integration checks

The automated tests cover WaveBar's parent-death setup race, signal-wakeable
PCM reader, leader-exits-first process group, final TERM-to-KILL escalation,
manifest contract, model limits, and component-destruction wiring.

For a release candidate, also run this live teardown check in an Omarchy
session while local media is playing:

```sh
pgrep -af 'waveform.py|pw-record'
omarchy-shell io.github.erikburdett.wavebar restart
pgrep -af 'waveform.py|pw-record'
omarchy restart shell
pgrep -af 'waveform.py|pw-record'
```

After the plugin restart, no process group from the first listing may remain.
After the shell restart, no process group from the second listing may remain;
one fresh WaveBar helper group may appear when media playback is still active.
Repeat with rapid restarts. Every old process group must disappear within the
one-second TERM grace period plus normal scheduling tolerance. The automated
suite separately forces the leader-exits-first and TERM-ignoring-descendant
cases without requiring manual process manipulation.
