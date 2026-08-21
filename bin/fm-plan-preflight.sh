#!/usr/bin/env bash
# fm-plan-preflight.sh (preflight contract v1) - single firstmate-side executable
# owner of PLAN dispatch preflight: plan-contract lint, clean-worktree execution
# rehearsal of a PLAN's declared deterministic producers, rehearsal-evidence
# verification, and the pre-authorized mechanical producer-output amendment.
#
# Ownership split (one-owner rule): .agents/skills/plan-execution/SKILL.md owns
# the readiness and admission DECISION (when a PLAN may dispatch, and when the
# mechanical amendment may continue without another captain round). This script
# owns the MECHANICS: the producer schema, the rehearsal, the evidence schema,
# and every refusal below. The skill points here and never restates mechanics.
# This is the only plan-contract parser tracked in the firstmate repo; the
# separately maintained reframe-and-plan / drive-plan-to-validated-mr /
# plan-fidelity packages consume the same schema and are synchronized out of
# band after the schema lands here.
#
# Commands:
#   fm-plan-preflight.sh lint <plan.md>
#       Parse the single ```plan-contract fenced block and evaluate the
#       automation-ready gate plus the producer schema. No git or python3 work.
#   fm-plan-preflight.sh rehearse <plan.md> --repo <path> [--base <ref>] [--evidence <path>]
#       Lint, then run every declared producer once in a fresh detached
#       worktree of the target clone at the resolved baseline, observe the
#       filesystem write-set of each run, and write the evidence sidecar
#       (default: <plan.md>.preflight.json next to the PLAN). A closure
#       failure still writes evidence (verdict "fail") so verify can report it.
#   fm-plan-preflight.sh verify <plan.md> [--repo <path>] [--evidence <path>]
#       Lint, then validate existing evidence: PLAN identity (plan_id,
#       contract_version, plan sha256), producer inventory, baseline freshness
#       against the recorded clone (or --repo), and closure recomputed from the
#       recorded write-set against the current contract. Executes nothing.
#   fm-plan-preflight.sh amend <plan.md> --producer <id> --add <path>... [--repo <path>] [--evidence <path>]
#       The mechanical producer-output amendment. Proves eligibility with two
#       identical clean reruns of the declared producer at the recorded
#       baseline, then rewrites the PLAN's contract segment (allowed_scope.paths
#       plus the producer's outputs) and its Amendments record, refreshes the
#       evidence sidecar, and prints the MR declaration text. Anything the
#       proof cannot establish is refused and stays a stop-and-return decision.
#   fm-plan-preflight.sh -h|--help
#       Print this header.
#
# Exit codes (uniform across commands):
#   0  PASS (gate pass / evidence written with verdict pass / verify pass /
#      amendment applied)
#   2  contract gate FAIL: segment present but not automation-ready (wrong
#      plan_status, automation_ready false, or nonzero decision/gap counts)
#   3  LEGACY: the PLAN has no plan-contract block. Explicit backward-compatible
#      result: a legacy PLAN is never linted, rehearsed, or labeled rehearsed.
#   4  malformed: usage error, unparseable or schema-invalid segment (including
#      the producer schema and its argv safety rules), malformed evidence, an
#      unsupported contract_version, or an --add path that needs no amendment
#   5  preflight failure: missing/failed/stale evidence, baseline drift, dirty
#      baseline, a failed isolation assertion, a failed or timed-out producer
#      run, a closure violation (undeclared write), or an ineligible amendment
#
# The producers schema (plan-contract contract_version 1 extension)
# ----------------------------------------------------------------
# An automation-ready PLAN whose execution runs deterministic generators
# declares them in the contract segment so the write-set can be rehearsed:
#
#   producers:
#     - id: openapi                 # [A-Za-z0-9_.-]+, unique across producers
#       argv:                       # block sequence, one element per "- " line;
#         - uv                      #   executed as an argv array, never through
#         - run                     #   a shell: no eval, no sh -c, no free-form
#         - python                  #   command text anywhere in this tool
#         - scripts/generate_openapi.py
#       outputs:                    # the producer's bounded committable
#         - docs/openapi.json       #   write-set: exact repo-relative paths or
#         - docs/openapi-by-path/** #   one trailing "/**" directory prefix whose
#                                   #   literal prefix names >= 2 path segments
#
# Rules enforced at lint (exit 4 on violation):
#   - outputs use the allowed_scope.paths plain-scalar grammar (no spaces,
#     quotes, flow characters, or wildcards other than one trailing "/**"),
#     must be repo-relative, and must not contain ".." segments (path escape).
#   - A "/**" output prefix must name at least two literal segments
#     (docs/openapi-by-path/** passes; docs/**, generated/**, or ** do not):
#     a broad generated/**-style exemption is forbidden.
#   - Every declared output must be covered by allowed_scope.paths, so the
#     pre-existing scope check stays valid and the two declarations cannot
#     drift apart silently; the amend command writes both sides mechanically.
#   - argv[0]'s basename must not be a shell, an evaluator, a destructive or
#     privilege tool, a network fetcher, a VCS binary (this tool owns all git
#     operations in the rehearsal worktree), or a session/lifecycle tool:
#       sh bash zsh dash ksh fish csh tcsh eval exec env nice chroot unshare
#       bwrap sandbox-exec sudo su doas rm rmdir dd mkfs fdisk mount umount
#       git curl wget ssh scp sftp rsync nc ncat socat telnet ftp kill pkill
#       killall tmux zellij screen herdr orca cmux nohup setsid at batch
#       crontab launchctl systemctl shutdown reboot halt poweroff
#     Producer declaration is captain-approved PLAN content; this denylist
#     stops destructive/lifecycle-shaped entries, it does not sandbox the
#     repo's own generator code.
#
# Rehearsal semantics
# -------------------
# - The rehearsal NEVER runs in the target checkout. The tool creates a fresh
#   detached worktree (`git worktree add --detach <tmp> <base_sha>`), proves
#   isolation (the worktree top-level is the new path and differs from the
#   target checkout, HEAD equals the baseline, the tree is clean), runs
#   producers there with stdin closed and a hard time bound
#   (FM_PLAN_PREFLIGHT_TIMEOUT seconds, default 900, via
#   bin/fm-timeout-lib.sh), and removes the worktree on every exit. A primary
#   checkout is unreachable by construction and any failed assertion fails
#   closed.
# - The baseline is `--base` or the clone's origin/HEAD (falling back to its
#   current branch, then HEAD). The target clone's own working tree must be
#   clean ("dirty baseline" fails closed): rehearsal semantics bind a committed
#   SHA, and a dirty clone signals a checkout tangle.
# - Write-set observation is filesystem-level, not git-level: every file under
#   the worktree (minus .git) is snapshotted (sha256, mtime, size) before and
#   after each producer run, and the per-producer observed write-set is the
#   added/deleted/modified delta with git-ignored paths filtered out. This is
#   what catches a deterministic generator that REWRITES a committed generated
#   directory with identical content - a git diff sees nothing, the snapshot
#   delta sees the rewrite. The honest bound: a producer that skips writes its
#   inputs make unnecessary can under-report its write-set at one baseline, so
#   declarations must cover the producer's possible write-set, and the
#   implementation-time scope check remains the second net.
# - Closure: every observed path of a producer must be covered by
#   allowed_scope.paths or that producer's declared outputs. Any uncovered path
#   is an UNDECLARED_WRITE and fails the rehearsal before dispatch.
#
# Evidence schema (preflight_version 1, JSON sidecar)
# ---------------------------------------------------
#   preflight_version: 1
#   plan_id, contract_version, plan_sha256      (PLAN identity binding)
#   repo: { path, base_ref, base_sha }          (target baseline binding)
#   rehearsed_at: <utc iso8601>
#   producers: [ { id, argv, declared_outputs, observed_writes,
#                  undeclared_writes, closure } ]
#   closure, verdict: pass | fail
#   amendments: [ { date, producer, added_outputs, plan_sha256_after,
#                   kind: "mechanical" } ]       (appended by amend)
#
# Mechanical amendment eligibility (all proven by `amend`, never judged)
# ---------------------------------------------------------------------
#   - the producer is declared in the approved PLAN's contract segment;
#   - each --add path passes the output grammar/breadth rules and is not
#     already covered (a covered path needs no amendment and is refused);
#   - two fresh clean worktrees at the evidence's recorded baseline run the
#     producer to an identical write-set with identical content (determinism);
#   - that write-set equals the dispatch evidence's recorded write-set, and
#     every --add pattern covers at least one path actually observed from that
#     producer (the new paths are that producer's deterministic generated
#     outputs, not handwritten, source, API, or product-semantic changes -
#     nothing but the declared producer ever runs in the rehearsal worktrees);
#   - applying the additions closes the rehearsal completely: no undeclared
#     write may remain for any producer.
# On pass, amend edits the PLAN (allowed_scope.paths, the producer's outputs,
# and an `Amendments:` line next to the contract block), re-lints the amended
# PLAN transactionally, refreshes the evidence, and prints the line the MR's
# PLAN Contract section must carry. The PLAN's Amendments line is the prose
# record; the evidence sidecar's amendments list is the machine authority.
# Any refusal leaves the PLAN untouched and the decision with the captain.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bin/fm-timeout-lib.sh
. "$SCRIPT_DIR/fm-timeout-lib.sh"

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

PRODUCER_TIMEOUT=${FM_PLAN_PREFLIGHT_TIMEOUT:-900}
case "$PRODUCER_TIMEOUT" in
  ''|*[!0-9]*) echo "error: FM_PLAN_PREFLIGHT_TIMEOUT must be a positive integer" >&2; exit 4 ;;
esac
[ "$PRODUCER_TIMEOUT" -gt 0 ] || { echo "error: FM_PLAN_PREFLIGHT_TIMEOUT must be > 0" >&2; exit 4; }

# argv[0] basenames that no declared producer may use (see the header rules).
ARGV0_DENYLIST=" sh bash zsh dash ksh fish csh tcsh eval exec env nice chroot unshare bwrap sandbox-exec sudo su doas rm rmdir dd mkfs fdisk mount umount git curl wget ssh scp sftp rsync nc ncat socat telnet ftp kill pkill killall tmux zellij screen herdr orca cmux nohup setsid at batch crontab launchctl systemctl shutdown reboot halt poweroff "

