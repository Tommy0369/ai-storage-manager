#!/usr/bin/env bash
# P5.0 — package Release candidate .app from SPM executable.
# Does NOT codesign (no secrets). Does NOT notarize.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT_NAME="AI Storage Manager"
BUNDLE_ID="com.tomystudio.aistoragemanager"
VERSION="0.2.0"
BUILD="51"
# Output root. Defaults to dist-0.2 for the current shipping line.
# Frozen v0.1 lives in dist/ and must never be rebuilt (freeze guard below).
DIST="${DIST_DIR:-$ROOT/dist-0.2}"
APP="$DIST/${PRODUCT_NAME}.app"

# Freeze guard: refuse to rebuild over a frozen release artifact.
# v0.1 was frozen at P5.6 (V0_1_GLOBAL_RELEASE_FROZEN). Rebuilding it would
# invalidate its checksum, signature and notarization evidence.
if [[ -f "$DIST/.p55_bundle_freeze_timestamp" && "${ALLOW_FROZEN_OVERWRITE:-0}" != "1" ]]; then
  cat >&2 <<EOF
error: refusing to rebuild into a FROZEN release directory

  $DIST
  frozen at: $(cat "$DIST/.p55_bundle_freeze_timestamp" 2>/dev/null)

This directory holds the frozen, signed and notarized v0.1 artifact.
For next-version development use a separate output:

  bash scripts/package-dev-app.sh

To deliberately override (you almost certainly should not):
  ALLOW_FROZEN_OVERWRITE=1 bash scripts/package-release-app.sh
EOF
  exit 1
fi
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Building Release (ai-storage-manager)"
# Remap absolute source/home paths so developer machine paths do not ship as runtime dependencies.
# Residual truncated debug fragments may still appear; they are not load paths.
swift build -c release --product ai-storage-manager \
  -Xswiftc -debug-prefix-map -Xswiftc "${ROOT}=." \
  -Xswiftc -file-prefix-map -Xswiftc "${ROOT}=." \
  -Xswiftc -debug-prefix-map -Xswiftc "${HOME}=/Users/demo" \
  -Xswiftc -file-prefix-map -Xswiftc "${HOME}=/Users/demo"

BIN="$(swift build -c release --show-bin-path)/ai-storage-manager"
if [[ ! -x "$BIN" ]]; then
  echo "error: missing release binary: $BIN" >&2
  exit 1
fi

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES/Localization"
cp "$BIN" "$MACOS/${PRODUCT_NAME}"
chmod +x "$MACOS/${PRODUCT_NAME}"
cp "$ROOT/packaging/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/packaging/AIStorageManager.entitlements" "$RESOURCES/AIStorageManager.entitlements"

BIN_DIR="$(swift build -c release --show-bin-path)"
# SPM resource bundles must ship beside the executable / in Resources.
# Without these, Bundle.module / offline L10n catalog is missing from Release packages.
for BUNDLE in AIStorageManager_AppServices.bundle AIStorageManager_SafetyCore.bundle; do
  if [[ -d "$BIN_DIR/$BUNDLE" ]]; then
    echo "==> Bundling $BUNDLE"
    rm -rf "$MACOS/$BUNDLE"
    cp -R "$BIN_DIR/$BUNDLE" "$MACOS/$BUNDLE"
  fi
done

# AppServices: flat resource bundle + Info.plist (codesign-friendly).
if [[ -d "$MACOS/AIStorageManager_AppServices.bundle" ]]; then
  cat > "$MACOS/AIStorageManager_AppServices.bundle/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.tomystudio.aistoragemanager.appservices</string>
	<key>CFBundleName</key>
	<string>AIStorageManager_AppServices</string>
	<key>CFBundlePackageType</key>
	<string>BNDL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD}</string>
</dict>
</plist>
PLIST
fi

