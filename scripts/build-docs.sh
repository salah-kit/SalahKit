#!/usr/bin/env bash
# Builds the SalahKit documentation site without a package dependency (STANDARD.md, Documentation):
#   1. `xcodebuild docbuild` builds one .doccarchive per module;
#   2. `xcrun docc merge` combines them into one archive;
#   3. `xcrun docc process-archive transform-for-static-hosting` turns it into a static site.
#
# Usage: scripts/build-docs.sh [output-directory]
#   output-directory  where the site goes (default: .build/docs-site)
#
# Environment:
#   DERIVED_DATA_PATH  xcodebuild's derived data (default: .derived/docs)
#   HOSTING_BASE_PATH  the site's base path (default: SalahKit, for salah-kit.github.io/SalahKit)
#   DOCC_STRICT        1 (default) fails the build on any DocC warning, such as an unresolved
#                      link; 0 reports warnings without failing, for a local preview only.

set -euo pipefail

cd "$(dirname "$0")/.."

readonly modules=(SalahCore SalahCalculation SalahFixtures SalahAlerts SalahWidgets SalahUI)
readonly site_dir="${1:-.build/docs-site}"
readonly derived_data="${DERIVED_DATA_PATH:-.derived/docs}"
readonly hosting_base_path="${HOSTING_BASE_PATH:-SalahKit}"
readonly work_dir=".build/docs-work"
readonly log_file="${work_dir}/docbuild.log"
docc_flags=""
if [[ "${DOCC_STRICT:-1}" != "0" ]]; then
  docc_flags="--warnings-as-errors"
fi

mkdir -p "${work_dir}"
# Start from empty outputs so a stale archive or page can't hide a failure.
for stale in "${work_dir}/SalahKit.doccarchive" "${site_dir}"; do
  if [[ -e "${stale}" ]]; then
    rm -r -- "${stale}"
  fi
done

echo "==> Building documentation archives"
set +e
xcodebuild docbuild \
  -scheme SalahKit-Package \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${derived_data}" \
  -skipPackagePluginValidation \
  OTHER_DOCC_FLAGS="${docc_flags}" \
  2>&1 | tee "${log_file}"
status=${PIPESTATUS[0]}
set -e
if [[ ${status} -ne 0 ]]; then
  echo "error: xcodebuild docbuild failed (${status})" >&2
  exit "${status}"
fi

archives=()
for module in "${modules[@]}"; do
  archive="$(find "${derived_data}/Build/Products" -type d -name "${module}.doccarchive" -prune | head -n 1)"
  if [[ -z "${archive}" ]]; then
    echo "error: no archive for ${module} under ${derived_data}/Build/Products" >&2
    exit 1
  fi
  echo "    ${module}: ${archive}"
  archives+=("${archive}")
done

echo "==> Merging archives"
xcrun docc merge "${archives[@]}" \
  --synthesized-landing-page-name SalahKit \
  --synthesized-landing-page-kind Package \
  --output-path "${work_dir}/SalahKit.doccarchive"

echo "==> Transforming for static hosting at /${hosting_base_path}"
xcrun docc process-archive transform-for-static-hosting "${work_dir}/SalahKit.doccarchive" \
  --hosting-base-path "${hosting_base_path}" \
  --output-path "${site_dir}"

# A root page that sends visitors to the documentation landing page.
cat >"${site_dir}/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>SalahKit documentation</title>
<meta http-equiv="refresh" content="0; url=/${hosting_base_path}/documentation/">
<link rel="canonical" href="/${hosting_base_path}/documentation/">
</head>
<body><p><a href="/${hosting_base_path}/documentation/">SalahKit documentation</a></p></body>
</html>
HTML

for module in "${modules[@]}"; do
  lower="$(echo "${module}" | tr '[:upper:]' '[:lower:]')"
  if [[ ! -f "${site_dir}/documentation/${lower}/index.html" ]]; then
    echo "error: the site has no page for ${module}" >&2
    exit 1
  fi
done

echo "==> Site ready in ${site_dir}"
