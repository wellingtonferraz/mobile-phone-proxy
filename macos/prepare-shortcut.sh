#!/usr/bin/env bash
# Sign a readable source plist locally; never execute the resulting shortcut.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
command -v shortcuts >/dev/null || { echo 'Requires the Shortcuts app/CLI on macOS.' >&2; exit 1; }
output="$repo_dir/ios/MobilePhoneProxy/Rotate IP.shortcut"
shortcuts sign --mode anyone --input "$repo_dir/shortcuts/Rotate IP.plist" --output "$output"
echo "Prepared $output. Import it on your iPhone, or regenerate the Xcode project to include it in the app."
echo 'No shortcut was executed. The signed file is ignored by Git.'
