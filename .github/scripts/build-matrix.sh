#!/usr/bin/env bash
set -euo pipefail

# Builds a dynamic GitHub Actions matrix for run-samples.yml.
# Usage: build-matrix.sh <run_mode> [base_sha]

RUN_MODE="${1:-all}"
BASE_SHA="${2:-}"

chmod +x ./run-samples.sh
TEST_META=$(./run-samples.sh --list)
TOTAL=$(echo "$TEST_META" | jq length)
echo "Run mode: $RUN_MODE | Total tests: $TOTAL"

INFRA_FILES="run-samples.sh Makefile .github/workflows/run-samples.yml .github/scripts/build-matrix.sh pyproject.toml requirements-dev.txt requirements-runtime.txt"

if [[ "$RUN_MODE" == "changed" && -n "$BASE_SHA" ]]; then
  CHANGED=$(git diff --name-only "$BASE_SHA"..HEAD || true)
  echo "Changed files:"
  echo "$CHANGED"

  # If any infrastructure file changed, run all tests
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
  INDICES=$(seq 0 $((TOTAL-1)))
fi

if [[ -z "${INDICES:-}" ]]; then
  echo "No tests to run."
  echo "has_tests=false" >> "$GITHUB_OUTPUT"
  echo 'matrix={"include":[]}' >> "$GITHUB_OUTPUT"
else
  echo "has_tests=true" >> "$GITHUB_OUTPUT"
  IDX_JSON=$(echo "$INDICES" | tr ' ' '\n' | jq -R 'tonumber' | jq -s '.')
  MATRIX=$(echo "$TEST_META" | jq -c --argjson idx "$IDX_JSON" \
    '{include: [$idx[] as $i | .[$i] | {shard, splits, name}]}')
  echo "matrix=$MATRIX" >> "$GITHUB_OUTPUT"
  echo "Matrix:" && echo "$MATRIX" | jq .
fi
