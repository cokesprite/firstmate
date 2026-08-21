# PLAN dispatch preflight verification

Audience: maintainer verification.

This record holds active empirical evidence for the PLAN execution rehearsal gate.
`.agents/skills/plan-execution/SKILL.md` owns the readiness and admission decision, and `bin/fm-plan-preflight.sh`'s header plus `--help` own the producer schema, rehearsal mechanics, evidence schema, and every refusal.
The behavior suite `tests/fm-plan-preflight.test.sh` and the handoff coverage in `tests/fm-brief.test.sh` are the regression proof; this record shows the pilot acceptance case running end to end.

Verified on 2026-08-21 on macOS (Darwin 25.5.0), Python 3.12, git 2.52.0.

## The pilot acceptance case

The fixture replays the PowerAgent queue-pressure omission: the PLAN contract declares two OpenAPI generator outputs (`docs/openapi.json`, `docs/openapi-by-path/**`), while the deterministic generator (`python3 scripts/gen_openapi.py`, mirroring `scripts/generate_openapi.py`) also rewrites a third committed directory, `docs/openapi-platform-simple/`.
Committed generated content is byte-identical to the generator output, so a git diff observes nothing; only the rehearsal's filesystem-level write-set delta sees the rewrite.

The two-declaration PLAN fails before dispatch, naming the undeclared write:

```sh
$ bin/fm-plan-preflight.sh rehearse plans/PLAN.md --repo <clone>; echo $?
UNDECLARED_WRITE: openapi wrote docs/openapi-platform-simple/pet.simple.openapi.json (covered by neither allowed_scope.paths nor the producer's declared outputs)
REHEARSAL: FAIL plan_id=pilot-openapi base=main@<sha> undeclared=1 evidence=<PLAN.md.preflight.json>
error: closure violation: every producer write must be covered by allowed_scope.paths or the producer's declared outputs; ...
5
$ bin/fm-plan-preflight.sh verify plans/PLAN.md --repo <clone>; echo $?
UNDECLARED_WRITE: openapi wrote docs/openapi-platform-simple/pet.simple.openapi.json ...
error: rehearsal evidence verdict is fail; ...
5
```

The pre-authorized mechanical amendment then proves the missing directory is the declared producer's deterministic output (two identical clean reruns at the recorded baseline), edits the contract segment (`allowed_scope.paths` plus the producer's `outputs`), adds the `Amendments:` line, and refreshes the evidence:

```sh
$ bin/fm-plan-preflight.sh amend plans/PLAN.md --producer openapi --add 'docs/openapi-platform-simple/**'; echo $?
AMENDMENT: PASS plan_id=pilot-openapi producer=openapi added=docs/openapi-platform-simple/** plan_sha256=<sha> evidence=<...>
0
$ bin/fm-plan-preflight.sh verify plans/PLAN.md; echo $?
PREFLIGHT: PASS plan_id=pilot-openapi contract_version=1 base=main@<sha> producers=1 evidence=<...>
0
```

`bin/fm-brief.sh --plan` enforces the same gate at the dispatch handoff: a contract-bearing PLAN with missing or failed evidence is refused before any brief is written, a passing PLAN's brief carries `Preflight result: PASS` plus the evidence pointer and the amendment boundary, and a prose-only PLAN scaffolds with `Preflight result: LEGACY` (never labeled rehearsed).

## Guarantee map

| Guarantee | Regression proof |
| --- | --- |
| Rehearsal observes generator write-sets git cannot see (content-identical rewrites), in a proven isolated disposable worktree | `tests/fm-plan-preflight.test.sh` (rehearsal pass, isolation, and evidence verification) |
| The pilot omission (two declared outputs, one undeclared) fails before dispatch; declaring the exact third output passes | `tests/fm-plan-preflight.test.sh` (pilot omission) |
| Closure also fails on unrelated handwritten/source writes, dirty baselines, baseline drift, identity drift, and malformed evidence | `tests/fm-plan-preflight.test.sh` (handwritten, dirty/drift, identity) |
| The mechanical amendment is machine-proven (declared producer, identical clean reruns, full closure) and recorded in the PLAN and evidence; every other class is refused | `tests/fm-plan-preflight.test.sh` (pilot repair, amendment refusals) |
| Legacy PLANs get an explicit never-rehearsed result everywhere | `tests/fm-plan-preflight.test.sh` (legacy results), `tests/fm-brief.test.sh` (preflight gate) |
| The dispatch handoff refuses an applicable failed/missing preflight and carries the result into the worker's brief | `tests/fm-brief.test.sh` (preflight gate binds the brief) |
