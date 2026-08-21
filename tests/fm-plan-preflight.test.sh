#!/usr/bin/env bash
# Behavior tests for bin/fm-plan-preflight.sh.
#
# The anchor fixture is the PowerAgent queue-pressure pilot omission: a PLAN
# contract declares two OpenAPI generator outputs (docs/openapi.json and
# docs/openapi-by-path/**) while the deterministic generator also rewrites a
# third committed directory (docs/openapi-platform-simple/**). Generated
# content is committed byte-identical to the generator's output, so a git diff
# sees nothing: the rehearsal must catch the rewrite from the filesystem delta.
# The suite also covers the closure rule, every fail-closed condition named in
# the script header, the legacy-PLAN result, and the mechanical amendment.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v python3 >/dev/null 2>&1 || { echo "skip: python3 not found"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "skip: git not found"; exit 0; }

TMP_ROOT=$(fm_test_tmproot fm-plan-preflight)
TOOL="$ROOT/bin/fm-plan-preflight.sh"
fm_git_identity

# --- fixtures -----------------------------------------------------------------

# mk_pilot_repo <dir> [extra-generator-line]
# A git repo with a deterministic "OpenAPI generator" (mirroring the pilot's
# scripts/generate_openapi.py) that unconditionally rewrites three committed
# artifacts. Committed content equals generated content, so only the
# filesystem-level observation can see the write-set. The generator also writes
# a git-ignored cache file with nondeterministic content to prove ignored churn
# is neither a write-set signal nor a determinism blocker.
mk_pilot_repo() {
  local dir=$1 extra=${2:-}
  mkdir -p "$dir/scripts" "$dir/docs/openapi-by-path" "$dir/docs/openapi-platform-simple" "$dir/src"
  cat > "$dir/scripts/gen_openapi.py" <<PY
import time
from pathlib import Path
Path("docs/openapi.json").write_text('{"root": 1}\n')
Path("docs/openapi-by-path/pet.openapi.json").write_text('{"by_path": 1}\n')
Path("docs/openapi-platform-simple/pet.simple.openapi.json").write_text('{"simple": 1}\n')
Path("__pycache__").mkdir(exist_ok=True)
Path("__pycache__/gen.cpython-312.pyc").write_text(str(time.time()))
$extra
PY
  printf '__pycache__/\n' > "$dir/.gitignore"
  printf 'print("api")\n' > "$dir/src/api.py"
  # Commit generated artifacts byte-identical to the generator's output.
  ( cd "$dir" && python3 scripts/gen_openapi.py && rm -rf __pycache__ )
  git -C "$dir" init -q -b main
  git -C "$dir" add -A
  git -C "$dir" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm initial
}

# seg_scalars [plan_id]: the standard scalar/scope/ID portion of a contract.
seg_scalars() {
  printf '%s\n' \
    'contract_version: 1' \
    "plan_id: ${1:-custom}" \
    'plan_status: approved' \
    'automation_ready: true' \
    'open_decisions:' \
    '  product: 0' \
    '  scope: 0' \
    '  architecture: 0' \
    '  acceptance_semantics: 0' \
    'planning_critical_evidence_gaps: 0' \
    'allowed_scope:' \
    '  paths:' \
    '    - src/api.py' \
    '    - docs/openapi.json' \
    '    - docs/openapi-by-path/**' \
    '    - tests/**' \
    'invariants:' \
    '  - I1' \
    'proof_obligations:' \
    '  merge:' \
    '    - PO-1'
}

# seg_producer [extra outputs...]: the pilot's OpenAPI producer declaration.
seg_producer() {
  printf '%s\n' \
    'producers:' \
    '  - id: openapi' \
    '    argv:' \
    '      - python3' \
    '      - scripts/gen_openapi.py' \
    '    outputs:' \
    '      - docs/openapi.json' \
    '      - docs/openapi-by-path/**'
  local extra
  for extra in "$@"; do
    printf '      - %s\n' "$extra"
  done
}

