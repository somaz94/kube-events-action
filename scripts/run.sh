#!/usr/bin/env bash
set -euo pipefail

# Build command as array (safer than eval)
CMD=(kube-events)

if [[ -n "${INPUT_NAMESPACE}" ]]; then
  IFS=',' read -ra NS_LIST <<< "${INPUT_NAMESPACE}"
  for ns in "${NS_LIST[@]}"; do
    trimmed=$(echo "${ns}" | xargs)
    CMD+=(-n "${trimmed}")
  done
fi

if [[ -n "${INPUT_KIND}" ]]; then
  IFS=',' read -ra KIND_LIST <<< "${INPUT_KIND}"
  for kind in "${KIND_LIST[@]}"; do
    trimmed=$(echo "${kind}" | xargs)
    CMD+=(-k "${trimmed}")
  done
fi

if [[ -n "${INPUT_NAME:-}" ]]; then
  CMD+=(-N "${INPUT_NAME}")
fi

if [[ -n "${INPUT_TYPE:-}" ]]; then
  IFS=',' read -ra TYPE_LIST <<< "${INPUT_TYPE}"
  for type in "${TYPE_LIST[@]}"; do
    trimmed=$(echo "${type}" | xargs)
    CMD+=(-t "${trimmed}")
  done
fi

if [[ -n "${INPUT_REASON:-}" ]]; then
  IFS=',' read -ra REASON_LIST <<< "${INPUT_REASON}"
  for reason in "${REASON_LIST[@]}"; do
    trimmed=$(echo "${reason}" | xargs)
    CMD+=(-r "${trimmed}")
  done
fi

if [[ -n "${INPUT_SINCE}" ]]; then
  CMD+=(--since "${INPUT_SINCE}")
fi

if [[ -n "${INPUT_GROUP_BY:-}" ]] && [[ "${INPUT_GROUP_BY}" != "resource" ]]; then
  CMD+=(-g "${INPUT_GROUP_BY}")
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

# set +e: a failing run must still write its outputs before the exit check below
set +e
RESULT=$("${CMD[@]}" 2>&1)
EXIT_CODE=$?
set -e

echo "${RESULT}"
echo "::endgroup::"

WARNING_COUNT=0
if [[ "${INPUT_OUTPUT}" == "json" ]]; then
  WARNING_COUNT=$(echo "${RESULT}" | grep -oE '"warningCount"[[:space:]]*:[[:space:]]*[0-9]+' | head -1 | grep -oE '[0-9]+' || echo "0")
else
  # Parse from summary line: "Warning: N" or "(Warning: N,"
  WARNING_COUNT=$(echo "${RESULT}" | grep -oE 'Warning:[[:space:]]*[0-9]+' | head -1 | grep -oE '[0-9]+' || echo "0")
fi

if [[ -z "${WARNING_COUNT}" ]]; then
  WARNING_COUNT=0
fi

{
  echo "warning-count=${WARNING_COUNT}"
  if [[ ${WARNING_COUNT} -gt 0 ]]; then
    echo "has-warnings=true"
  else
    echo "has-warnings=false"
  fi
} >> "${GITHUB_OUTPUT}"

{
  echo "result<<KUBE_EVENTS_EOF"
  echo "${RESULT}"
  echo "KUBE_EVENTS_EOF"
} >> "${GITHUB_OUTPUT}"

if [[ ${EXIT_CODE} -ne 0 ]]; then
  echo "::error::kube-events encountered an error (exit code: ${EXIT_CODE})"
  exit 1
fi

THRESHOLD="${INPUT_THRESHOLD:-0}"
if [[ ${THRESHOLD} -gt 0 ]] && [[ ${WARNING_COUNT} -gt ${THRESHOLD} ]]; then
  echo "::error::Warning count (${WARNING_COUNT}) exceeds threshold (${THRESHOLD})"
  exit 1
fi
