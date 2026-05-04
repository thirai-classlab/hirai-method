#!/usr/bin/env bash
# run-tests.sh — wrapper that runs every test-*.sh in this directory.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_FAIL=0
TOTAL_RUN=0

for t in "$DIR"/test-*.sh; do
  [ -f "$t" ] || continue
  printf "\n=== %s ===\n" "$(basename "$t")"
  if bash "$t"; then
    :
  else
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
  TOTAL_RUN=$((TOTAL_RUN + 1))
done

printf "\n=== run-tests.sh summary: %d files run, %d failed ===\n" \
  "$TOTAL_RUN" "$TOTAL_FAIL"

[ "$TOTAL_FAIL" -eq 0 ]
