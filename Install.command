#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple Command Line Tools are needed to build this app."
  echo "Install them with: xcode-select --install"
  echo "This can be a large download. The already-built app needs no compiler."
  read -r -p "Press Return to close. "
  exit 1
fi
if pgrep -x MacCleanup >/dev/null; then
  echo "Quit Pankaj Mac Cleanup before rebuilding it."
  read -r -p "Press Return to close. "
  exit 1
fi
bash "$PROJECT_DIR/scripts/test.sh"
bash "$PROJECT_DIR/scripts/build.sh"
mkdir -p "$HOME/Applications"
ditto "$PROJECT_DIR/build/Pankaj Mac Cleanup.app" "$HOME/Applications/Pankaj Mac Cleanup.app"
xattr -cr "$HOME/Applications/Pankaj Mac Cleanup.app"
codesign --verify --deep --strict "$HOME/Applications/Pankaj Mac Cleanup.app"
open "$HOME/Applications/Pankaj Mac Cleanup.app"
echo "Installed in your Applications folder. No cleanup has been performed."
