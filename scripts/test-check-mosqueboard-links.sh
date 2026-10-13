#!/usr/bin/env bash
# Tests scripts/check-mosqueboard-links.sh: it passes on a build that links SalahCore only, and
# each of its checks fails on a build that breaks it. The builds are made up: a target
# dependency graph like xcodebuild's, binaries of plain text, and a stand-in for nm that prints
# the symbols each case needs. strings, grep, awk and find are the real ones.
#
# Usage: scripts/test-check-mosqueboard-links.sh

set -euo pipefail

cd "$(dirname "$0")/.."

check="${PWD}/scripts/check-mosqueboard-links.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# The stand-in nm prints the case's symbols, whatever binary it's given.
mkdir -p "${work}/bin"
cat >"${work}/bin/nm" <<'NM'
#!/usr/bin/env bash
cat "${FAKE_SYMBOLS}"
NM
chmod +x "${work}/bin/nm"

core_symbol='0000000000001000 T _$s9SalahCore12PrayerSourceMp'
times_symbol='0000000000002000 T _$s10SalahTimes17CalculationMethodO'
calculation_symbol='0000000000003000 T _$s16SalahCalculation17CalculationSourceV'

# xcodebuild's target dependency graph for MosqueBoard, with any extra SalahKit targets.
graph() {
  echo "note: Target dependency graph ($((3 + $#)) targets)"
  echo "    Target 'MosqueBoard' in project 'MosqueBoard'"
  echo "        ➜ Explicit dependency on target 'SalahCore-product' in project 'SalahKit'"
  echo "    Target 'SalahCore-product' in project 'SalahKit'"
  echo "        ➜ Explicit dependency on target 'SalahCore' in project 'SalahKit'"
  echo "    Target 'SalahCore' in project 'SalahKit' (no dependencies)"
  for target in "$@"; do
    echo "    Target '${target}' in project 'SalahKit' (no dependencies)"
  done
  echo
  echo "Build description signature: 0"
}

# Many printable strings, so that strings is still writing long after an early match.
filler() {
  awk 'BEGIN { for (i = 0; i < 20000; i++) printf "MosqueBoard string %05d\n", i }'
}

cases=0
failures=0

# Makes a new case: a build that links SalahCore only. The case then breaks one thing.
new_case() {
  cases=$((cases + 1))
  dir="${work}/case-${cases}"
  products="${dir}/Debug-iphonesimulator"
  binary="${products}/MosqueBoard.app/MosqueBoard.debug.dylib"
  mkdir -p "${products}/MosqueBoard.app"
  graph >"${dir}/build.log"
  filler >"${binary}"
  echo "${core_symbol}" >"${dir}/symbols"
}

# Runs the check on the case. `expected` is `pass`, or the error the check must report.
expect() {
  local name="$1" expected="$2" output status=0
  output="$(PATH="${work}/bin:${PATH}" FAKE_SYMBOLS="${dir}/symbols" \
    "${check}" "${dir}/build.log" "${products}" 2>&1)" || status=$?
  if [[ "${expected}" == pass && ${status} -eq 0 ]] \
    || [[ "${expected}" != pass && ${status} -ne 0 && "${output}" == *"error: "*"${expected}"* ]]; then
    echo "ok: ${name}"
  else
    echo "FAILED: ${name}: expected ${expected}; the check exited ${status} and printed:" >&2
    echo "${output}" >&2
    failures=$((failures + 1))
  fi
}

new_case
expect "a build that links SalahCore only passes" pass

new_case
graph SalahTimes >"${dir}/build.log"
expect "a SalahTimes target in the build graph" \
  "the build graph has a SalahCalculation or SalahTimes target"

new_case
graph SalahCalculation >"${dir}/build.log"
expect "a SalahCalculation target in the build graph" \
  "the build graph has a SalahCalculation or SalahTimes target"

new_case
echo "** BUILD SUCCEEDED **" >"${dir}/build.log"
expect "a log without a build graph" "no target dependency graph"

new_case
echo "${times_symbol}" >>"${dir}/symbols"
expect "SalahTimes symbols" "has SalahTimes symbols"

new_case
echo "${calculation_symbol}" >>"${dir}/symbols"
expect "SalahCalculation symbols" "has SalahCalculation symbols"

new_case
: >"${dir}/symbols"
expect "no SalahCore symbols" "no SalahCore symbols"

# A match among the first strings: a `strings | grep -q` pipe under pipefail missed this one.
new_case
{
  echo "SalahTimes 0.1.0"
  filler
} >"${binary}"
expect "a string naming SalahTimes before 20,000 others" "mentions SalahCalculation or SalahTimes"

new_case
{
  filler
  echo "SalahCalculation"
} >"${binary}"
expect "a string naming SalahCalculation after 20,000 others" \
  "mentions SalahCalculation or SalahTimes"

new_case
: >"${products}/SalahTimes.o"
expect "SalahTimes build output in the products" \
  "the products hold SalahCalculation or SalahTimes build output"

new_case
mv "${binary}" "${dir}/moved.dylib"
expect "an app without its binary" "no MosqueBoard binary"

if [[ ${failures} -ne 0 ]]; then
  echo "${failures} of ${cases} cases failed." >&2
  exit 1
fi
echo "All ${cases} cases passed."