# mk_custom_plan <file> <segment-text>
mk_custom_plan() {
  local file=$1 seg=$2
  {
    printf '# PLAN fixture\n\n## Execution contract\n\n```plan-contract\n'
    printf '%s\n' "$seg"
    printf '```\n'
  } > "$file"
}

# mk_plan <file> <plan_id> <outputs: two|three>
# The pilot PLAN contract. "two" reproduces the pilot omission (the third
# generated directory is declared nowhere); "three" adds
# docs/openapi-platform-simple/** to both allowed_scope.paths and the
# producer's outputs.
mk_plan() {
  local file=$1 pid=$2 outputs=$3
  local segment
  if [ "$outputs" = three ]; then
    segment=$(
      seg_scalars "$pid" | sed 's|^    - tests/\*\*$|    - docs/openapi-platform-simple/**\n    - tests/**|'
      seg_producer 'docs/openapi-platform-simple/**'
    )
  else
    segment=$(
      seg_scalars "$pid"
      seg_producer
    )
  fi
  mk_custom_plan "$file" "$segment"
}

run_tool() {  # captures stdout+stderr into $OUT and exit code into $RC
  OUT=$("$@" 2>&1)
  RC=$?
}

# --- tests --------------------------------------------------------------------

test_help_is_versioned_and_complete() {
  local help
  help=$("$TOOL" --help)
  assert_contains "$help" "preflight contract v1" "--help must name its contract version"
  assert_contains "$help" "fm-plan-preflight.sh lint <plan.md>" "--help must document lint"
  assert_contains "$help" "fm-plan-preflight.sh rehearse <plan.md>" "--help must document rehearse"
  assert_contains "$help" "fm-plan-preflight.sh verify <plan.md>" "--help must document verify"
  assert_contains "$help" "fm-plan-preflight.sh amend <plan.md>" "--help must document amend"
  assert_contains "$help" "3  LEGACY" "--help must define the legacy exit code"
  assert_contains "$help" "generated/**-style exemption is forbidden" "--help must carry the breadth rule"
  assert_contains "$help" "Any refusal leaves the PLAN untouched and the decision with the captain." "--help omitted its header terminator"
  pass "fm-plan-preflight.sh: --help is versioned and complete"
}

test_lint_gate_outcomes() {
  local d="$TMP_ROOT/lint-gate"
  mkdir -p "$d"
  mk_plan "$d/ok.md" gate-ok two
  run_tool "$TOOL" lint "$d/ok.md"
  expect_code 0 "$RC" "valid contract must lint clean"
  assert_contains "$OUT" "LINT: PASS plan_id=gate-ok contract_version=1 producers=1" "lint pass line"

  local seg
  seg=$(
    printf '%s\n' \
      'contract_version: 1' \
      'plan_id: gatefail' \
      'plan_status: approved' \
      'automation_ready: true' \
      'open_decisions:' \
      '  product: 0' \
      '  scope: 1' \
      '  architecture: 0' \
      '  acceptance_semantics: 0' \
      'planning_critical_evidence_gaps: 0' \
      'allowed_scope:' \
      '  paths:' \
      '    - src/api.py' \
      'invariants:' \
      '  - I1' \
      'proof_obligations:' \
      '  merge:' \
      '    - PO-1'
  )
  mk_custom_plan "$d/gatefail.md" "$seg"
  run_tool "$TOOL" lint "$d/gatefail.md"
  expect_code 2 "$RC" "nonzero counts must fail the gate"
  assert_contains "$OUT" "LINT: FAIL" "gate failure prints LINT: FAIL"
  assert_contains "$OUT" "scope=1" "gate failure names the nonzero count"

  printf '# prose-only PLAN\n' > "$d/legacy.md"
  run_tool "$TOOL" lint "$d/legacy.md"
  expect_code 3 "$RC" "a PLAN without a contract block is the legacy result"
  assert_contains "$OUT" "LINT: LEGACY" "legacy result is explicit"
  assert_contains "$OUT" "never labeled rehearsed" "legacy never claims rehearsal"

  seg=$(printf '%s\n' "$seg" | sed 's/plan_id: gatefail/plan_id: future/; s/  scope: 1/  scope: 0/; s/contract_version: 1/contract_version: 2/')
  mk_custom_plan "$d/future.md" "$seg"
  run_tool "$TOOL" lint "$d/future.md"
  expect_code 4 "$RC" "an unsupported contract_version fails closed"
  assert_contains "$OUT" "unsupported contract_version 2" "unsupported version is named"
  pass "fm-plan-preflight.sh: lint gate outcomes (pass / fail / legacy / unsupported version)"
}