TAB=$(printf '\t')

err() {
  printf 'error: %s\n' "$*" >&2
}

# --- path resolution -----------------------------------------------------------

# resolve_read_file <name> <path>: absolute physical path of an existing file.
resolve_read_file() {
  local name=$1 path=$2 dir base resolved
  case "$path" in
    */*) dir=${path%/*}; base=${path##*/} ;;
    *) dir=.; base=$path ;;
  esac
  resolved=$(CDPATH='' cd -- "$dir" 2>/dev/null && pwd -P) || {
    err "$name directory cannot be resolved: $dir"
    return 4
  }
  if [ -z "$base" ] || [ ! -f "$resolved/$base" ]; then
    err "$name not found: $resolved/$base"
    return 4
  fi
  printf '%s/%s\n' "$resolved" "$base"
}

# resolve_dir <name> <path>: absolute physical path of an existing directory.
resolve_dir() {
  local name=$1 path=$2 resolved
  resolved=$(CDPATH='' cd -- "$path" 2>/dev/null && pwd -P) || {
    err "$name directory cannot be resolved: $path"
    return 4
  }
  printf '%s\n' "$resolved"
}

# resolve_write_file <name> <path>: absolute physical path whose parent exists.
resolve_write_file() {
  local name=$1 path=$2 dir base resolved
  case "$path" in
    */*) dir=${path%/*}; base=${path##*/} ;;
    *) dir=.; base=$path ;;
  esac
  resolved=$(CDPATH='' cd -- "$dir" 2>/dev/null && pwd -P) || {
    err "$name parent directory cannot be resolved: $dir"
    return 4
  }
  [ -n "$base" ] || { err "$name needs a file name: $path"; return 4; }
  printf '%s/%s\n' "$resolved" "$base"
}

# --- plan-contract parser ------------------------------------------------------
# This awk owns the machine-readable subset of the segment: top-level scalar
# keys, the open_decisions counts, allowed_scope paths/exempt_additions,
# invariants and proof_obligations ID lists, and the producers block. Unknown
# top-level keys are ignored for forward compatibility; anything else outside
# the grammar dies loudly (exit 4). Emits validated scalars as key=value lines,
# then marker-delimited lists (tab-joined so values need no escaping; the
# segment itself is already tab-free).

parse_contract() {  # <plan-file> ; normalized stream on stdout
  local plan=$1
  if ! grep -q '^```plan-contract[ \t]*$' "$plan"; then
    return 3
  fi
  awk '
    function die(msg) { print "error: contract segment: " msg > "/dev/stderr"; died = 1; exit 4 }
    function indent_of(s,   n) { n = 0; while (substr(s, n + 1, 1) == " ") n++; return n }
    function check_id(v, what) { if (v !~ /^[A-Za-z0-9_.-]+$/) die(what " must match [A-Za-z0-9_.-]+: " v) }
    BEGIN {
      TAB = sprintf("%c", 9)
      fences = 0; inblock = 0
      np = 0; ne = 0; ni = 0; npm = 0; nprod = 0
    }
    /^```plan-contract[ \t]*$/ { fences++; if (fences > 1) die("multiple plan-contract blocks"); inblock = 1; next }
    inblock && /^```[ \t]*$/ { inblock = 0; section = ""; next }
    !inblock { next }
    /\t/ { die("tab character is not allowed in the machine-readable segment") }
    /^[ \t]*#/ { next }
    /^[ \t]*$/ { next }
    {
      ind = indent_of($0)
      line = substr($0, ind + 1)
      if (ind == 0) {
        subsection = ""
        if (line !~ /^[A-Za-z_][A-Za-z0-9_]*:([ ]|$)/) die("top-level line is not a key: " line)
        key = line; sub(/:.*/, "", key)
        val = line; sub(/^[^:]*:[ ]*/, "", val); sub(/[ ]*$/, "", val)
        section = ""
        if (key == "contract_version") { if (val !~ /^[0-9]+$/) die("contract_version must be an integer"); cv = val }
        else if (key == "plan_id") { check_id(val, "plan_id"); pid = val }
        else if (key == "plan_status") { if (val !~ /^(draft|decision-ready|approved|blocked|decision-pending)$/) die("plan_status not in vocabulary: " val); ps = val }
        else if (key == "automation_ready") { if (val != "true" && val != "false") die("automation_ready must be true or false"); ar = val }
        else if (key == "planning_critical_evidence_gaps") { if (val !~ /^[0-9]+$/) die("planning_critical_evidence_gaps must be an integer"); pceg = val }
        else if (key == "open_decisions") { if (val != "") die("open_decisions must be a block mapping"); section = "od" }
        else if (key == "allowed_scope") { if (val != "") die("allowed_scope must be a block mapping"); section = "scope" }
        else if (key == "invariants") { if (val != "") die("invariants must be a block sequence of IDs"); section = "inv" }
        else if (key == "proof_obligations") { if (val != "") die("proof_obligations must be a block mapping of gate -> ID list"); section = "po" }
        else if (key == "producers") { if (val != "") die("producers must be a block sequence"); section = "prod" }
        next
      }
      if (section == "od" && ind == 2) {
        if (line !~ /^[A-Za-z_][A-Za-z0-9_]*:/) die("open_decisions: unexpected line: " line)
        name = line; sub(/:.*/, "", name)
        v = line; sub(/^[^:]*:[ ]*/, "", v); sub(/[ ]*$/, "", v)
        if (name ~ /^(product|scope|architecture|acceptance_semantics)$/) {
          if (v !~ /^[0-9]+$/) die("open_decisions." name " must be an integer")
          od[name] = v
        }
        next
      }
      if (section == "scope" && ind == 2) {
        subsection = ""
        if (line == "paths:") { subsection = "paths"; next }
        if (line == "exempt_additions:") { subsection = "exempt"; next }
        if (line ~ /^[A-Za-z_][A-Za-z0-9_]*:([ ]|$)/) next
        die("allowed_scope: unexpected line: " line)
      }
      if (section == "scope" && subsection == "paths" && ind == 4) {
        if (line !~ /^- /) die("paths entries must be list items: " line)
        p = substr(line, 3)
        if (p == "") die("empty paths entry")
        if (p ~ /[ \t]/ || index(p, "\"") || index(p, "\047") || index(p, "[") || index(p, "]") || index(p, "{") || index(p, "}") || index(p, "|") || index(p, ">")) die("paths entries must be plain scalars: " p)
        if (p ~ /\*/) {
          n = gsub(/\*/, "*", p)
          if (p !~ /\/\*\*$/ || n != 2) die("only a single trailing /** wildcard is supported: " p)
        }
        paths[++np] = p
        next
      }
      if (section == "scope" && subsection == "exempt" && ind == 4) {
        if (line !~ /^- /) die("exempt_additions entries must be list items: " line)
        e = substr(line, 3)
        if (e !~ /^(test-fixture|generated|helper)$/) die("exempt_additions category outside closed vocabulary (test-fixture|generated|helper): " e)
        exempts[++ne] = e
        next
      }
      if (section == "inv" && ind == 2) {
        if (line !~ /^- /) die("invariants entries must be list items: " line)
        i = substr(line, 3)
        check_id(i, "invariant ID")
        invs[++ni] = i
        next
      }
      if (section == "po" && ind == 2) {
        subsection = ""
        if (line ~ /^[A-Za-z_][A-Za-z0-9_]*:[ ]*$/) { subsection = line; sub(/:.*/, "", subsection); next }
        die("proof_obligations: gate key is not a plain key: " line)
      }
      if (section == "po" && ind == 4 && subsection != "") {
        if (line !~ /^- /) die("proof_obligations entries must be list items: " line)
        po = substr(line, 3)
        check_id(po, "PO ID")
        if (subsection == "merge") pom[++npm] = po
        next
      }
      if (section == "prod" && ind == 2) {
        subsection = ""
        if (line ~ /^- id: /) {
          v = substr(line, 7)
          check_id(v, "producer id")
          for (i = 1; i <= nprod; i++) if (prod_id[i] == v) die("duplicate producer id: " v)
          nprod++
          prod_id[nprod] = v
          prod_argc[nprod] = 0
          prod_nout[nprod] = 0
          prod_have_argv[nprod] = 0
          prod_have_outputs[nprod] = 0
          next
        }
        die("producers entries must open with \"- id: <id>\": " line)
      }
      if (section == "prod" && ind == 4) {
        if (line == "argv:") { subsection = "argv"; prod_have_argv[nprod] = 1; next }
        if (line == "outputs:") { subsection = "outputs"; prod_have_outputs[nprod] = 1; next }
        die("producers: unknown key (only argv: and outputs:): " line)
      }
      if (section == "prod" && ind == 6 && subsection == "argv") {
        if (line !~ /^- /) die("argv entries must be list items: " line)
        e = substr(line, 3)
        if (e == "") die("empty argv element")
        if (e ~ /^[ ]/ || e ~ /[ ]$/) die("argv elements must not carry outer whitespace: " e)
        prod_argc[nprod]++
        prod_argv[nprod, prod_argc[nprod]] = e
        next
      }
      if (section == "prod" && ind == 6 && subsection == "outputs") {
        if (line !~ /^- /) die("outputs entries must be list items: " line)
        o = substr(line, 3)
        if (o == "") die("empty outputs entry")
        prod_nout[nprod]++
        prod_out[nprod, prod_nout[nprod]] = o
        next
      }
      if (section != "") die("unexpected nesting at: " line)
      next
    }
    END {
      if (died) exit 4
      if (inblock) die("unterminated plan-contract block")
      if (cv == "") die("missing contract_version")
      if (cv != "1") die("unsupported contract_version " cv " (this tool speaks contract_version 1)")
      if (pid == "") die("missing plan_id")
      if (ps == "") die("missing plan_status")
      if (ar == "") die("missing automation_ready")
      if (pceg == "") die("missing planning_critical_evidence_gaps")
      want["product"]; want["scope"]; want["architecture"]; want["acceptance_semantics"]
      for (k in want) if (!(k in od)) die("missing open_decisions." k)
      if (np == 0) die("allowed_scope.paths is empty or missing")
      if (ni == 0) die("invariants ID list is empty or missing")
      if (npm == 0) die("proof_obligations.merge ID list is empty or missing")
      for (i = 1; i <= nprod; i++) {
        if (!prod_have_argv[i] || prod_argc[i] == 0) die("producer " prod_id[i] " declares no argv")
        if (!prod_have_outputs[i] || prod_nout[i] == 0) die("producer " prod_id[i] " declares no outputs")
      }
      print "cv=" cv
      print "plan_id=" pid
      print "plan_status=" ps
      print "ar=" ar
      print "pceg=" pceg
      print "od_product=" od["product"]
      print "od_scope=" od["scope"]
      print "od_architecture=" od["architecture"]
      print "od_acceptance=" od["acceptance_semantics"]
      print "---PATHS---"
      for (i = 1; i <= np; i++) print paths[i]
      print "---EXEMPTS---"
      for (i = 1; i <= ne; i++) print exempts[i]
      print "---INVARIANTS---"
      for (i = 1; i <= ni; i++) print invs[i]
      print "---PO_MERGE---"
      for (i = 1; i <= npm; i++) print pom[i]
      print "---PRODUCERS---"
      for (i = 1; i <= nprod; i++) {
        print "PRODUCER" TAB prod_id[i]
        for (j = 1; j <= prod_argc[i]; j++) print "ARGV" TAB prod_argv[i, j]
        for (j = 1; j <= prod_nout[i]; j++) print "OUTPUT" TAB prod_out[i, j]
        print "ENDPRODUCER"
      }
    }
  ' "$plan"
}

