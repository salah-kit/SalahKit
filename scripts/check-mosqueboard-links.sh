#!/usr/bin/env bash
# Proves that MosqueBoard, the published-timetable example, builds and links SalahCore and
# nothing that calculates: neither the SalahCalculation product nor SalahTimes, although the
# package graph resolves SalahTimes. An app that shows published times needs no calculation code.
#
# Usage: scripts/check-mosqueboard-links.sh <xcodebuild-log> <products-directory>
#   xcodebuild-log      the output of an `xcodebuild build` or `build-for-testing` of MosqueBoard
#   products-directory  its Build/Products/<configuration>-<platform> directory
#
# 1. The build graph: xcodebuild's "Target dependency graph" must list SalahCore and no target
#    of SalahCalculation or SalahTimes.
# 2. The binary: the app's executable code must carry SalahCore's Swift symbols, none of
#    SalahCalculation's or SalahTimes' and no string naming either, and the products must hold
#    no object or module of them.
#
# scripts/test-check-mosqueboard-links.sh tests each of these checks.

set -euo pipefail

log="${1:?usage: scripts/check-mosqueboard-links.sh <xcodebuild-log> <products-directory>}"
products="${2:?usage: scripts/check-mosqueboard-links.sh <xcodebuild-log> <products-directory>}"
app="${products}/MosqueBoard.app"
failed=0

fail() {
  echo "error: $*" >&2
  failed=1
}

# 1. The build graph.
graph="$(awk '/Target dependency graph/ {printing = 1} printing && /^$/ {exit} printing' "${log}")"
if [[ -z "${graph}" ]]; then
  fail "no target dependency graph in ${log}"
else
  echo "${graph}"
  grep -q "Target 'SalahCore' in project 'SalahKit'" <<<"${graph}" \
    || fail "the build graph has no SalahCore target"
  if grep -E "Target '(SalahCalculation|SalahTimes)[^']*'" <<<"${graph}"; then
    fail "the build graph has a SalahCalculation or SalahTimes target"
  fi
fi

# 2. The binary. Debug builds keep the app's code in MosqueBoard.debug.dylib; Release builds in
# the executable. Swift symbols carry their module's name with its length: 9SalahCore,
# 16SalahCalculation, 10SalahTimes.
binaries=()
for candidate in "${app}/MosqueBoard" "${app}/MosqueBoard.debug.dylib"; do
  [[ -f "${candidate}" ]] && binaries+=("${candidate}")
done
if [[ ${#binaries[@]} -eq 0 ]]; then
  fail "no MosqueBoard binary in ${app}"
fi
core=0
# The `+` form expands to nothing for an empty array, which bash 3.2 (macOS) rejects under `set -u`.
for binary in ${binaries[@]+"${binaries[@]}"}; do
  symbols="$(nm "${binary}" 2>/dev/null || true)"
  count_core="$(grep -c '9SalahCore' <<<"${symbols}" || true)"
  count_calculation="$(grep -c '16SalahCalculation' <<<"${symbols}" || true)"
  count_times="$(grep -c '10SalahTimes' <<<"${symbols}" || true)"
  # All of the strings are read before they're searched. In `strings | grep -q`, grep would exit
  # at the first match, and the SIGPIPE that stops strings would make pipefail fail the pipe,
  # which would turn the match into a pass.
  text="$(strings -a "${binary}")"
  count_mentions="$(grep -c -E 'SalahCalculation|SalahTimes' <<<"${text}" || true)"
  echo "${binary#"${products}/"}: SalahCore ${count_core}, SalahCalculation ${count_calculation}, SalahTimes ${count_times} symbols; ${count_mentions} strings naming either"
  core=$((core + count_core))
  [[ "${count_calculation}" -eq 0 ]] || fail "${binary} has SalahCalculation symbols"
  [[ "${count_times}" -eq 0 ]] || fail "${binary} has SalahTimes symbols"
  [[ "${count_mentions}" -eq 0 ]] || fail "${binary} mentions SalahCalculation or SalahTimes"
done
[[ "${core}" -gt 0 ]] || fail "no SalahCore symbols: the check would prove nothing"

stray="$(find "${products}" \( -iname '*SalahCalculation*' -o -iname '*SalahTimes*' \) -print)"
if [[ -n "${stray}" ]]; then
  echo "${stray}"
  fail "the products hold SalahCalculation or SalahTimes build output"
fi

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi
echo "MosqueBoard links SalahCore only: no SalahCalculation or SalahTimes in its build graph or binary."