test_lint_producer_schema_refusals() {
  local d="$TMP_ROOT/lint-schema"
  mkdir -p "$d"
  local seg

  seg=$(
    seg_scalars dup
    seg_producer
    printf '%s\n' \
      '  - id: openapi' \
      '    argv:' \
      '      - python3' \
      '      - b.py' \
      '    outputs:' \
      '      - docs/openapi.json'
  )
  mk_custom_plan "$d/dup-producer.md" "$seg"
  run_tool "$TOOL" lint "$d/dup-producer.md"
  expect_code 4 "$RC" "duplicate producer id must be refused"
  assert_contains "$OUT" "duplicate producer id: openapi" "duplicate producer id is named"

  seg=$(
    seg_scalars dupout
    printf '%s\n' \
      'producers:' \
      '  - id: one' \
      '    argv:' \
      '      - python3' \
      '      - a.py' \
      '    outputs:' \
      '      - docs/openapi.json' \
      '  - id: two' \
      '    argv:' \
      '      - python3' \
      '      - b.py' \
      '    outputs:' \
      '      - docs/openapi.json'
  )
  mk_custom_plan "$d/dup-output.md" "$seg"
  run_tool "$TOOL" lint "$d/dup-output.md"
  expect_code 4 "$RC" "duplicate output across producers must be refused"
  assert_contains "$OUT" "duplicate producer output declaration: docs/openapi.json" "duplicate output is named"

  seg=$(
    seg_scalars trav
    printf '%s\n' \
      'producers:' \
      '  - id: openapi' \
      '    argv:' \
      '      - python3' \
      '      - a.py' \
      '    outputs:' \
      '      - ../escape.txt'
  )
  mk_custom_plan "$d/traversal.md" "$seg"
  run_tool "$TOOL" lint "$d/traversal.md"
  expect_code 4 "$RC" "a path-escaping output must be refused"
  assert_contains "$OUT" "must not contain '..' segments" "traversal refusal is named"

  seg=$(
    seg_scalars broad
    printf '%s\n' \
      'producers:' \
      '  - id: openapi' \
      '    argv:' \
      '      - python3' \
      '      - a.py' \
      '    outputs:' \
      '      - generated/**'
  )
  mk_custom_plan "$d/broad.md" "$seg"
  run_tool "$TOOL" lint "$d/broad.md"
  expect_code 4 "$RC" "a broad generated/**-style output must be refused"
  assert_contains "$OUT" "at least two path segments" "breadth refusal is named"

  seg=$(
    seg_scalars shargv
    printf '%s\n' \
      'producers:' \
      '  - id: openapi' \
      '    argv:' \
      '      - sh' \
      '      - -c' \
      '      - rm -rf docs' \
      '    outputs:' \
      '      - docs/openapi.json'
  )
  mk_custom_plan "$d/shargv.md" "$seg"
  run_tool "$TOOL" lint "$d/shargv.md"
  expect_code 4 "$RC" "a shell-shaped argv must be refused"
  assert_contains "$OUT" "argv[0] 'sh'" "argv refusal is named"

  seg=$(
    seg_scalars nocov
    printf '%s\n' \
      'producers:' \
      '  - id: openapi' \
      '    argv:' \
      '      - python3' \
      '      - a.py' \
      '    outputs:' \
      '      - docs/other.json'
  )
  mk_custom_plan "$d/nocov.md" "$seg"
  run_tool "$TOOL" lint "$d/nocov.md"
  expect_code 4 "$RC" "an output outside allowed paths must be refused"
  assert_contains "$OUT" "not covered by allowed_scope.paths" "coverage refusal is named"

  # Duplicate contract blocks fail closed.
  mk_plan "$d/double.md" double two
  {
    cat "$d/double.md"
    # shellcheck disable=SC2016  # single quotes are deliberate: literal fence markers, not substitutions
    printf '\n```plan-contract\ncontract_version: 1\n```\n'
  } > "$d/double.md.new"
  mv "$d/double.md.new" "$d/double.md"
  run_tool "$TOOL" lint "$d/double.md"
  expect_code 4 "$RC" "duplicate contract blocks must be refused"
  assert_contains "$OUT" "multiple plan-contract blocks" "duplicate block refusal is named"

  # A tab anywhere in the segment fails closed.
  mk_plan "$d/tabbed.md" tabbed two
  {
    printf '# PLAN fixture\n\n```plan-contract\n'
    # shellcheck disable=SC2016  # single quotes are deliberate: literal fence markers in the sed ranges
    mk_plan /dev/stdout tabbed two | sed -n '/^```plan-contract$/,/^```$/p' | sed '1d;$d' | while IFS= read -r l; do
      case "$l" in
        '    - src/api.py') printf '\t- src/api.py\n' ;;
        *) printf '%s\n' "$l" ;;
      esac
    done
    printf '```\n'
  } > "$d/tabbed.md.new"
  mv "$d/tabbed.md.new" "$d/tabbed.md"
  run_tool "$TOOL" lint "$d/tabbed.md"
  expect_code 4 "$RC" "a tab in the segment must be refused"
  assert_contains "$OUT" "tab character is not allowed" "tab refusal is named"
  pass "fm-plan-preflight.sh: producer schema refusals (duplicates, traversal, breadth, argv safety, coverage, blocks, tabs)"
}