# Contract globals populated by read_contract_stream.
reset_contract_globals() {
  CV=; PLAN_ID=; PLAN_STATUS=; AR=; PCEG=
  OD_PRODUCT=0; OD_SCOPE=0; OD_ARCH=0; OD_ACC=0
  NP=0; NPROD=0
  PATHS=()
  PROD_ID=(); PROD_ARGV=(); PROD_OUT=()
}
reset_contract_globals

read_contract_stream() {  # <stream-file>
  # The awk pass already validated and counted the exempt/ID lists; the bash
  # side needs only paths and producers, so those lines are consumed, not kept.
  local line mode value cur
  mode=scalars
  cur=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ---PATHS---) mode=paths; continue ;;
      ---EXEMPTS---) mode=exempts; continue ;;
      ---INVARIANTS---) mode=invs; continue ;;
      ---PO_MERGE---) mode=pom; continue ;;
      ---PRODUCERS---) mode=prods; continue ;;
    esac
    case "$mode" in
      paths) NP=$((NP + 1)); PATHS[NP]=$line; continue ;;
      exempts|invs|pom) continue ;;
      prods)
        case "$line" in
          PRODUCER"$TAB"*)
            NPROD=$((NPROD + 1)); cur=$NPROD
            PROD_ID[cur]=${line#PRODUCER"$TAB"}
            PROD_ARGV[cur]=
            PROD_OUT[cur]=
            continue
            ;;
          ARGV"$TAB"*)
            value=${line#ARGV"$TAB"}
            PROD_ARGV[cur]=${PROD_ARGV[cur]:+${PROD_ARGV[cur]}$'\n'}$value
            continue
            ;;
          OUTPUT"$TAB"*)
            value=${line#OUTPUT"$TAB"}
            PROD_OUT[cur]=${PROD_OUT[cur]:+${PROD_OUT[cur]}$'\n'}$value
            continue
            ;;
          ENDPRODUCER) cur=0; continue ;;
          *) err "internal parser output unexpected: $line"; return 4 ;;
        esac
        ;;
    esac
    case "$line" in
      cv=*) CV=${line#cv=} ;;
      plan_id=*) PLAN_ID=${line#plan_id=} ;;
      plan_status=*) PLAN_STATUS=${line#plan_status=} ;;
      ar=*) AR=${line#ar=} ;;
      pceg=*) PCEG=${line#pceg=} ;;
      od_product=*) OD_PRODUCT=${line#od_product=} ;;
      od_scope=*) OD_SCOPE=${line#od_scope=} ;;
      od_architecture=*) OD_ARCH=${line#od_architecture=} ;;
      od_acceptance=*) OD_ACC=${line#od_acceptance=} ;;
      *) err "internal parser output unexpected: $line"; return 4 ;;
    esac
  done < "$1"
}

# lint_plan <plan-abs>: parse, populate globals, evaluate gate + producer rules.
# Returns 0 pass, 2 gate fail, 3 legacy, 4 malformed; prints the LINT line.
lint_plan() {
  local plan=$1 stream rc
  reset_contract_globals
  stream=$(mktemp "${TMPDIR:-/tmp}/fm-plan-preflight-stream.XXXXXX") || return 4
  set +e
  parse_contract "$plan" > "$stream"
  rc=$?
  set -e
  if [ "$rc" -eq 3 ]; then
    rm -f "$stream"
    printf 'LINT: LEGACY no plan-contract block found (prose-only PLAN; never rehearsal-gated, never labeled rehearsed)\n'
    return 3
  fi
  if [ "$rc" -ne 0 ]; then
    rm -f "$stream"
    return 4
  fi
  read_contract_stream "$stream" || { rm -f "$stream"; return 4; }
  rm -f "$stream"

  local why total
  why=
  if [ "$AR" != "true" ]; then why="automation_ready=$AR"; fi
  if [ "$PLAN_STATUS" != "approved" ]; then why="${why:+$why; }plan_status=$PLAN_STATUS"; fi
  total=$((OD_PRODUCT + OD_SCOPE + OD_ARCH + OD_ACC + PCEG))
  if [ "$total" -ne 0 ]; then
    why="${why:+$why; }nonzero counts: product=$OD_PRODUCT scope=$OD_SCOPE architecture=$OD_ARCH acceptance_semantics=$OD_ACC planning_critical_evidence_gaps=$PCEG"
  fi
  if [ -n "$why" ]; then
    printf 'LINT: FAIL %s\n' "$why"
    return 2
  fi
  validate_producers || return 4
  printf 'LINT: PASS plan_id=%s contract_version=%s producers=%s allowed_paths=%s\n' "$PLAN_ID" "$CV" "$NPROD" "$NP"
  return 0
}

# --- producer schema validation ------------------------------------------------

# validate_output_entry <pattern>: grammar, escape, and breadth rules.
validate_output_entry() {
  local p=$1 stars pref
  case "$p" in
    ''|/*|*' '*|*"$TAB"*|*\"*|*"'"*|*'['*|*']'*|*'{'*|*'}'*|*'|'*|*'>'*)
      err "producer output must be a non-empty repo-relative plain scalar: $p"
      return 4 ;;
  esac
  case "/$p/" in
    */../*)
      err "producer output must not contain '..' segments (path escape): $p"
      return 4 ;;
  esac
  case "$p" in
    *'*'*)
      case "$p" in
        */\*\*) : ;;
        *) err "producer output supports only a single trailing /** wildcard: $p"; return 4 ;;
      esac
      stars=${p//[^*]/}
      if [ "${#stars}" -ne 2 ]; then
        err "producer output supports only a single trailing /** wildcard: $p"
        return 4
      fi
      pref=${p%/\*\*}
      case "$pref" in
        */*) : ;;
        *)
          err "producer output wildcard prefix must name at least two path segments (a broad generated/**-style exemption is forbidden): $p"
          return 4 ;;
      esac
      ;;
  esac
  return 0
}

# pattern_covers <covering-entry> <candidate>: an exact entry covers only
# itself; a trailing-/** entry covers anything under (or equal to) its prefix,
# including a narrower /** candidate.
pattern_covers() {
  local cover=$1 cand=$2 pref
  case "$cover" in
    */\*\*)
      pref=${cover%/\*\*}
      case "$cand" in
        "$pref"/*|"$pref") return 0 ;;
      esac
      ;;
    *)
      [ "$cand" = "$cover" ] && return 0
      ;;
  esac
  return 1
}

# covered_by_paths <pattern>: candidate covered by any allowed_scope path.
covered_by_paths() {
  local cand=$1 i
  i=1
  while [ "$i" -le "$NP" ]; do
    if pattern_covers "${PATHS[$i]}" "$cand"; then
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# covered_by_outputs <newline-joined outputs> <candidate>
covered_by_outputs() {
  local outputs=$1 cand=$2 entry
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if pattern_covers "$entry" "$cand"; then
      return 0
    fi
  done <<EOF
$outputs
EOF
  return 1
}

# newline_list_contains <newline-joined list> <entry>: exact line membership.
newline_list_contains() {
  printf '%s\n' "$1" | grep -qxF -- "$2"
}

# validate_producers: argv safety, output grammar/breadth, duplicate outputs,
# and the outputs-must-be-covered-by-allowed-paths rule.
validate_producers() {
  local i a0 base0 entry seen
  i=1
  seen=
  while [ "$i" -le "$NPROD" ]; do
    a0=${PROD_ARGV[$i]%%$'\n'*}
    base0=${a0##*/}
    case "$ARGV0_DENYLIST" in
      *" $base0 "*)
        err "producer ${PROD_ID[$i]}: argv[0] '$base0' is a shell, destructive, network, VCS, or lifecycle-shaped command and may not run in a rehearsal"
        return 4 ;;
    esac
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      validate_output_entry "$entry" || return 4
      if newline_list_contains "$seen" "$entry"; then
        err "duplicate producer output declaration: $entry"
        return 4
      fi
      seen="${seen}${seen:+$'\n'}${entry}"
      if ! covered_by_paths "$entry"; then
        err "producer ${PROD_ID[$i]} output is not covered by allowed_scope.paths (declare it in both; the amend command writes both sides): $entry"
        return 4
      fi
    done <<EOF
${PROD_OUT[$i]}
EOF
    i=$((i + 1))
  done
  return 0
}

# --- filesystem observation ----------------------------------------------------

require_python3() {
  command -v python3 >/dev/null 2>&1 || {
    err "python3 is required for rehearsal evidence (snapshot hashing and JSON)"
    return 4
  }
}

