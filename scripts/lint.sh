#!/usr/bin/env bash
# Lints the Swift sources with the shared .swift-format configuration, as CI does.
# Fix findings with `swift format --in-place --recursive <paths>`.

set -euo pipefail

cd "$(dirname "$0")/.."

paths=(Sources Tests Package.swift)
# Examples joins the lint once it exists.
if [[ -d Examples ]]; then
  paths+=(Examples)
fi

swift format lint --strict --recursive "${paths[@]}"
echo "swift format lint: no findings in ${paths[*]}"