test_rehearse_pass_verify_and_isolation() {
  local d="$TMP_ROOT/pass"
  mkdir -p "$d"
  mk_pilot_repo "$d/repo"
  mk_plan "$d/PLAN.md" pilot-pass three
  local head_before wt_count_before evidence
  head_before=$(git -C "$d/repo" rev-parse HEAD)
  wt_count_before=$(git -C "$d/repo" worktree list | wc -l | tr -d ' ')

  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 0 "$RC" "fully declared write-set must pass rehearsal"
  assert_contains "$OUT" "REHEARSAL: PASS plan_id=pilot-pass" "rehearsal pass line"
  assert_present "$d/PLAN.md.preflight.json" "evidence sidecar written"
  evidence=$(cat "$d/PLAN.md.preflight.json")
  assert_contains "$evidence" '"observed_writes"' "evidence records the observed write-set"
  assert_contains "$evidence" 'docs/openapi-platform-simple/pet.simple.openapi.json' "evidence records the third directory's file"
  assert_not_contains "$evidence" '__pycache__' "git-ignored churn is filtered from the write-set"
  assert_contains "$evidence" '"verdict": "pass"' "evidence verdict passes"
  assert_contains "$evidence" '"base_ref": "main"' "evidence binds the baseline ref"

  # The rehearsal leaves the target clone untouched and removes its worktree.
  expect_code "$head_before" "$(git -C "$d/repo" rev-parse HEAD)" "rehearsal must not move the clone HEAD"
  expect_code "" "$(git -C "$d/repo" status --porcelain)" "rehearsal must leave the clone clean"
  expect_code "$wt_count_before" "$(git -C "$d/repo" worktree list | wc -l | tr -d ' ')" "rehearsal worktree must be removed"

  run_tool "$TOOL" verify "$d/PLAN.md"
  expect_code 0 "$RC" "fresh passing evidence verifies"
  assert_contains "$OUT" "PREFLIGHT: PASS plan_id=pilot-pass" "verify pass line"

  # A custom --evidence path works for both directions.
  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo" --evidence "$d/custom.json"
  expect_code 0 "$RC" "custom evidence path rehearses"
  run_tool "$TOOL" verify "$d/PLAN.md" --evidence "$d/custom.json"
  expect_code 0 "$RC" "custom evidence path verifies"
  pass "fm-plan-preflight.sh: rehearsal pass, isolation, and evidence verification"
}