# snapshot_tree <root> <out>: TSV of relpath, kind(F|L), sha256, mtime_ns, size
# for every file under root except .git. Rewrites with identical content still
# change mtime, which is exactly what a deterministic generator's write-set
# needs to surface.
snapshot_tree() {
  python3 - "$1" "$2" <<'PY'
import hashlib, os, sys

root, out = sys.argv[1], sys.argv[2]
rows = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = sorted(d for d in dirnames if d != ".git")
    for name in sorted(filenames):
        p = os.path.join(dirpath, name)
        rel = os.path.relpath(p, root)
        if "\t" in rel or "\n" in rel:
            print("error: path contains a tab or newline: %r" % rel, file=sys.stderr)
            sys.exit(3)
        try:
            st = os.lstat(p)
        except OSError:
            continue
        if os.path.islink(p):
            try:
                target = os.readlink(p)
            except OSError:
                continue
            rows.append((rel, "L", hashlib.sha256(target.encode()).hexdigest(), 0, 0))
            continue
        if not os.path.isfile(p):
            continue
        h = hashlib.sha256()
        try:
            with open(p, "rb") as fh:
                for chunk in iter(lambda: fh.read(65536), b""):
                    h.update(chunk)
        except OSError:
            continue
        rows.append((rel, "F", h.hexdigest(), st.st_mtime_ns, st.st_size))
rows.sort()
with open(out, "w") as fh:
    for rel, kind, digest, mtime, size in rows:
        fh.write("%s\t%s\t%s\t%s\t%s\n" % (rel, kind, digest, mtime, size))
PY
}

# diff_snapshots <before> <after> <out>: "<path>\t<added|deleted|modified>"
# lines for every path whose record differs, content hash included.
diff_snapshots() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys

def load(p):
    d = {}
    with open(p) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 5:
                d[parts[0]] = tuple(parts[1:])
    return d

before = load(sys.argv[1])
after = load(sys.argv[2])
rows = []
for path in sorted(set(before) | set(after)):
    b = before.get(path)
    a = after.get(path)
    if b is None:
        rows.append((path, "added"))
    elif a is None:
        rows.append((path, "deleted"))
    elif b != a:
        rows.append((path, "modified"))
with open(sys.argv[3], "w") as fh:
    for path, kind in rows:
        fh.write("%s\t%s\n" % (path, kind))
PY
}

# filter_ignored <worktree> <in> <out>: drop git-ignored paths from a
# path/kind TSV so tool churn (caches, virtualenvs) is not a write-set signal.
filter_ignored() {
  local wt=$1 in=$2 out=$3 ignored path kind
  : > "$out"
  [ -s "$in" ] || return 0
  ignored=$(cut -f1 "$in" | git -C "$wt" check-ignore --stdin 2>/dev/null || true)
  while IFS="$TAB" read -r path kind; do
    [ -n "$path" ] || continue
    if [ -n "$ignored" ] && newline_list_contains "$ignored" "$path"; then
      continue
    fi
    printf '%s\t%s\n' "$path" "$kind" >> "$out"
  done < "$in"
}

# --- evidence IO -----------------------------------------------------------------

# write_evidence <bundle> <out>: build the JSON sidecar from a tab-joined
# bundle (see the header schema). Fails loudly on unknown keys.
write_evidence() {
  python3 - "$1" "$2" <<'PY'
import json, sys

bundle, out = sys.argv[1], sys.argv[2]
doc = {"preflight_version": 1, "producers": [], "amendments": []}
repo = {}
cur = None
def bad(msg):
    print("error: internal evidence bundle: %s" % msg, file=sys.stderr)
    sys.exit(4)
with open(bundle) as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if not line:
            continue
        fields = line.split("\t")
        key = fields[0]
        if key == "PRODUCER":
            if len(fields) != 2: bad("PRODUCER needs one id")
            cur = {"id": fields[1], "argv": [], "declared_outputs": [],
                   "observed_writes": [], "undeclared_writes": [], "closure": "pass"}
            doc["producers"].append(cur)
        elif key == "ARGV":
            if cur is None: bad("ARGV outside producer")
            cur["argv"] = fields[1:]
        elif key == "OUTPUT":
            if cur is None: bad("OUTPUT outside producer")
            cur["declared_outputs"].append(fields[1])
        elif key == "OBSERVED":
            if cur is None: bad("OBSERVED outside producer")
            cur["observed_writes"].append(fields[1])
        elif key == "UNDECLARED":
            if cur is None: bad("UNDECLARED outside producer")
            cur["undeclared_writes"].append(fields[1])
        elif key == "PCLOSURE":
            if cur is None: bad("PCLOSURE outside producer")
            cur["closure"] = fields[1]
        elif key == "ENDPRODUCER":
            cur = None
        elif key == "AMENDMENT":
            if len(fields) < 5: bad("AMENDMENT needs date, producer, sha, outputs")
            doc["amendments"].append({"date": fields[1], "producer": fields[2],
                                      "plan_sha256_after": fields[3],
                                      "added_outputs": fields[4:], "kind": "mechanical"})
        elif key == "PLAN_ID": doc["plan_id"] = fields[1]
        elif key == "CONTRACT_VERSION": doc["contract_version"] = int(fields[1])
        elif key == "PLAN_SHA256": doc["plan_sha256"] = fields[1]
        elif key == "REPO_PATH": repo["path"] = fields[1]
        elif key == "BASE_REF": repo["base_ref"] = fields[1]
        elif key == "BASE_SHA": repo["base_sha"] = fields[1]
        elif key == "REHEARSED_AT": doc["rehearsed_at"] = fields[1]
        elif key == "VERDICT": doc["verdict"] = fields[1]
        elif key == "CLOSURE": doc["closure"] = fields[1]
        else:
            bad("unknown key %s" % key)
doc["repo"] = repo
with open(out, "w") as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
}

# read_evidence <json> <bundle-out>: validate the sidecar schema and emit the
# bundle form for bash consumption. Malformed anything exits 4.
read_evidence() {
  python3 - "$1" "$2" <<'PY'
import json, sys

src, out = sys.argv[1], sys.argv[2]
def bad(msg):
    print("error: malformed evidence %s: %s" % (src, msg), file=sys.stderr)
    sys.exit(4)
try:
    with open(src) as fh:
        doc = json.load(fh)
except (OSError, ValueError) as e:
    bad(str(e))
if not isinstance(doc, dict):
    bad("top level must be an object")
if doc.get("preflight_version") != 1:
    bad("preflight_version must be 1")
def req_str(d, k):
    v = d.get(k)
    if not isinstance(v, str) or "\t" in v or "\n" in v:
        bad("%s must be a tab/newline-free string" % k)
    return v
plan_id = req_str(doc, "plan_id")
cv = doc.get("contract_version")
if not isinstance(cv, int):
    bad("contract_version must be an integer")
plan_sha = req_str(doc, "plan_sha256")
repo = doc.get("repo")
if not isinstance(repo, dict):
    bad("repo must be an object")
repo_path = req_str(repo, "path")
base_ref = req_str(repo, "base_ref")
base_sha = req_str(repo, "base_sha")
rehearsed_at = req_str(doc, "rehearsed_at")
verdict = doc.get("verdict")
closure = doc.get("closure")
if verdict not in ("pass", "fail"):
    bad("verdict must be pass|fail")
if closure not in ("pass", "fail"):
    bad("closure must be pass|fail")
producers = doc.get("producers")
if not isinstance(producers, list):
    bad("producers must be a list")
seen = set()
lines = []
def str_list(p, k):
    v = p.get(k)
    if not isinstance(v, list) or any(not isinstance(x, str) or "\t" in x or "\n" in x for x in v):
        bad("producer %s must be a list of tab/newline-free strings" % k)
    return v
for p in producers:
    if not isinstance(p, dict):
        bad("each producer must be an object")
    pid = req_str(p, "id")
    if pid in seen:
        bad("duplicate producer id: %s" % pid)
    seen.add(pid)
    pc = p.get("closure")
    if pc not in ("pass", "fail"):
        bad("producer closure must be pass|fail")
    lines.append("PRODUCER\t%s" % pid)
    argv = str_list(p, "argv")
    if not argv:
        bad("producer %s has an empty argv" % pid)
    lines.append("ARGV" + "".join("\t%s" % x for x in argv))
    for x in str_list(p, "declared_outputs"):
        lines.append("OUTPUT\t%s" % x)
    for x in str_list(p, "observed_writes"):
        lines.append("OBSERVED\t%s" % x)
    for x in str_list(p, "undeclared_writes"):
        lines.append("UNDECLARED\t%s" % x)
    lines.append("PCLOSURE\t%s" % pc)
    lines.append("ENDPRODUCER")
amendments = doc.get("amendments")
if amendments is None:
    amendments = []
if not isinstance(amendments, list):
    bad("amendments must be a list")
for a in amendments:
    if not isinstance(a, dict):
        bad("each amendment must be an object")
    date = req_str(a, "date")
    prod = req_str(a, "producer")
    sha = req_str(a, "plan_sha256_after")
    kind = req_str(a, "kind")
    if kind != "mechanical":
        bad("amendment kind must be mechanical")
    adds = str_list(a, "added_outputs")
    if not adds:
        bad("amendment added_outputs must not be empty")
    lines.append("\t".join(["AMENDMENT", date, prod, sha] + adds))
lines.append("PLAN_ID\t%s" % plan_id)
lines.append("CONTRACT_VERSION\t%s" % cv)
lines.append("PLAN_SHA256\t%s" % plan_sha)
lines.append("REPO_PATH\t%s" % repo_path)
lines.append("BASE_REF\t%s" % base_ref)
lines.append("BASE_SHA\t%s" % base_sha)
lines.append("REHEARSED_AT\t%s" % rehearsed_at)
lines.append("VERDICT\t%s" % verdict)
lines.append("CLOSURE\t%s" % closure)
with open(out, "w") as fh:
    fh.write("\n".join(lines) + "\n")
PY
}

