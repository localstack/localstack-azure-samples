#!/usr/bin/env bash
set -euo pipefail

# Builds a dynamic GitHub Actions matrix for run-samples.yml.
# Usage: build-matrix.sh <run_mode> [base_sha]

# "all" runs every test; "changed" only runs tests whose watch_folders have modified files
RUN_MODE="${1:-all}"
BASE_SHA="${2:-}"

# Get JSON metadata for all tests from run-samples.sh --list
TEST_META=$(./run-samples.sh --list)
TOTAL=$(echo "$TEST_META" | jq length)
echo "Run mode: $RUN_MODE | Total tests: $TOTAL"

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
  echo "No tests to run."
  echo "has_tests=false" >> "$GITHUB_OUTPUT"
  echo 'matrix={"include":[]}' >> "$GITHUB_OUTPUT"
else
  echo "has_tests=true" >> "$GITHUB_OUTPUT"
  # Convert space-separated indices to JSON array, then build the matrix object
  IDX_JSON=$(echo "$INDICES" | tr ' ' '\n' | jq -R 'tonumber' | jq -s '.')
  MATRIX=$(echo "$TEST_META" | jq -c --argjson idx "$IDX_JSON" \
    '{include: [$idx[] as $i | .[$i] | {shard, splits, name}]}')
  echo "matrix=$MATRIX" >> "$GITHUB_OUTPUT"
  echo "Matrix:" && echo "$MATRIX" | jq .
fi