test_pilot_omission_fails_before_dispatch_then_passes() {
  local d="$TMP_ROOT/pilot"
  mkdir -p "$d"
  mk_pilot_repo "$d/repo"
  # The exact pilot failure: two declared outputs, one undeclared directory.
  mk_plan "$d/PLAN.md" pilot-omission two
  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 5 "$RC" "the pilot omission must fail rehearsal before dispatch"
  assert_contains "$OUT" "UNDECLARED_WRITE: openapi wrote docs/openapi-platform-simple/pet.simple.openapi.json" "the undeclared third directory is named"
  assert_contains "$OUT" "REHEARSAL: FAIL" "rehearsal reports the closure failure"
  assert_present "$d/PLAN.md.preflight.json" "failure evidence is still recorded"
  run_tool "$TOOL" verify "$d/PLAN.md"
  expect_code 5 "$RC" "failed evidence keeps dispatch refused"
  assert_contains "$OUT" "docs/openapi-platform-simple/pet.simple.openapi.json" "verify replays the undeclared write"

  # Adding the exact third output (planner repair) passes.
  mk_plan "$d/PLAN.md" pilot-omission three
  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 0 "$RC" "declaring the exact third output passes rehearsal"
  run_tool "$TOOL" verify "$d/PLAN.md"
  expect_code 0 "$RC" "and then verifies"
  pass "fm-plan-preflight.sh: the pilot OpenAPI omission fails before dispatch and passes once declared"
}

test_unrelated_handwritten_write_fails_closure() {
  local d="$TMP_ROOT/handwritten"
  mkdir -p "$d"
  mk_pilot_repo "$d/repo" 'Path("src/other.py").write_text("# rewritten by generator\n")'
  printf '# handwritten\n' > "$d/repo/src/other.py"
  git -C "$d/repo" add src/other.py
  git -C "$d/repo" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm 'add handwritten file'
  # The generator overwrites a source file outside every declaration.
  mk_plan "$d/PLAN.md" pilot-handwritten three
  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 5 "$RC" "an undeclared source-file write must fail closure"
  assert_contains "$OUT" "UNDECLARED_WRITE: openapi wrote src/other.py" "the handwritten-path write is named"
  pass "fm-plan-preflight.sh: an unrelated handwritten/source change fails closure"
}

test_dirty_baseline_and_drift_refusals() {
  local d="$TMP_ROOT/dirty"
  mkdir -p "$d"
  mk_pilot_repo "$d/repo"
  mk_plan "$d/PLAN.md" pilot-dirty three

  printf 'junk\n' >> "$d/repo/src/api.py"
  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 5 "$RC" "a dirty baseline must refuse rehearsal"
  assert_contains "$OUT" "dirty baseline" "dirty baseline refusal is named"
  git -C "$d/repo" checkout -q -- src/api.py

  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 0 "$RC" "clean baseline rehearses"
  printf 'print("newer")\n' > "$d/repo/src/api.py"
  git -C "$d/repo" commit -qam 'advance baseline'
  run_tool "$TOOL" verify "$d/PLAN.md"
  expect_code 5 "$RC" "baseline drift must refuse verification"
  assert_contains "$OUT" "baseline drift" "drift refusal is named"
  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 0 "$RC" "re-rehearsal at the new baseline passes again"
  run_tool "$TOOL" verify "$d/PLAN.md"
  expect_code 0 "$RC" "and verifies fresh"
  pass "fm-plan-preflight.sh: dirty baseline and baseline drift fail closed"
}