# Evidence globals populated by read_evidence_bundle.
reset_evidence_globals() {
  EV_PLAN_ID=; EV_CV=; EV_PLAN_SHA=; EV_REPO_PATH=; EV_BASE_REF=; EV_BASE_SHA=
  EV_REHEARSED_AT=; EV_VERDICT=; EV_CLOSURE=
  EV_NPROD=0
  EV_PROD_ID=(); EV_PROD_ARGV=(); EV_PROD_OUT=(); EV_PROD_OBSERVED=(); EV_PROD_UNDECLARED=()
  EV_NAMEND=0
  EV_AMEND=()
}
reset_evidence_globals

read_evidence_bundle() {  # <bundle-file>
  local line cur
  cur=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      PRODUCER"$TAB"*)
        EV_NPROD=$((EV_NPROD + 1)); cur=$EV_NPROD
        EV_PROD_ID[cur]=${line#PRODUCER"$TAB"}
        EV_PROD_ARGV[cur]=
        EV_PROD_OUT[cur]=
        EV_PROD_OBSERVED[cur]=
        EV_PROD_UNDECLARED[cur]=
        continue
        ;;
      ARGV"$TAB"*) EV_PROD_ARGV[cur]=${line#ARGV"$TAB"}; continue ;;
      OUTPUT"$TAB"*)
        EV_PROD_OUT[cur]=${EV_PROD_OUT[cur]:+${EV_PROD_OUT[cur]}$'\n'}${line#OUTPUT"$TAB"}
        continue
        ;;
      OBSERVED"$TAB"*)
        EV_PROD_OBSERVED[cur]=${EV_PROD_OBSERVED[cur]:+${EV_PROD_OBSERVED[cur]}$'\n'}${line#OBSERVED"$TAB"}
        continue
        ;;
      UNDECLARED"$TAB"*)
        EV_PROD_UNDECLARED[cur]=${EV_PROD_UNDECLARED[cur]:+${EV_PROD_UNDECLARED[cur]}$'\n'}${line#UNDECLARED"$TAB"}
        continue
        ;;
      # The recorded per-producer closure flag is never trusted: verify and
      # amend recompute closure from the recorded write-set instead.
      PCLOSURE"$TAB"*) continue ;;
      ENDPRODUCER) cur=0; continue ;;
      AMENDMENT"$TAB"*)
        EV_NAMEND=$((EV_NAMEND + 1))
        EV_AMEND[EV_NAMEND]=$line
        continue
        ;;
      PLAN_ID"$TAB"*) EV_PLAN_ID=${line#PLAN_ID"$TAB"}; continue ;;
      CONTRACT_VERSION"$TAB"*) EV_CV=${line#CONTRACT_VERSION"$TAB"}; continue ;;
      PLAN_SHA256"$TAB"*) EV_PLAN_SHA=${line#PLAN_SHA256"$TAB"}; continue ;;
      REPO_PATH"$TAB"*) EV_REPO_PATH=${line#REPO_PATH"$TAB"}; continue ;;
      BASE_REF"$TAB"*) EV_BASE_REF=${line#BASE_REF"$TAB"}; continue ;;
      BASE_SHA"$TAB"*) EV_BASE_SHA=${line#BASE_SHA"$TAB"}; continue ;;
      REHEARSED_AT"$TAB"*) EV_REHEARSED_AT=${line#REHEARSED_AT"$TAB"}; continue ;;
      VERDICT"$TAB"*) EV_VERDICT=${line#VERDICT"$TAB"}; continue ;;
      CLOSURE"$TAB"*) EV_CLOSURE=${line#CLOSURE"$TAB"}; continue ;;
      *) err "internal evidence bundle unexpected: $line"; return 4 ;;
    esac
  done < "$1"
  return 0
}

plan_sha256() {
  python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}

# producer_index <id>: print the 1-based contract index of a producer id.
producer_index() {
  local want=$1 i
  i=1
  while [ "$i" -le "$NPROD" ]; do
    if [ "${PROD_ID[$i]}" = "$want" ]; then
      printf '%s\n' "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

ev_producer_index() {
  local want=$1 i
  i=1
  while [ "$i" -le "$EV_NPROD" ]; do
    if [ "${EV_PROD_ID[$i]}" = "$want" ]; then
      printf '%s\n' "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# --- git/baseline helpers --------------------------------------------------------

resolve_repo() {  # <path> -> physical abs path of a non-bare git work tree
  local repo
  repo=$(resolve_dir "--repo" "$1") || return 4
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
    err "--repo is not a git repository: $repo"
    return 4
  }
  if [ "$(git -C "$repo" rev-parse --is-bare-repository)" = "true" ]; then
    err "--repo must be a non-bare clone: $repo"
    return 4
  fi
  printf '%s\n' "$repo"
}

resolve_base() {  # <repo> <explicit-ref-or-empty> ; prints "<ref>\t<sha>"
  local repo=$1 ref=$2 sha
  if [ -z "$ref" ]; then
    ref=$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -z "$ref" ]; then
      ref=$(git -C "$repo" branch --show-current 2>/dev/null || true)
    fi
    if [ -z "$ref" ]; then
      ref=HEAD
    fi
  fi
  sha=$(git -C "$repo" rev-parse --verify --quiet "$ref^{commit}") || {
    err "baseline ref does not resolve to a commit: $ref"
    return 4
  }
  printf '%s%s%s\n' "$ref" "$TAB" "$sha"
}

assert_clean_clone() {  # <repo> ; the dirty-baseline refusal
  local repo=$1
  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
    err "dirty baseline: $repo has uncommitted changes or untracked files; rehearsal binds a committed SHA and refuses a dirty clone"
    return 5
  fi
  return 0
}

# make_rehearsal_worktree <repo> <sha> <wt>: create + prove the isolation
# assertions. Failure anywhere is an isolation failure (exit 5 class).
make_rehearsal_worktree() {
  local repo=$1 sha=$2 wt=$3 wt_top repo_top head
  if ! git -C "$repo" worktree add --detach "$wt" "$sha" >/dev/null 2>&1; then
    err "could not create the rehearsal worktree at $sha"
    return 5
  fi
  wt_top=$(CDPATH='' cd -- "$wt" 2>/dev/null && pwd -P) || {
    err "rehearsal worktree did not materialize: $wt"
    return 5
  }
  repo_top=$(CDPATH='' cd -- "$repo" 2>/dev/null && pwd -P) || {
    err "repo top-level vanished: $repo"
    return 5
  }
  if [ "$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null)" != "$wt_top" ]; then
    err "isolation assertion failed: $wt is not its own worktree top-level"
    return 5
  fi
  if [ "$wt_top" = "$repo_top" ]; then
    err "isolation assertion failed: rehearsal path resolves to the target checkout itself"
    return 5
  fi
  head=$(git -C "$wt" rev-parse HEAD 2>/dev/null) || {
    err "isolation assertion failed: rehearsal worktree has no HEAD"
    return 5
  }
  if [ "$head" != "$sha" ]; then
    err "isolation assertion failed: rehearsal HEAD $head != baseline $sha"
    return 5
  fi
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    err "isolation assertion failed: fresh rehearsal worktree is not clean"
    return 5
  fi
  return 0
}

remove_rehearsal_worktree() {  # <repo> <wt>
  local repo=$1 wt=$2
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || true
  git -C "$repo" worktree prune >/dev/null 2>&1 || true
}

# run_producer_argv <wt> <log> <newline-joined elements>
# Executes the argv array with stdin closed and a hard time bound. The argv
# text is never evaluated: elements pass through as literal array words.
run_producer_argv() {
  local wt=$1 log=$2 elements=$3 e rc
  local -a argv=()
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    argv+=("$e")
  done <<EOF
$elements
EOF
  [ "${#argv[@]}" -gt 0 ] || {
    err "producer argv is empty"
    return 4
  }
  set +e
  ( cd "$wt" && fm_run_timed "$PRODUCER_TIMEOUT" "${argv[@]}" ) </dev/null > "$log" 2>&1
  rc=$?
  set -e
  if [ "$rc" -eq 124 ]; then
    err "producer timed out after ${PRODUCER_TIMEOUT}s: ${argv[*]}"
    return 5
  fi
  if [ "$rc" -ne 0 ]; then
    err "producer exited $rc: ${argv[*]}"
    sed -n '1,20p' "$log" >&2 || true
    return 5
  fi
  return 0
}

# observe_producer_writes <wt> <before-snap> <out-file>: snapshot after, diff
# against before, filter ignored, then advance the before snapshot in place.
observe_producer_writes() {
  local wt=$1 before=$2 out=$3 after raw
  after=$(mktemp "${TMPDIR:-/tmp}/fm-plan-preflight-snap.XXXXXX") || return 4
  raw=$(mktemp "${TMPDIR:-/tmp}/fm-plan-preflight-diff.XXXXXX") || { rm -f "$after"; return 4; }
  snapshot_tree "$wt" "$after" || { rm -f "$after" "$raw"; return 4; }
  diff_snapshots "$before" "$after" "$raw" || { rm -f "$after" "$raw"; return 4; }
  filter_ignored "$wt" "$raw" "$out" || { rm -f "$after" "$raw"; return 4; }
  cp "$after" "$before"
  rm -f "$after" "$raw"
  return 0
}

# --- commands -------------------------------------------------------------------

cmd_lint() {
  local plan
  plan=$(resolve_read_file "PLAN" "$1") || exit 4
  lint_plan "$plan"
}

default_evidence_path() {
  printf '%s.preflight.json\n' "$1"
}

