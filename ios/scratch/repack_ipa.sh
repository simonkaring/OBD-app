#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Regenerating Xcode project with make_xcodeproj.py..."
python3 scratch/make_xcodeproj.py

echo "==> Archiving VoltLink for iOS..."
xcodebuild -scheme VoltLink \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  archive \
  -archivePath ./build/VoltLink.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

echo "==> Packaging VoltLink.ipa..."
rm -rf build/Payload
mkdir -p build/Payload
cp -R build/VoltLink.xcarchive/Products/Applications/VoltLink.app build/Payload/
(cd build && rm -f VoltLink.ipa && zip -qr VoltLink.ipa Payload)
rm -rf build/Payload

echo "==> Done: build/VoltLink.ipa ($(ls -lh build/VoltLink.ipa | awk '{print $5}'))"