test_plan_identity_and_evidence_mismatch() {
  local d="$TMP_ROOT/identity"
  mkdir -p "$d"
  mk_pilot_repo "$d/repo"
  mk_plan "$d/PLAN.md" pilot-identity three
  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 0 "$RC" "baseline rehearsal passes"

  printf '\nA comment changed after rehearsal.\n' >> "$d/PLAN.md"
  run_tool "$TOOL" verify "$d/PLAN.md"
  expect_code 5 "$RC" "an edited PLAN invalidates the evidence"
  assert_contains "$OUT" "changed since rehearsal" "PLAN edit is detected by sha256"

  # Evidence recorded for a different plan_id never verifies this PLAN.
  mk_plan "$d/OTHER.md" pilot-other three
  run_tool "$TOOL" rehearse "$d/OTHER.md" --repo "$d/repo"
  expect_code 0 "$RC" "second plan rehearses"
  run_tool "$TOOL" verify "$d/PLAN.md" --evidence "$d/OTHER.md.preflight.json"
  expect_code 5 "$RC" "foreign evidence must not verify"
  assert_contains "$OUT" "identity mismatch" "identity mismatch is named"

  printf '{"preflight_version": 1, "plan_id": ' > "$d/broken.json"
  run_tool "$TOOL" verify "$d/PLAN.md" --evidence "$d/broken.json"
  expect_code 4 "$RC" "malformed evidence JSON fails loudly"
  assert_contains "$OUT" "malformed evidence" "malformed evidence is named"
  pass "fm-plan-preflight.sh: PLAN identity and evidence mismatch fail closed"
}

test_legacy_plan_results() {
  local d="$TMP_ROOT/legacy"
  mkdir -p "$d"
  mk_pilot_repo "$d/repo"
  printf '# prose-only PLAN\nEverything is prose.\n' > "$d/PLAN.md"
  run_tool "$TOOL" lint "$d/PLAN.md"
  expect_code 3 "$RC" "legacy lint result"
  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 3 "$RC" "legacy plans are never rehearsed"
  assert_not_contains "$OUT" "REHEARSAL: PASS" "legacy never reports a rehearsal"
  assert_absent "$d/PLAN.md.preflight.json" "legacy writes no evidence"
  run_tool "$TOOL" verify "$d/PLAN.md"
  expect_code 3 "$RC" "legacy plans have no evidence to verify"
  run_tool "$TOOL" amend "$d/PLAN.md" --producer openapi --add 'docs/openapi-platform-simple/**'
  expect_code 3 "$RC" "legacy plans have no mechanical amendment path"
  pass "fm-plan-preflight.sh: legacy PLAN behavior is explicit and never labeled rehearsed"
}

test_amend_proves_and_records_the_pilot_repair() {
  local d="$TMP_ROOT/amend"
  mkdir -p "$d"
  mk_pilot_repo "$d/repo"
  mk_plan "$d/PLAN.md" pilot-amend two
  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 5 "$RC" "the omission fails rehearsal first"

  run_tool "$TOOL" amend "$d/PLAN.md" --producer openapi --add 'docs/openapi-platform-simple/**'
  expect_code 0 "$RC" "the proven mechanical amendment applies"
  assert_contains "$OUT" "AMENDMENT: PASS plan_id=pilot-amend producer=openapi added=docs/openapi-platform-simple/**" "amend pass line"
  assert_contains "$OUT" "### Amendment" "amend prints the MR declaration scaffold"
  assert_grep "    - docs/openapi-platform-simple/**" "$d/PLAN.md" "amend adds the path to allowed_scope.paths"
  assert_grep "      - docs/openapi-platform-simple/**" "$d/PLAN.md" "amend adds the path to the producer outputs"
  assert_grep "Amendments: $(date -u +%Y-%m-%d) mechanical producer-output closure producer=openapi added=docs/openapi-platform-simple/**" "$d/PLAN.md" "amend records the PLAN Amendments line"
  assert_contains "$(cat "$d/PLAN.md.preflight.json")" '"kind": "mechanical"' "evidence records the mechanical amendment"
  assert_contains "$(cat "$d/PLAN.md.preflight.json")" '"verdict": "pass"' "amended evidence passes"

  run_tool "$TOOL" verify "$d/PLAN.md"
  expect_code 0 "$RC" "the amended PLAN verifies for dispatch"

  # A second amendment of the same path is a no-op and refused as such.
  run_tool "$TOOL" amend "$d/PLAN.md" --producer openapi --add 'docs/openapi-platform-simple/**'
  expect_code 4 "$RC" "an already-covered path needs no amendment"
  assert_contains "$OUT" "nothing to amend" "no-op amendment is refused"
  pass "fm-plan-preflight.sh: the pilot repair is a proven, recorded mechanical amendment"
}