cmd_rehearse() {
  local plan_in=$1 repo_in=$2 base_in=$3 evidence_in=$4
  local plan repo evidence base_ref base_sha rc
  plan=$(resolve_read_file "PLAN" "$plan_in") || exit 4
  set +e
  lint_plan "$plan"
  rc=$?
  set -e
  case "$rc" in
    0) : ;;
    2) exit 2 ;;
    3) err "a legacy PLAN has no contract to rehearse against"; exit 3 ;;
    *) exit 4 ;;
  esac
  require_python3 || exit 4
  repo=$(resolve_repo "$repo_in") || exit 4
  if [ -n "$evidence_in" ]; then
    evidence=$(resolve_write_file "--evidence" "$evidence_in") || exit 4
  else
    evidence=$(default_evidence_path "$plan")
  fi
  local base_pair
  base_pair=$(resolve_base "$repo" "$base_in") || exit 4
  base_ref=${base_pair%%"$TAB"*}
  base_sha=${base_pair#*"$TAB"}
  assert_clean_clone "$repo" || exit 5

  local tmp wt snap bundle
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-plan-preflight.XXXXXX") || exit 4
  wt="$tmp/worktree"
  snap="$tmp/snapshot"
  bundle="$tmp/bundle"
  # shellcheck disable=SC2064  # intentional early expansion of $tmp/$repo
  trap "rm -rf '$tmp'; git -C '$repo' worktree prune 2>/dev/null || true" EXIT

  make_rehearsal_worktree "$repo" "$base_sha" "$wt" || exit 5
  snapshot_tree "$wt" "$snap" || exit 4

  local overall_closure=pass
  local undeclared_total=0
  local i log observed undeclared path covered
  : > "$bundle"
  i=1
  while [ "$i" -le "$NPROD" ]; do
    log="$tmp/producer.$i.log"
    observed="$tmp/observed.$i"
    if ! run_producer_argv "$wt" "$log" "${PROD_ARGV[$i]}"; then
      err "producer ${PROD_ID[$i]} failed; rehearsal cannot produce evidence"
      exit 5
    fi
    observe_producer_writes "$wt" "$snap" "$observed" || exit 4
    printf 'PRODUCER%s%s\n' "$TAB" "${PROD_ID[$i]}" >> "$bundle"
    printf 'ARGV' >> "$bundle"
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      printf '%s%s' "$TAB" "$path" >> "$bundle"
    done <<EOF
${PROD_ARGV[$i]}
EOF
    printf '\n' >> "$bundle"
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      printf 'OUTPUT%s%s\n' "$TAB" "$path" >> "$bundle"
    done <<EOF
${PROD_OUT[$i]}
EOF
    undeclared=
    while IFS="$TAB" read -r path _kind; do
      [ -n "$path" ] || continue
      printf 'OBSERVED%s%s\n' "$TAB" "$path" >> "$bundle"
      covered=0
      if covered_by_paths "$path" || covered_by_outputs "${PROD_OUT[$i]}" "$path"; then
        covered=1
      fi
      if [ "$covered" -eq 0 ]; then
        printf 'UNDECLARED%s%s\n' "$TAB" "$path" >> "$bundle"
        undeclared="${undeclared}${undeclared:+$'\n'}${path}"
      fi
    done < "$observed"
    if [ -n "$undeclared" ]; then
      overall_closure=fail
      undeclared_total=$((undeclared_total + $(printf '%s\n' "$undeclared" | grep -c .)))
      printf 'PCLOSURE%sfail\n' "$TAB" >> "$bundle"
    else
      printf 'PCLOSURE%spass\n' "$TAB" >> "$bundle"
    fi
    printf 'ENDPRODUCER\n' >> "$bundle"
    i=$((i + 1))
  done

  remove_rehearsal_worktree "$repo" "$wt"

  local verdict=$overall_closure
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  {
    printf 'PLAN_ID%s%s\n' "$TAB" "$PLAN_ID"
    printf 'CONTRACT_VERSION%s%s\n' "$TAB" "$CV"
    printf 'PLAN_SHA256%s%s\n' "$TAB" "$(plan_sha256 "$plan")"
    printf 'REPO_PATH%s%s\n' "$TAB" "$repo"
    printf 'BASE_REF%s%s\n' "$TAB" "$base_ref"
    printf 'BASE_SHA%s%s\n' "$TAB" "$base_sha"
    printf 'REHEARSED_AT%s%s\n' "$TAB" "$now"
    printf 'VERDICT%s%s\n' "$TAB" "$verdict"
    printf 'CLOSURE%s%s\n' "$TAB" "$overall_closure"
  } >> "$bundle"
  write_evidence "$bundle" "$evidence" || exit 4

  if [ "$overall_closure" = pass ]; then
    printf 'REHEARSAL: PASS plan_id=%s base=%s@%s producers=%s evidence=%s\n' \
      "$PLAN_ID" "$base_ref" "$base_sha" "$NPROD" "$evidence"
    return 0
  fi
  python3 - "$evidence" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    doc = json.load(fh)
for p in doc.get("producers", []):
    for path in p.get("undeclared_writes", []):
        print("UNDECLARED_WRITE: %s wrote %s (covered by neither allowed_scope.paths nor the producer's declared outputs)" % (p["id"], path))
PY
  printf 'REHEARSAL: FAIL plan_id=%s base=%s@%s undeclared=%s evidence=%s\n' \
    "$PLAN_ID" "$base_ref" "$base_sha" "$undeclared_total" "$evidence" >&2
  err "closure violation: every producer write must be covered by allowed_scope.paths or the producer's declared outputs; fix the PLAN declaration or prove a mechanical amendment (fm-plan-preflight.sh amend) before dispatch"
  return 5
}

cmd_verify() {
  local plan_in=$1 repo_in=$2 evidence_in=$3
  local plan evidence rc
  plan=$(resolve_read_file "PLAN" "$plan_in") || exit 4
  set +e
  lint_plan "$plan"
  rc=$?
  set -e
  case "$rc" in
    0) : ;;
    2) exit 2 ;;
    3) err "a legacy PLAN has no preflight evidence to verify"; exit 3 ;;
    *) exit 4 ;;
  esac
  require_python3 || exit 4
  if [ -n "$evidence_in" ]; then
    if ! evidence=$(resolve_read_file "--evidence" "$evidence_in" 2>/dev/null); then
      err "missing rehearsal evidence: $evidence_in (run: fm-plan-preflight.sh rehearse '$plan' --repo <target-clone>)"
      exit 5
    fi
  else
    evidence=$(default_evidence_path "$plan")
    [ -f "$evidence" ] || {
      err "missing rehearsal evidence: $evidence (run: fm-plan-preflight.sh rehearse '$plan' --repo <target-clone>)"
      exit 5
    }
  fi
  local bundle
  bundle=$(mktemp "${TMPDIR:-/tmp}/fm-plan-preflight-ev.XXXXXX") || exit 4
  # shellcheck disable=SC2064  # intentional early expansion
  trap "rm -f '$bundle'" EXIT
  reset_evidence_globals
  read_evidence "$evidence" "$bundle" || exit 4
  read_evidence_bundle "$bundle" || exit 4

  # Identity binding.
  if [ "$EV_PLAN_ID" != "$PLAN_ID" ] || [ "$EV_CV" != "$CV" ]; then
    err "evidence identity mismatch: evidence plan_id=$EV_PLAN_ID contract_version=$EV_CV vs PLAN plan_id=$PLAN_ID contract_version=$CV"
    exit 5
  fi
  local sha_now
  sha_now=$(plan_sha256 "$plan")
  if [ "$EV_PLAN_SHA" != "$sha_now" ]; then
    err "the PLAN changed since rehearsal (sha256 $EV_PLAN_SHA -> $sha_now); re-rehearse before dispatch"
    exit 5
  fi

  # Producer inventory binding.
  local i ev_idx
  if [ "$EV_NPROD" -ne "$NPROD" ]; then
    err "producer inventory drifted: contract declares $NPROD, evidence recorded $EV_NPROD; re-rehearse"
    exit 5
  fi
  i=1
  while [ "$i" -le "$NPROD" ]; do
    if ! ev_producer_index "${PROD_ID[$i]}" >/dev/null; then
      err "producer ${PROD_ID[$i]} has no recorded rehearsal evidence; re-rehearse"
      exit 5
    fi
    i=$((i + 1))
  done

  # Baseline drift against the recorded (or overridden) clone.
  local repo sha_live
  if [ -n "$repo_in" ]; then
    repo=$(resolve_repo "$repo_in") || exit 4
  else
    if ! repo=$(resolve_dir "evidence repo" "$EV_REPO_PATH" 2>/dev/null); then
      err "the clone recorded in the evidence cannot be resolved: $EV_REPO_PATH"
      exit 5
    fi
  fi
  sha_live=$(git -C "$repo" rev-parse --verify --quiet "$EV_BASE_REF^{commit}") || {
    err "baseline ref $EV_BASE_REF no longer resolves in $repo; re-rehearse"
    exit 5
  }
  if [ "$sha_live" != "$EV_BASE_SHA" ]; then
    err "baseline drift: $EV_BASE_REF moved $EV_BASE_SHA -> $sha_live since rehearsal; re-rehearse"
    exit 5
  fi

  # Recorded verdict plus closure recomputed from the recorded write-set.
  if [ "$EV_VERDICT" != "pass" ] || [ "$EV_CLOSURE" != "pass" ]; then
    i=1
    while [ "$i" -le "$EV_NPROD" ]; do
      if [ -n "${EV_PROD_UNDECLARED[$i]}" ]; then
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          printf 'UNDECLARED_WRITE: %s wrote %s (covered by neither allowed_scope.paths nor the producer'\''s declared outputs)\n' "${EV_PROD_ID[$i]}" "$line" >&2
        done <<EOF
${EV_PROD_UNDECLARED[$i]}
EOF
      fi
      i=$((i + 1))
    done
    err "rehearsal evidence verdict is fail; repair the declaration (or prove a mechanical amendment) and re-rehearse before dispatch"
    exit 5
  fi
  i=1
  while [ "$i" -le "$EV_NPROD" ]; do
    ev_idx=$(producer_index "${EV_PROD_ID[$i]}") || {
      err "evidence producer ${EV_PROD_ID[$i]} is not declared in the PLAN; re-rehearse"
      exit 5
    }
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if ! covered_by_paths "$line" && ! covered_by_outputs "${PROD_OUT[$ev_idx]}" "$line"; then
        err "closure no longer holds: recorded write $line is uncovered in the current contract; re-rehearse"
        exit 5
      fi
    done <<EOF
${EV_PROD_OBSERVED[$i]}
EOF
    i=$((i + 1))
  done

  printf 'PREFLIGHT: PASS plan_id=%s contract_version=%s base=%s@%s producers=%s evidence=%s\n' \
    "$PLAN_ID" "$CV" "$EV_BASE_REF" "$EV_BASE_SHA" "$EV_NPROD" "$evidence"
  return 0
}

