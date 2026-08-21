---
name: plan-execution
description: >-
  Agent-only decision procedure for turning captain-approved automation-ready
  PLANs into parallel worker dispatches.
  Load before dispatching an approved PLAN into execution, and before admitting
  another PLAN worker alongside in-flight PLAN work.
user-invocable: false
metadata:
  internal: true
---

# plan-execution

This skill is the single owner of PLAN readiness gating, intake overlap triage, and parallel admission control for the PLAN-to-MR default path (captain-approved roadmap Phase 0, 2026-08-20).
`AGENTS.md` section 7 owns the always-loaded default path, delivery-mode and yolo resolution, and the general overlap principle this skill specializes.
`bin/fm-brief.sh` owns the `--plan` scaffold mechanics, and `bin/fm-plan-preflight.sh` owns the executable preflight mechanics (contract lint, rehearsal, evidence, amendment); this skill owns the decisions they serve and points at both rather than duplicating them.
Active verification evidence for the preflight gate lives in `docs/verification/plan-preflight.md`.

## Readiness gate

An automation-ready PLAN is a `reframe-and-plan` product with zero open material decisions and zero critical evidence gaps, a passing machine contract lint, and a passing clean-worktree execution rehearsal of its declared deterministic producers against the target repository's current baseline.
`bin/fm-plan-preflight.sh` owns the contract lint, the rehearsal, the evidence schema, and every refusal mechanic; read its header and run it rather than re-deriving any of that here.
When a decision or gap remains open, the PLAN is not dispatchable: route it back to the captain or a follow-up planning pass rather than letting a worker re-ask requirements mid-execution.

A PLAN without a machine-readable contract segment gets the tool's explicit `legacy` result: it remains dispatchable under the prose readiness judgment above (backward compatible), but it was never rehearsed, must never be labeled rehearsed, and the legacy label goes into the task's backlog note.
Prefer adding a contract segment and a rehearsal before admitting a legacy PLAN to unattended parallel execution.

Dispatch follows the section 7 default path: scaffold with `bin/fm-brief.sh --plan <path>`, then spawn and supervise like any other ship task.
The scaffold refuses a contract-bearing PLAN whose preflight is failed, missing, or stale, so a dispatch cannot skip the gate; repair it with `bin/fm-plan-preflight.sh rehearse` (or a proven amendment), or return the PLAN to planning - never work around the refusal.
The worker's brief carries the preflight result and the evidence pointer before it touches code.

### Mechanical producer-output amendment

A declared deterministic producer whose observed write-set exceeds its declared outputs is the single failure class that may continue without another captain round, and only when `bin/fm-plan-preflight.sh amend` proves every condition mechanically: the producer was declared in the approved PLAN, each added path is that producer's deterministic generated output shown by identical clean reruns, no handwritten, source, API, or product-semantic change is involved, and the amendment is recorded in the PLAN's Amendments record and the MR's PLAN Contract section.
A hand-widened scope, an undeclared producer, a nondeterministic rerun, an unproven output, or any other uncovered write remains a stop-and-return decision to the captain.
This authority applies identically to firstmate repairing a failed rehearsal before dispatch and to a worker discovering an omission mid-implementation.

## Overlap triage

Before dispatch, classify the PLAN against every in-flight and queued PLAN task using its stated file scope, module ownership, data model, and API surface.
Verify ambiguous scope claims against the code, and take the more conservative class while overlap remains unknown.

| Conflict class | Admission |
| --- | --- |
| Fully independent files, modules, data model, and API surface | Dispatch in parallel immediately |
| Shared module with disjoint areas | Admit in parallel; record the risk flag in both tasks' backlog notes |
| Same file or same interface | Queue behind the in-flight task |
| Database schema or other shared mutable external state | Serialize |

This table specializes section 7's general overlap rule for unattended PLAN execution: attended work treats same-file overlap as a risk signal, but two workers running without a human in the loop cannot reconcile a shared file or interface, so here it is a concrete reconciliation-unsafe condition.
Queued and serialized PLANs stay durable in the backlog and are re-evaluated at every teardown and heartbeat like any other blocked work.

## Parallel admission control

Start at 2 parallel PLAN workers.
Scale up only while all three hold: the Kimi 429 rate stays low, build and validation capacity is not contended, and the open-MR count stays within the captain's review bandwidth.
Never add a worker while the open-MR backlog exceeds the captain's review capacity: that is human review backpressure, and output past it becomes unreviewed MR and evidence debt rather than delivery.
Effective throughput is min(model throughput, build throughput, validation throughput, captain review throughput), so adding workers beyond the tightest term increases nothing.
