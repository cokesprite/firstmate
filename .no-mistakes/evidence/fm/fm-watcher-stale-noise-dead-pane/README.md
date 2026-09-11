# Live validation: fm-watcher agent-gone stale-noise termination (branch fm/fm-watcher-stale-noise-dead-pane)

Driven 2026-09-12 against the real `bin/fm-watch.sh` subprocess with the real
`bin/fm-backend.sh` tmux adapter talking to a real tmux 3.6a server (dedicated
session `fmlv51467`, isolated FM_HOME/state under /tmp, real
`fm-crew-state.sh`, real wake-queue/drain). Live panes: `fm-husk` (bare shell →
recovery-grade probe reads `dead`; later resurrected with a foreground
`grok`-named process → `alive`), `fm-gone` (killed mid-test → `missing`),
`fm-aaa` (live agent), `fm-zzz` (dead shell, record retired mid-run).

## scenarioA-first-surface.out
Watcher stdout for the 2026-08-27 incident shape: a bare-shell husk with a
classified stale hash and a wedge timer already past its threshold
(FM_STALE_ESCALATE_SECS=1). Poll 1 recorded `pending:dead` with NO wake and NO
wedge escalation (marker file state captured in the transcript session); poll 2
confirmed and surfaced exactly one wake:

    stale: fmlv51467:fm-husk (agent gone: dead - the endpoint answers but holds no live agent ...)

`.stale-since-` and `.wedge-escalations-` were removed at the surface; the tmux
window itself was still present afterwards (no-force/no-cleanup boundary). The
wake went through the real `fm-wake-drain.sh` ack protocol.

## scenarioA-churn-silence.out
After typing recovery steers into the dead shell (`echo recovery-steer-1/2` —
the churn that used to reset the one-shot suppression and re-alarm), repeated
watcher relaunches stayed silent for fm-husk across 5-8 polls each: the
established `gone:dead` marker short-circuits before the capture, so pane churn
never re-arms classification. (The one wake visible in the transcript is a
DIFFERENT fixture window, fm-gone, going through its own fresh first-sight
contract; fm-husk produced no output and kept its marker through every run.)

## scenarioA-resurrection.out
After `exec -a grok /bin/sleep` was launched in the husk pane, the probe read
`alive`; the watcher cleared `.agentgone-*` ("agent reads alive again; resumed
stale tracking" in the triage log) and kept polling silently — ordinary
supervision resumed.

## scenarioB-missing-surface.out / scenarioB-missing-silence.out
The 2026-09-12 pane_not_found family: fm-gone's tmux window was killed. Poll 1
recorded `pending:missing` silently (failed capture → recovery probe reads
missing); poll 2 surfaced exactly one

    stale: fmlv51467:fm-gone (agent gone: missing - the endpoint itself is authoritatively absent ...)

and exited. Eight subsequent polls in a fresh watcher produced zero wakes
(missing-silence.out is empty).

## scenarioC-retired-sweep.out + scenarioC-triage.log
Teardown raced the poll loop: fm-zzz's task record (meta) was deleted while the
watcher was mid-run. Result: no stale wake for fm-zzz, and the sweep retired
its whole per-window marker family (`.hash/.count/.stale/...` gone) while the
recorded windows (fm-aaa: 5 markers, fm-husk) kept theirs. scenarioC-triage.log
also carries the full agent-gone surface history for the run.

## scenarioD-misread-collapse.out
Adversarial: a contradictory transient misread (`pending:dead` on a window
whose real probe reads `alive`) collapsed silently on the next poll — marker
removed, "agent reads alive again; resumed stale tracking", no wake, watcher
kept running.

## Not driven against a live herdr server
The event fast-path scenarios (`event_wait_or_sleep` absorbing a blocked push
transition for an established gone:* identity, still committing it; delivering
normally once the agent reads alive) were exercised by
`tests/fm-supervision-events.test.sh` against the real watcher code with the
herdr dispatchers stubbed — standing up an isolated herdr session in the
user's running herdr server was out of scope. The established-suspension-survives-
inconclusive-read asymmetry (review round 1, declined F2) was likewise not
inducible deterministically on a real tmux backend.