cmd_amend() {
  local plan_in=$1 repo_in=$2 evidence_in=$3 producer=$4 adds_in=$5
  local plan evidence rc
  plan=$(resolve_read_file "PLAN" "$plan_in") || exit 4
  set +e
  lint_plan "$plan"
  rc=$?
  set -e
  case "$rc" in
    0) : ;;
    2) err "the mechanical amendment requires an approved automation-ready PLAN"; exit 2 ;;
    3) err "a legacy PLAN has no contract to amend; scope surprises stay stop-and-return"; exit 3 ;;
    *) exit 4 ;;
  esac
  require_python3 || exit 4
  local pidx
  if ! pidx=$(producer_index "$producer"); then
    err "producer '$producer' is not declared in the approved PLAN; only a declared producer's outputs can be amended"
    exit 4
  fi

  # Validate and dedupe --add entries; each must currently be uncovered.
  local add nadd=0
  local -a ADDS=()
  while IFS= read -r add; do
    [ -n "$add" ] || continue
    validate_output_entry "$add" || exit 4
    if newline_list_contains "$(printf '%s\n' "${ADDS[@]+"${ADDS[@]}"}")" "$add"; then
      err "duplicate --add: $add"
      exit 4
    fi
    if covered_by_paths "$add" || covered_by_outputs "${PROD_OUT[$pidx]}" "$add"; then
      err "--add $add is already covered by the contract; there is nothing to amend"
      exit 4
    fi
    nadd=$((nadd + 1))
    ADDS[nadd]=$add
  done <<EOF
$adds_in
EOF
  [ "$nadd" -gt 0 ] || { err "amend requires at least one --add path"; exit 4; }

  if [ -n "$evidence_in" ]; then
    evidence=$(resolve_read_file "--evidence" "$evidence_in") || exit 4
  else
    evidence=$(default_evidence_path "$plan")
    [ -f "$evidence" ] || {
      err "amend requires the dispatch rehearsal evidence: $evidence (run rehearse first)"
      exit 5
    }
  fi
  local tmp bundle
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-plan-preflight-amend.XXXXXX") || exit 4
  bundle="$tmp/bundle"
  reset_evidence_globals
  read_evidence "$evidence" "$bundle" || { rm -rf "$tmp"; exit 4; }
  read_evidence_bundle "$bundle" || { rm -rf "$tmp"; exit 4; }
  if [ "$EV_PLAN_ID" != "$PLAN_ID" ] || [ "$EV_PLAN_SHA" != "$(plan_sha256 "$plan")" ]; then
    rm -rf "$tmp"
    err "the PLAN changed since rehearsal; re-rehearse before amending"
    exit 5
  fi
  local ev_idx
  if ! ev_idx=$(ev_producer_index "$producer"); then
    rm -rf "$tmp"
    err "producer $producer has no recorded rehearsal evidence"
    exit 5
  fi
  local repo
  if [ -n "$repo_in" ]; then
    repo=$(resolve_repo "$repo_in") || { rm -rf "$tmp"; exit 4; }
  else
    repo=$(resolve_dir "evidence repo" "$EV_REPO_PATH") || { rm -rf "$tmp"; exit 4; }
  fi
  # shellcheck disable=SC2064  # intentional early expansion of $tmp/$repo
  trap "rm -rf '$tmp'; git -C '$repo' worktree prune 2>/dev/null || true" EXIT

  # Eligibility: two identical clean reruns at the recorded baseline.
  local wt_a="$tmp/a/worktree" wt_b="$tmp/b/worktree"
  mkdir -p "$tmp/a" "$tmp/b"
  local snap_a="$tmp/a/snap" snap_b="$tmp/b/snap"
  local obs_a="$tmp/a/observed" obs_b="$tmp/b/observed"
  local run_argv
  run_argv=$(printf '%s\n' "${EV_PROD_ARGV[$ev_idx]}" | tr '\t' '\n')
  if ! make_rehearsal_worktree "$repo" "$EV_BASE_SHA" "$wt_a"; then
    exit 5
  fi
  snapshot_tree "$wt_a" "$snap_a" || exit 4
  if ! run_producer_argv "$wt_a" "$tmp/a.log" "$run_argv"; then
    remove_rehearsal_worktree "$repo" "$wt_a"
    exit 5
  fi
  observe_producer_writes "$wt_a" "$snap_a" "$obs_a" || exit 4
  if ! make_rehearsal_worktree "$repo" "$EV_BASE_SHA" "$wt_b"; then
    remove_rehearsal_worktree "$repo" "$wt_a"
    exit 5
  fi
  snapshot_tree "$wt_b" "$snap_b" || exit 4
  if ! run_producer_argv "$wt_b" "$tmp/b.log" "$run_argv"; then
    remove_rehearsal_worktree "$repo" "$wt_a"
    remove_rehearsal_worktree "$repo" "$wt_b"
    exit 5
  fi
  observe_producer_writes "$wt_b" "$snap_b" "$obs_b" || exit 4

  local paths_a paths_b recorded_sorted
  paths_a=$(cut -f1 "$obs_a" | LC_ALL=C sort)
  paths_b=$(cut -f1 "$obs_b" | LC_ALL=C sort)
  if [ "$paths_a" != "$paths_b" ]; then
    remove_rehearsal_worktree "$repo" "$wt_a"
    remove_rehearsal_worktree "$repo" "$wt_b"
    err "producer $producer is not deterministic at the recorded baseline: two clean reruns produced different write-sets"
    exit 5
  fi
  # Content identity across the reruns (hash comparison from the snapshots).
  if ! python3 - "$snap_a" "$snap_b" "$obs_a" <<'PY'
import sys

def load(p):
    d = {}
    with open(p) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 5:
                d[parts[0]] = parts[2]
    return d

snap_a = load(sys.argv[1])
snap_b = load(sys.argv[2])
diffs = []
with open(sys.argv[3]) as fh:
    for line in fh:
        path = line.split("\t")[0].rstrip("\n")
        if not path:
            continue
        if snap_a.get(path) != snap_b.get(path):
            diffs.append(path)
if diffs:
    for d in diffs:
        print("error: producer output content differs across clean reruns: %s" % d, file=sys.stderr)
    sys.exit(1)
PY
  then
    remove_rehearsal_worktree "$repo" "$wt_a"
    remove_rehearsal_worktree "$repo" "$wt_b"
    err "producer $producer is not deterministic at the recorded baseline: content differs across clean reruns"
    exit 5
  fi
  # The reruns must match the dispatch evidence's recorded write-set exactly.
  recorded_sorted=$(printf '%s\n' "${EV_PROD_OBSERVED[$ev_idx]}" | sed '/^$/d' | LC_ALL=C sort)
  if [ "$paths_a" != "$recorded_sorted" ]; then
    remove_rehearsal_worktree "$repo" "$wt_a"
    remove_rehearsal_worktree "$repo" "$wt_b"
    err "producer $producer write-set drifted from the dispatch evidence; re-rehearse instead of amending"
    exit 5
  fi
  remove_rehearsal_worktree "$repo" "$wt_a"
  remove_rehearsal_worktree "$repo" "$wt_b"

  # Every --add must cover at least one path this producer actually wrote.
  local i any observed_path
  i=1
  while [ "$i" -le "$nadd" ]; do
    any=0
    while IFS= read -r observed_path; do
      [ -n "$observed_path" ] || continue
      if pattern_covers "${ADDS[$i]}" "$observed_path"; then
        any=1
        break
      fi
    done <<EOF
$paths_a
EOF
    if [ "$any" -eq 0 ]; then
      err "--add ${ADDS[$i]} covers nothing producer $producer wrote at the baseline; the mechanical amendment only declares proven producer outputs"
      exit 5
    fi
    i=$((i + 1))
  done

  # The amendment must close the rehearsal completely, for every producer.
  local j ev_j uncovered
  j=1
  while [ "$j" -le "$EV_NPROD" ]; do
    ev_j=$(producer_index "${EV_PROD_ID[$j]}") || exit 4
    while IFS= read -r observed_path; do
      [ -n "$observed_path" ] || continue
      uncovered=1
      if covered_by_paths "$observed_path" || covered_by_outputs "${PROD_OUT[$ev_j]}" "$observed_path"; then
        uncovered=0
      elif [ "$j" -eq "$ev_idx" ]; then
        i=1
        while [ "$i" -le "$nadd" ]; do
          if pattern_covers "${ADDS[$i]}" "$observed_path"; then
            uncovered=0
            break
          fi
          i=$((i + 1))
        done
      fi
      if [ "$uncovered" -eq 1 ]; then
        err "amendment does not close the rehearsal: $observed_path (written by ${EV_PROD_ID[$j]}) remains undeclared; that is a stop-and-return decision, not an amendment"
        exit 5
      fi
    done <<EOF
