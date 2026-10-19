#!/usr/bin/env bash
set -euo pipefail

swift --version
swift build --configuration release --jobs 2
swift test --jobs 2
