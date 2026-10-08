#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
swift build -c release "$@"
bin_path=$(swift build -c release --show-bin-path "$@")
contents="$project_root/build/Codex Sidecar.app/Contents"
mkdir -p "$contents/MacOS"
mkdir -p "$contents/Resources"
cp "$bin_path/CodexSidecar" "$contents/MacOS/CodexSidecar"
cp "$project_root/Sources/CodexSidecar/Resources/Info.plist" "$contents/Info.plist"
cp "$project_root/Sources/CodexSidecar/Resources/Icons/AppIcon.icns" "$contents/Resources/AppIcon.icns"
cp -R "$bin_path/CodexSidecar_CodexSidecar.bundle" "$contents/Resources/"
printf '%s\n' "$project_root/build/Codex Sidecar.app"