# SafetyCore: convert SPM flat Resources/ into proper Contents/Resources for codesign.
if [[ -d "$MACOS/AIStorageManager_SafetyCore.bundle" ]]; then
  SC="$MACOS/AIStorageManager_SafetyCore.bundle"
  mkdir -p "$SC/Contents/Resources"
  if [[ -d "$SC/Resources" ]]; then
    # Move SPM resource tree under Contents/Resources
    shopt -s dotglob nullglob
    mv "$SC/Resources"/* "$SC/Contents/Resources/" 2>/dev/null || true
    shopt -u dotglob nullglob
    rm -rf "$SC/Resources"
  fi
  # Strip developer-only trees before sealing.
  rm -rf "$SC/Contents/Resources/knowledge/reports"
  rm -rf "$SC/Contents/Resources/knowledge/source"
  cat > "$SC/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.tomystudio.aistoragemanager.safetycore</string>
	<key>CFBundleName</key>
	<string>AIStorageManager_SafetyCore</string>
	<key>CFBundlePackageType</key>
	<string>BNDL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD}</string>
</dict>
</plist>
PLIST
fi
if [[ -f "$BIN_DIR/AIStorageManager_AppServices.bundle/LocalizationCatalog.json" ]]; then
  cp "$BIN_DIR/AIStorageManager_AppServices.bundle/LocalizationCatalog.json" "$RESOURCES/Localization/LocalizationCatalog.json"
  cp "$BIN_DIR/AIStorageManager_AppServices.bundle/Localizable.xcstrings" "$RESOURCES/Localization/Localizable.xcstrings" 2>/dev/null || true
fi

# v0.2 UX FIX 001 — native macOS menu localization.
#
# AppKit renders the standard app menu (About / Services / Hide / Show All /
# Quit, plus Edit / View / Window / Help) from the BUNDLE's localizations —
# not from anything the app sets at runtime. Without ja.lproj the menu stays
# English on a Japanese Mac no matter what the process does, because SwiftUI
# rebuilds the menu from the bundle after launch.
#
# en + ja only, on purpose: the product UI ships 9 locales, but the native menu
# is Japanese-or-English by design for this fix.
for LOC in en ja; do
  mkdir -p "$RESOURCES/${LOC}.lproj"
  printf '/* Present so macOS localizes the standard app menu for this language. */\n' \
    > "$RESOURCES/${LOC}.lproj/InfoPlist.strings"
done

echo "==> Validating localization resources in packaged .app (required before any signing)"
bash "$ROOT/scripts/validate-localization-bundle.sh" "$APP"

# Keep reports/fixtures OUT of the bundle.
# Do not copy knowledge source trees that are developer-only.
ARCH="$(uname -m)"
FILE_OUT="$(file "$MACOS/${PRODUCT_NAME}" || true)"

# Optional ad-hoc sign for local runnability when no Developer ID exists.
# This is NOT Developer ID / notarization.
# For external distribution: after Developer ID is installed, run:
#   bash scripts/notarize-release.sh
if [[ "${DEV_FORCE_ADHOC:-0}" == "1" ]]; then
  echo "==> DEV build — ad-hoc sign only (never a release artifact)"
  codesign --force --deep --sign - "$APP" || true
  SIGN_STATE="ADHOC_DEV_ONLY"
elif [[ -n "${SIGNING_IDENTITY:-}" ]] || security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  echo "==> Developer ID available — assembling UNSIGNED for scripts/notarize-release.sh"
  SIGN_STATE="UNSIGNED_AWAITING_DEVELOPER_ID_SIGN"
else
  echo "==> No Developer ID — applying ad-hoc sign for local beta only"
  codesign --force --deep --sign - "$APP" || true
  SIGN_STATE="ADHOC_LOCAL_ONLY"
fi

cat > "$DIST/release_manifest.json" <<EOF
{
  "productName": "${PRODUCT_NAME}",
  "version": "${VERSION}",
  "build": "${BUILD}",
  "bundleIdentifier": "${BUNDLE_ID}",
  "architectureHost": "${ARCH}",
  "binaryFile": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$FILE_OUT"),
  "appBundlePath": "${APP}",
  "signState": "${SIGN_STATE}",
  "notarized": false,
  "packaging": "APP_BUNDLE_ZIP_CANDIDATE",
  "minimumMacOS": "13.0",
  "debugFixturesBundled": false,
  "reportsBundled": false
}
EOF

echo "==> Wrote $APP"
echo "==> Wrote $DIST/release_manifest.json"

# Dev builds stop here: no distribution ZIP is produced for non-release output.
if [[ "${DEV_FORCE_ADHOC:-0}" == "1" ]]; then
  exit 0
fi

# Simple ZIP for local beta handoff (not Gatekeeper-ready without Developer ID + notarization)
ZIP="$DIST/AIStorageManager-${VERSION}-rc${BUILD}-arm64.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "==> Wrote $ZIP"