${EV_PROD_OBSERVED[$j]}
EOF
    j=$((j + 1))
  done

  # Apply the PLAN edit transactionally, then re-lint the amended file.
  local adds_file="$tmp/adds" plan_tmp="$tmp/plan.new"
  : > "$adds_file"
  i=1
  while [ "$i" -le "$nadd" ]; do
    printf '%s\n' "${ADDS[$i]}" >> "$adds_file"
    i=$((i + 1))
  done
  local today
  today=$(date -u +%Y-%m-%d)
  apply_amendment_to_plan "$plan" "$producer" "$today" "$adds_file" "$plan_tmp" || exit 4
  local save_plan="$tmp/plan.orig"
  cp "$plan" "$save_plan"
  if ! lint_plan "$plan_tmp" >/dev/null 2>&1; then
    err "internal: the amended PLAN failed re-lint; the PLAN is untouched"
    exit 4
  fi
  cp "$plan_tmp" "$plan"
  if ! lint_plan "$plan" >/dev/null; then
    cp "$save_plan" "$plan"
    err "internal: the installed amended PLAN failed re-lint; the PLAN was restored"
    exit 4
  fi

  # Refresh the evidence sidecar from the amended contract plus the recorded
  # write-set, preserving the original rehearsal timestamp and amendments.
  local new_sha
  new_sha=$(plan_sha256 "$plan")
  local nbundle="$tmp/nbundle"
  : > "$nbundle"
  j=1
  while [ "$j" -le "$EV_NPROD" ]; do
    ev_j=$(producer_index "${EV_PROD_ID[$j]}") || exit 4
    {
      printf 'PRODUCER%s%s\n' "$TAB" "${EV_PROD_ID[$j]}"
      printf 'ARGV'
      printf '%s\n' "${EV_PROD_ARGV[$j]}" | tr '\t' '\n' | while IFS= read -r add; do
        [ -n "$add" ] || continue
        printf '%s%s' "$TAB" "$add"
      done
      printf '\n'
      while IFS= read -r add; do
        [ -n "$add" ] || continue
        printf 'OUTPUT%s%s\n' "$TAB" "$add"
      done <<EOF
${PROD_OUT[$ev_j]}
EOF
      while IFS= read -r add; do
        [ -n "$add" ] || continue
        printf 'OBSERVED%s%s\n' "$TAB" "$add"
      done <<EOF
${EV_PROD_OBSERVED[$j]}
EOF
      printf 'PCLOSURE%spass\n' "$TAB"
      printf 'ENDPRODUCER\n'
    } >> "$nbundle"
    j=$((j + 1))
  done
  i=1
  while [ "$i" -le "$EV_NAMEND" ]; do
    printf '%s\n' "${EV_AMEND[$i]}" >> "$nbundle"
    i=$((i + 1))
  done
  printf 'AMENDMENT%s%s%s%s%s%s' "$TAB" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TAB" "$producer" "$TAB" "$new_sha" >> "$nbundle"
  i=1
  while [ "$i" -le "$nadd" ]; do
    printf '%s%s' "$TAB" "${ADDS[$i]}" >> "$nbundle"
    i=$((i + 1))
  done
  printf '\n' >> "$nbundle"
  {
    printf 'PLAN_ID%s%s\n' "$TAB" "$PLAN_ID"
    printf 'CONTRACT_VERSION%s%s\n' "$TAB" "$CV"
    printf 'PLAN_SHA256%s%s\n' "$TAB" "$new_sha"
    printf 'REPO_PATH%s%s\n' "$TAB" "$EV_REPO_PATH"
    printf 'BASE_REF%s%s\n' "$TAB" "$EV_BASE_REF"
    printf 'BASE_SHA%s%s\n' "$TAB" "$EV_BASE_SHA"
    printf 'REHEARSED_AT%s%s\n' "$TAB" "$EV_REHEARSED_AT"
    printf 'VERDICT%spass\n' "$TAB"
    printf 'CLOSURE%spass\n' "$TAB"
  } >> "$nbundle"
  local evidence_tmp="$tmp/evidence.json"
  write_evidence "$nbundle" "$evidence_tmp" || exit 4
  cp "$evidence_tmp" "$evidence"

  local added_csv
  added_csv=$(printf '%s,' "${ADDS[@]+"${ADDS[@]}"}" | sed 's/,$//')
  printf 'AMENDMENT: PASS plan_id=%s producer=%s added=%s plan_sha256=%s evidence=%s\n' \
    "$PLAN_ID" "$producer" "$added_csv" "$new_sha" "$evidence"
  cat <<EOF
Record this amendment in the MR's '## PLAN Contract' section (Plan / Evidence / Deviation), e.g.:

  ### Amendment
  - mechanical producer-output closure: producer=$producer added=$added_csv (fm-plan-preflight amend, $today; proven by identical clean reruns at $EV_BASE_SHA)
EOF
  return 0
}

# apply_amendment_to_plan <plan> <producer-id> <date> <adds-file> <out-file>
# Inserts each added path into allowed_scope.paths and into the producer's
# outputs inside the contract segment, and inserts one Amendments line after
# the block (after any existing Amendments lines). Pure text surgery on the
# lint-validated shape; the caller re-lints the result before adopting it.
apply_amendment_to_plan() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import sys

plan, producer, date, adds_file, out = sys.argv[1:6]
def bad(msg):
    print("error: amendment edit: %s" % msg, file=sys.stderr)
    sys.exit(4)
with open(adds_file) as fh:
    adds = [l.rstrip("\n") for l in fh if l.rstrip("\n")]
if not adds:
    bad("no paths to add")
with open(plan) as fh:
    lines = fh.read().split("\n")
start = None
end = None
for i, line in enumerate(lines):
    if line.strip() == "```plan-contract":
        if start is not None:
            bad("multiple plan-contract blocks")
        start = i
    elif start is not None and end is None and line.strip() == "```":
        end = i
if start is None:
    bad("no plan-contract block")
if end is None:
    bad("unterminated plan-contract block")

def insert_after_last_item(idx, indent):
    # idx points at the header line (e.g. "  paths:"); items are "<indent>- .."
    j = idx + 1
    last = None
    while j < len(lines) and lines[j].startswith(indent + "- "):
        last = j
        j += 1
    if last is None:
        bad("no list items after %r" % lines[idx])
    existing = {lines[k][len(indent) + 2:] for k in range(idx + 1, last + 1)}
    payload = [indent + "- " + a for a in adds if a not in existing]
    if payload:
        lines[last + 1:last + 1] = payload
    return len(payload)

# allowed_scope.paths (0-space key, 2-space "paths:", 4-space items)
paths_idx = None
i = start
while i < end:
    if lines[i].rstrip() == "allowed_scope:":
        j = i + 1
        while j < end and lines[j].startswith("  "):
            if lines[j].rstrip() == "  paths:":
                paths_idx = j
                break
            j += 1
        break
    i += 1
if paths_idx is None:
    bad("allowed_scope.paths not found")
end += insert_after_last_item(paths_idx, "    ")

# producer outputs (2-space "- id:", 4-space "outputs:", 6-space items)
prod_idx = None
i = start
while i < end:
    if lines[i].rstrip() == "  - id: " + producer:
        j = i + 1
        while j < end and not lines[j].startswith("  - id: "):
            if lines[j].rstrip() == "    outputs:":
                prod_idx = j
                break
            j += 1
        break
    i += 1
if prod_idx is None:
    bad("outputs: for producer %s not found" % producer)
end += insert_after_last_item(prod_idx, "      ")

# Amendments line after the closing fence, following existing Amendments lines.
amend_line = (
    "Amendments: " + date + " mechanical producer-output closure producer="
    + producer + " added=" + ",".join(adds)
    + " (fm-plan-preflight amend; pre-authorized, no captain round)"
)
insert_at = end + 1
j = end + 1
while j < len(lines) and lines[j].startswith("Amendments:"):
    insert_at = j + 1
    j += 1
lines[insert_at:insert_at] = [amend_line]
with open(out, "w") as fh:
    fh.write("\n".join(lines))
PY
}

# --- entrypoint ------------------------------------------------------------------

CMD=${1:-}
case "$CMD" in
  lint|rehearse|verify|amend) ;;
  '') usage >&2; exit 4 ;;
  *) err "unknown command: $CMD"; usage >&2; exit 4 ;;
esac
shift

REPO=
BASE=
EVIDENCE=
PRODUCER=
ADDS_TEXT=
POS=()
want_value=
for a in "$@"; do
  if [ -n "$want_value" ]; then
    case "$a" in
      --*) err "--$want_value requires a value"; exit 4 ;;
    esac
    case "$want_value" in
      repo) REPO=$a ;;
      base) BASE=$a ;;
      evidence) EVIDENCE=$a ;;
      producer) PRODUCER=$a ;;
      add) ADDS_TEXT="${ADDS_TEXT}${ADDS_TEXT:+$'\n'}${a}" ;;
      *) err "internal parser state for --$want_value"; exit 4 ;;
    esac
    want_value=
    continue
  fi
  case "$a" in
    --repo) want_value=repo ;;
    --repo=*) REPO=${a#--repo=} ;;
    --base) want_value=base ;;
    --base=*) BASE=${a#--base=} ;;
    --evidence) want_value=evidence ;;
    --evidence=*) EVIDENCE=${a#--evidence=} ;;
    --producer) want_value=producer ;;
    --producer=*) PRODUCER=${a#--producer=} ;;
    --add) want_value=add ;;
    --add=*) ADDS_TEXT="${ADDS_TEXT}${ADDS_TEXT:+$'\n'}${a#--add=}" ;;
    --*) err "unknown flag: $a"; exit 4 ;;
    *) POS+=("$a") ;;
  esac
done
[ -z "$want_value" ] || { err "--$want_value requires a value"; exit 4; }

case "$CMD" in
  lint)
    [ "${#POS[@]}" -eq 1 ] || { err "lint takes exactly one PLAN"; exit 4; }
    [ -z "$REPO$BASE$EVIDENCE$PRODUCER$ADDS_TEXT" ] || { err "lint takes no --repo/--base/--evidence/--producer/--add"; exit 4; }
    cmd_lint "${POS[0]}"
    ;;
  rehearse)
    [ "${#POS[@]}" -eq 1 ] || { err "rehearse takes exactly one PLAN"; exit 4; }
    [ -n "$REPO" ] || { err "rehearse requires --repo <target-clone>"; exit 4; }
    [ -z "$PRODUCER$ADDS_TEXT" ] || { err "rehearse takes no --producer/--add"; exit 4; }
    cmd_rehearse "${POS[0]}" "$REPO" "$BASE" "$EVIDENCE"
    ;;
  verify)
    [ "${#POS[@]}" -eq 1 ] || { err "verify takes exactly one PLAN"; exit 4; }
    [ -z "$BASE$PRODUCER$ADDS_TEXT" ] || { err "verify takes no --base/--producer/--add"; exit 4; }
    cmd_verify "${POS[0]}" "$REPO" "$EVIDENCE"
    ;;
  amend)
    [ "${#POS[@]}" -eq 1 ] || { err "amend takes exactly one PLAN"; exit 4; }
    [ -n "$PRODUCER" ] || { err "amend requires --producer <id>"; exit 4; }
    [ -n "$ADDS_TEXT" ] || { err "amend requires at least one --add <path>"; exit 4; }
    [ -z "$BASE" ] || { err "amend rehearses at the evidence's recorded baseline and takes no --base"; exit 4; }
    cmd_amend "${POS[0]}" "$REPO" "$EVIDENCE" "$PRODUCER" "$ADDS_TEXT"
    ;;
esac
