#!/usr/bin/env bash
set -euo pipefail

# Build command as array (safer than eval)
CMD=(kube-events)

# Add filter flags
if [[ -n "${INPUT_NAMESPACE}" ]]; then
  IFS=',' read -ra NS_LIST <<< "${INPUT_NAMESPACE}"
  for ns in "${NS_LIST[@]}"; do
    trimmed=$(echo "${ns}" | xargs)
    CMD+=(-n "${trimmed}")
  done
fi

if [[ -n "${INPUT_KIND}" ]]; then
  CMD+=(-k "${INPUT_KIND}")
fi

if [[ -n "${INPUT_NAME:-}" ]]; then
  CMD+=(-N "${INPUT_NAME}")
fi

if [[ -n "${INPUT_TYPE:-}" ]]; then
  CMD+=(-t "${INPUT_TYPE}")
fi

if [[ -n "${INPUT_REASON:-}" ]]; then
  CMD+=(-r "${INPUT_REASON}")
fi

if [[ -n "${INPUT_SINCE}" ]]; then
  CMD+=(--since "${INPUT_SINCE}")
fi

if [[ -n "${INPUT_OUTPUT}" ]]; then
  CMD+=(-o "${INPUT_OUTPUT}")
fi

if [[ "${INPUT_SUMMARY_ONLY}" == "true" ]]; then
  CMD+=(-s)
fi

if [[ "${INPUT_ALL_NAMESPACES}" == "true" ]]; then
  CMD+=(--all-namespaces)
fi

echo "::group::Running kube-events"
echo "Command: ${CMD[*]}"

# Run kube-events and capture output
set +e
RESULT=$("${CMD[@]}" 2>&1)
EXIT_CODE=$?
set -e

echo "${RESULT}"
echo "::endgroup::"

# Extract warning count from output
# Try JSON parsing first, fall back to regex
WARNING_COUNT=0
if [[ "${INPUT_OUTPUT}" == "json" ]]; then
  WARNING_COUNT=$(echo "${RESULT}" | grep -o '"warningCount":[0-9]*' | head -1 | cut -d: -f2 || echo "0")
else
  # Parse from summary line: "Warning: N" or "(Warning: N,"
  WARNING_COUNT=$(echo "${RESULT}" | grep -oE 'Warning: [0-9]+' | head -1 | grep -oE '[0-9]+' || echo "0")
fi

if [[ -z "${WARNING_COUNT}" ]]; then
  WARNING_COUNT=0
fi

# Set outputs
{
  echo "warning-count=${WARNING_COUNT}"
  if [[ ${WARNING_COUNT} -gt 0 ]]; then
    echo "has-warnings=true"
  else
    echo "has-warnings=false"
  fi
} >> "${GITHUB_OUTPUT}"

# Handle multiline result output
{
  echo "result<<KUBE_EVENTS_EOF"
  echo "${RESULT}"
  echo "KUBE_EVENTS_EOF"
} >> "${GITHUB_OUTPUT}"

# Handle exit code
if [[ ${EXIT_CODE} -ne 0 ]]; then
  echo "::error::kube-events encountered an error (exit code: ${EXIT_CODE})"
  exit 1
fi

# Check threshold
THRESHOLD="${INPUT_THRESHOLD:-0}"
if [[ ${THRESHOLD} -gt 0 ]] && [[ ${WARNING_COUNT} -gt ${THRESHOLD} ]]; then
  echo "::error::Warning count (${WARNING_COUNT}) exceeds threshold (${THRESHOLD})"
  exit 1
fi
