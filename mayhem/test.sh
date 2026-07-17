#!/usr/bin/env bash
#
# georinex/mayhem/test.sh — RUN the known-answer behavioral oracle (mayhem/test_kat.py) via the
# native ELF launcher build.sh produced, and emit a CTRF (ctrf.io) summary. Exit 0 iff no check
# failed. This script only RUNS the suite — it never builds anything.
#
# The oracle asserts georinex's decoded RINEX values + error semantics exactly (see test_kat.py),
# so a no-op / exit(0) / output-altering patch CANNOT pass it. We run it through /mayhem/georinex-test
# (a non-system ELF) so the anti-reward-hack sabotage check can neuter the program and observe the
# oracle FAIL — proving it asserts behavior, not just exit code.
set -uo pipefail

SRC="${SRC:-/mayhem}"
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/georinex-test"
if [ ! -x "$RUNNER" ]; then
  echo "FATAL: $RUNNER missing — build.sh did not produce the test launcher" >&2
  emit_ctrf "georinex-kat" 0 1 0
  exit 1
fi

echo "=== running georinex known-answer behavioral oracle ==="
out="$("$RUNNER" 2>&1)"; rc=$?
echo "$out"

PASSED=$(printf '%s\n' "$out" | grep -c '^PASS ')
FAILED=$(printf '%s\n' "$out" | grep -c '^FAIL ')

# No result lines (e.g. the runner was neutered or crashed before running) -> hard failure.
if [ $(( PASSED + FAILED )) -eq 0 ]; then
  echo "no test results parsed (runner exit $rc) — treating as failure" >&2
  emit_ctrf "georinex-kat" 0 1 0
  exit 1
fi

emit_ctrf "georinex-kat" "$PASSED" "$FAILED" 0
