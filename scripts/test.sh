#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/build"
xcrun swiftc -swift-version 5 -parse-as-library \
  "$PROJECT_DIR/Sources/CleanupCore.swift" "$PROJECT_DIR/Tests/CoreTests.swift" \
  -o "$PROJECT_DIR/build/core-tests"
"$PROJECT_DIR/build/core-tests" "$@"
if [[ "${1:-}" != "--scan-only" ]]; then
  xcrun swiftc -swift-version 5 -parse-as-library \
    "$PROJECT_DIR/Sources/FileReviewCore.swift" "$PROJECT_DIR/Tests/FileReviewTests.swift" \
    -o "$PROJECT_DIR/build/file-review-tests"
  "$PROJECT_DIR/build/file-review-tests"
fi
