#!/usr/bin/env bash
# Builds every package product for one Apple platform's generic simulator destination.
#
# Usage: scripts/build-apple-platform.sh "<platform>"   e.g. "iOS Simulator", "visionOS Simulator"
#
# Environment:
#   DERIVED_DATA_PATH  xcodebuild's derived data (default: .derived/platforms)
#
# When the selected Xcode lacks the platform's SDK, the build is skipped with a warning
# rather than failed, as STANDARD.md (CI) asks of checks that hosted runners can't run.

set -euo pipefail

cd "$(dirname "$0")/.."

platform="${1:?usage: scripts/build-apple-platform.sh \"<platform>\"}"
derived_data="${DERIVED_DATA_PATH:-.derived/platforms}"

case "${platform}" in
  "iOS Simulator") sdk=iphonesimulator ;;
  "watchOS Simulator") sdk=watchsimulator ;;
  "tvOS Simulator") sdk=appletvsimulator ;;
  "visionOS Simulator") sdk=xrsimulator ;;
  *)
    echo "error: unknown platform '${platform}'" >&2
    exit 2
    ;;
esac

if ! xcodebuild -showsdks 2>/dev/null | grep -q -- "-sdk ${sdk}"; then
  message="the selected Xcode has no ${platform} SDK; skipping its build"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::warning title=${platform} skipped::${message}"
  else
    echo "warning: ${message}" >&2
  fi
  exit 0
fi

xcodebuild build \
  -scheme SalahKit-Package \
  -destination "generic/platform=${platform}" \
  -derivedDataPath "${derived_data}" \
  -skipPackagePluginValidation \
  -quiet
echo "${platform}: build succeeded"
