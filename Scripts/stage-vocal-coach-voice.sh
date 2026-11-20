#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
archive="${1:-$HOME/Documents/Projects/PageHum/.build/releases/pagehum-0.1.0-macOS-arm64.tar.gz}"
destination="$repo/Sources/VocalCoach/PageHumVoice"
if [ -x "$destination/pagehum" ]; then
    printf 'PageHum voice is already staged.\n'
    exit 0
fi
if [ ! -f "$archive" ] || [ ! -f "$archive.sha256" ]; then
    printf 'Provide the PageHum Apple Silicon CLI archive and its companion .sha256 file.\n' >&2
    exit 1
fi
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
(cd "$(dirname "$archive")" && shasum -a 256 -c "$(basename "$archive").sha256")
staging="$(mktemp -d "$repo/Sources/VocalCoach/.voice-stage.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
tar -xzf "$archive" -C "$staging"
test -x "$staging/pagehum/pagehum"
test -d "$staging/pagehum/PackageFrameworks"
test -f "$staging/pagehum/pagehum-resources.bundle/Contents/Resources/kokoro-v1_0.safetensors"
mv "$staging/pagehum" "$destination"
printf 'Staged the offline Kokoro voice runtime.\n'