test_amend_refusals() {
  local d="$TMP_ROOT/amend-refuse"
  mkdir -p "$d"
  mk_pilot_repo "$d/repo"
  mk_plan "$d/PLAN.md" pilot-refusals two
  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 5 "$RC" "omission rehearsal fails"

  run_tool "$TOOL" amend "$d/PLAN.md" --producer nobody --add 'docs/openapi-platform-simple/**'
  expect_code 4 "$RC" "an undeclared producer cannot amend"
  assert_contains "$OUT" "not declared in the approved PLAN" "undeclared producer refusal"

  run_tool "$TOOL" amend "$d/PLAN.md" --producer openapi --add '../escape/**'
  expect_code 4 "$RC" "a path-escaping --add is refused"
  assert_contains "$OUT" "must not contain '..'" "traversal refusal"

  run_tool "$TOOL" amend "$d/PLAN.md" --producer openapi --add 'docs/never-written/**'
  expect_code 5 "$RC" "an --add the producer never wrote cannot be proven"
  assert_contains "$OUT" "covers nothing producer openapi wrote" "unproven output refusal"

  # A nondeterministic producer can never earn the mechanical amendment.
  local d2="$TMP_ROOT/amend-nondet"
  mkdir -p "$d2"
  mk_pilot_repo "$d2/repo" 'Path("docs/openapi-platform-simple/pet.simple.openapi.json").write_text(str(time.time()))'
  mk_plan "$d2/PLAN.md" pilot-nondet two
  run_tool "$TOOL" rehearse "$d2/PLAN.md" --repo "$d2/repo"
  expect_code 5 "$RC" "nondeterministic producer still fails closure on the omission"
  run_tool "$TOOL" amend "$d2/PLAN.md" --producer openapi --add 'docs/openapi-platform-simple/**'
  expect_code 5 "$RC" "a nondeterministic producer is amendment-ineligible"
  assert_contains "$OUT" "not deterministic" "nondeterminism refusal"
  # The failed amendment left the PLAN untouched.
  assert_no_grep "docs/openapi-platform-simple" "$d2/PLAN.md" "a refused amendment never edits the PLAN"
  pass "fm-plan-preflight.sh: amendment refusals stay stop-and-return"
}

test_producer_failure_refuses_rehearsal() {
  local d="$TMP_ROOT/producer-fail"
  mkdir -p "$d"
  mk_pilot_repo "$d/repo" 'raise SystemExit(3)'
  mk_plan "$d/PLAN.md" pilot-fail three
  run_tool "$TOOL" rehearse "$d/PLAN.md" --repo "$d/repo"
  expect_code 5 "$RC" "a failing producer refuses rehearsal"
  assert_contains "$OUT" "exited 3" "producer failure is named"
  assert_absent "$d/PLAN.md.preflight.json" "a failed producer writes no evidence"
  pass "fm-plan-preflight.sh: a failed producer run fails closed with no evidence"
}

test_help_is_versioned_and_complete
test_lint_gate_outcomes
test_lint_producer_schema_refusals
test_rehearse_pass_verify_and_isolation
test_pilot_omission_fails_before_dispatch_then_passes
test_unrelated_handwritten_write_fails_closure
test_dirty_baseline_and_drift_refusals
test_plan_identity_and_evidence_mismatch
test_legacy_plan_results
test_amend_proves_and_records_the_pilot_repair
test_amend_refusals
test_producer_failure_refuses_rehearsal
