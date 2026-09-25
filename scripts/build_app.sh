#!/bin/bash
# Build FaceUnlock.app from the SwiftPM package and sign it.
#
# The app is signed with a real Apple Development certificate rather than ad-hoc.
# That matters: macOS records camera permission against the code signature, and an
# ad-hoc signature gets a fresh hash on every build, so each rebuild would look
# like a brand-new app and macOS would ask for camera access again. A stable
# identity is granted once.
#
# If the face model has been placed at Model/FaceEmbedding.mlpackage (see
# docs/MODEL.md), it is compiled into the bundle. Without it the app still builds
# and runs; it just reports that no model is installed and does nothing.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

CONFIG="release"
APP="build/FaceUnlock.app"
CONTENTS="$APP/Contents"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/FaceUnlock"

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/FaceUnlock"
cp scripts/Info.plist "$CONTENTS/Info.plist"

# Compile the Core ML model into the bundle if it is present.
if [ -d "Model/FaceEmbedding.mlpackage" ]; then
    echo "Compiling Core ML model…"
    xcrun coremlcompiler compile "Model/FaceEmbedding.mlpackage" "$CONTENTS/Resources"
elif [ -d "Model/FaceEmbedding.mlmodelc" ]; then
    cp -R "Model/FaceEmbedding.mlmodelc" "$CONTENTS/Resources/"
else
    echo "No model found at Model/FaceEmbedding.mlpackage — building without it."
    echo "The app will run and detect faces but report 'model not installed'."
fi

# Prefer a real identity; fall back to ad-hoc so the script still works without one.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Apple Development" | head -1 | awk '{print $2}')
if [ -z "$IDENTITY" ]; then
    echo "No Apple Development certificate found — signing ad-hoc."
    echo "macOS will ask for camera access again after each rebuild."
    IDENTITY="-"
fi

echo "Signing with ${IDENTITY}…"
codesign --force --options runtime \
    --entitlements scripts/FaceUnlock.entitlements \
    --sign "$IDENTITY" --timestamp=none \
    "$APP"

echo "Verifying signature…"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier" || true

echo
echo "Built $APP"
echo "Run it with:  open $APP"
