#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
scripts/package-app.sh "$@"
app="$project_root/build/Codex Sidecar.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
architecture=$(lipo -archs "$app/Contents/MacOS/CodexSidecar")
if [ "$architecture" != arm64 ]; then
    printf '%s\n' 'This release script packages the validated Apple Silicon build only.' >&2
    exit 1
fi
output="$project_root/build/releases/v$version"
mkdir -p "$output"
staging=$(mktemp -d "$project_root/build/release-staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
ditto "$app" "$staging/Codex Sidecar.app"
# Remove debug maps containing local build paths. The linker-generated ad hoc
# signature is retained; this does not add an Apple Developer ID signature.
strip -S "$staging/Codex Sidecar.app/Contents/MacOS/CodexSidecar"
codesign --verify --ignore-resources "$staging/Codex Sidecar.app/Contents/MacOS/CodexSidecar"
cp LICENSE "$staging/LICENSE"
cp docs/INSTALL.md "$staging/INSTALL.md"
asset="Codex-Sidecar-$version-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$staging/Codex Sidecar.app" "$output/$asset"
# Include the license and installation instructions beside the application.
(cd "$staging" && zip -q "$output/$asset" LICENSE INSTALL.md)
(cd "$output" && shasum -a 256 "$asset" > SHA256SUMS.txt)
printf '%s\n' "$output/$asset" "$output/SHA256SUMS.txt"
