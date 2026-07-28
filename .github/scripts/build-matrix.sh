#!/usr/bin/env bash
set -euo pipefail

# Builds a dynamic GitHub Actions matrix for run-samples.yml.
# Usage: build-matrix.sh <run_mode> [base_sha] [arch_filter]

# "all" runs every test; "changed" only runs tests whose watch_folders have modified files
RUN_MODE="${1:-all}"
BASE_SHA="${2:-}"
# "both" runs each test on every architecture it supports; "amd64"/"arm64" restrict it to one
ARCH_FILTER="${3:-both}"

# Get JSON metadata for all tests from run-samples.sh --list
TEST_META=$(./run-samples.sh --list)
TOTAL=$(echo "$TEST_META" | jq length)
echo "Run mode: $RUN_MODE | Arch filter: $ARCH_FILTER | Total tests: $TOTAL"

# Changes to these files affect all tests, so any modification triggers a full run
INFRA_FILES="run-samples.sh Makefile .github/workflows/run-samples.yml .github/scripts/build-matrix.sh pyproject.toml requirements-dev.txt requirements-runtime.txt"

if [[ "$RUN_MODE" == "changed" && -n "$BASE_SHA" ]]; then
  # Get list of files changed between base branch and current HEAD
  CHANGED=$(git diff --name-only "$BASE_SHA"..HEAD || true)
  echo "Changed files:"
  echo "$CHANGED"

  # Safety net: if any infrastructure file changed, run all tests
  RUN_ALL=false
  for f in $INFRA_FILES; do
    if echo "$CHANGED" | grep -qF "$f"; then
      echo "Infra changed: $f -> running all"
      RUN_ALL=true && break
    fi
  done

  if [[ "$RUN_ALL" == "true" ]]; then
    INDICES=$(seq 0 $((TOTAL-1)))
  else
    # Match changed files against each test's watch_folders using prefix matching
    INDICES=""
    for (( i=0; i<TOTAL; i++ )); do
      mapfile -t folders < <(echo "$TEST_META" | jq -r ".[$i].watch_folders[]")
      for wf in "${folders[@]}"; do
        if echo "$CHANGED" | grep -q "^${wf}/"; then
          INDICES+=" $i" && break
        fi
      done
    done
    INDICES=$(echo "$INDICES" | xargs)
  fi
else
  # "all" mode: select every test
  INDICES=$(seq 0 $((TOTAL-1)))
fi

# Output the matrix JSON for GitHub Actions
if [[ -z "${INDICES:-}" ]]; then
  MATRIX='{"include":[]}'
else
  # Convert space-separated indices to JSON array, then build the matrix object.
  # Each selected test is expanded into one entry per architecture it supports, so a
  # test that runs on both arches becomes two independent jobs. Tests that declare only
  # amd64 depend on an amd64-only container image — see run-samples.sh for the details.
  IDX_JSON=$(echo "$INDICES" | tr ' ' '\n' | jq -R 'tonumber' | jq -s '.')
  MATRIX=$(echo "$TEST_META" | jq -c --argjson idx "$IDX_JSON" --arg filter "$ARCH_FILTER" \
    '{include: [
        $idx[] as $i | .[$i] as $test |
        $test.arches[] |
        select($filter == "both" or . == $filter) |
        {
          shard:  $test.shard,
          splits: $test.splits,
          arch:   .,
          runner: (if . == "arm64" then "ubuntu-22.04-arm" else "ubuntu-22.04" end),
          name:   ($test.name + " [" + . + "]")
        }
      ]}')
fi

# An arch filter can select tests that support no matching architecture, so decide
# has_tests from the expanded matrix rather than from the selected indices.
JOB_COUNT=$(echo "$MATRIX" | jq '.include | length')
if [[ "$JOB_COUNT" -eq 0 ]]; then
  echo "No tests to run."
  echo "has_tests=false" >> "$GITHUB_OUTPUT"
  echo 'matrix={"include":[]}' >> "$GITHUB_OUTPUT"
else
  echo "has_tests=true" >> "$GITHUB_OUTPUT"
  echo "matrix=$MATRIX" >> "$GITHUB_OUTPUT"
  echo "Matrix ($JOB_COUNT jobs):" && echo "$MATRIX" | jq .
fi
