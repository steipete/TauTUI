#!/usr/bin/env bash
set -euo pipefail

# Select the toolchain for this process, without changing the runner's global Xcode.
selected=''
while IFS= read -r candidate; do
  toolchain_version=$(DEVELOPER_DIR="$candidate/Contents/Developer" xcrun swift --version 2>/dev/null || true)
  if [[ "$toolchain_version" =~ Swift\ version\ ([0-9]+)\.([0-9]+) ]] &&
    (( BASH_REMATCH[1] == 6 && BASH_REMATCH[2] >= 2 )); then
    selected="$candidate/Contents/Developer"
    break
  fi
done < <(find /Applications -maxdepth 1 \( -type d -o -type l \) -name 'Xcode*.app' -print | sort -Vr)
[[ -n "$selected" ]] || { echo 'No installed Xcode provides Swift 6.2 or newer Swift 6' >&2; exit 1; }
export DEVELOPER_DIR="$selected"
swift --version
swift build --configuration release --jobs 2
swift test --jobs 2
