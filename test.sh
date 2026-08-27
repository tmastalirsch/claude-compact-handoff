#!/usr/bin/env bash
# Runs every suite.
cd "$(dirname "$0")"
fail=0
for s in test-lib.sh test-hooks.sh; do
  echo "═══ $s"
  bash "$s" || fail=1
  echo
done
if (( fail )); then echo "═══ FAILED"; else echo "═══ all green"; fi
exit $fail
