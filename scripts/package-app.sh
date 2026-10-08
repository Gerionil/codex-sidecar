#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
swift build -c release "$@"
bin_path=$(swift build -c release --show-bin-path "$@")
contents="$project_root/build/Codex Sidecar.app/Contents"
mkdir -p "$contents/MacOS"
cp "$bin_path/CodexSidecar" "$contents/MacOS/CodexSidecar"
cp "$project_root/Sources/CodexSidecar/Resources/Info.plist" "$contents/Info.plist"
printf '%s\n' "$project_root/build/Codex Sidecar.app"
