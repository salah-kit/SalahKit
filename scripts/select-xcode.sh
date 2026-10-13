#!/usr/bin/env bash
# Selects the newest Xcode 26 installed on a GitHub-hosted macOS runner.
#
# Hosted runners offer Xcode 26 at most (docs/rfcs/0001-core.md, section 6.4), and the image's
# default Xcode can be older than the newest one installed. Locally, keep your own selection.

set -euo pipefail

newest="$(find /Applications -maxdepth 1 -name 'Xcode_26*.app' | sort -V | tail -n 1)"
if [[ -z "${newest}" ]]; then
  echo "error: no Xcode 26 in /Applications" >&2
  exit 1
fi
echo "Selecting ${newest}"
sudo xcode-select -s "${newest}"
xcodebuild -version
swift --version
