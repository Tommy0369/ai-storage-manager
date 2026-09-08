#!/usr/bin/env bash
# P5.1 — Developer ID sign → notarize → staple → Gatekeeper → final ZIP
#
# Secrets NEVER live in this file.
# Provide via environment / keychain only:
#   SIGNING_IDENTITY   e.g. "Developer ID Application: Example Corp (TEAMID)"
#   NOTARY_PROFILE     e.g. AIStorageManagerNotary  (notarytool keychain profile name)
#
# Exit codes:
#   0  EXTERNAL_DISTRIBUTION_READY
#   2  SIGNING_IDENTITY_REQUIRED
#   3  NOTARIZATION_CREDENTIALS_REQUIRED
#   4  NOTARIZATION_REJECTED / GATEKEEPER_REJECTED / RELEASE_BLOCKED
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT_NAME="AI Storage Manager"
VERSION="${RELEASE_VERSION:-0.2.0}"
BUILD="${RELEASE_BUILD:-51}"
DIST="${DIST_DIR:-$ROOT/dist-0.2}"
APP="$DIST/${PRODUCT_NAME}.app"
NOTARY_ZIP="$DIST/AIStorageManager-${VERSION}-rc${BUILD}-arm64-notary.zip"
FINAL_ZIP="$DIST/AIStorageManager-${VERSION}-rc${BUILD}-arm64.zip"
MANIFEST="$DIST/release-manifest.json"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AIStorageManagerNotary}"

die() { echo "error: $*" >&2; exit 4; }
need_identity() {
  cat >&2 <<'EOF'
P5_1_STATUS=SIGNING_IDENTITY_REQUIRED

Install a valid Developer ID Application certificate
associated with the Apple Developer team into the login
keychain, then rerun P5.1.

  security find-identity -v -p codesigning
  # expect: Developer ID Application: <NAME> (<TEAM_ID>)

Then:
  export SIGNING_IDENTITY='Developer ID Application: <NAME> (<TEAM_ID>)'
  bash scripts/package-release-app.sh
  bash scripts/notarize-release.sh
EOF
  exit 2
}

need_credentials() {
  cat >&2 <<EOF
P5_1_STATUS=NOTARIZATION_CREDENTIALS_REQUIRED

Store notarization credentials in the keychain (do not put secrets in repo):

  xcrun notarytool store-credentials "${NOTARY_PROFILE}"

Use App Store Connect API key, or Apple ID + app-specific password + Team ID.
Then:

  export SIGNING_IDENTITY='Developer ID Application: <NAME> (<TEAM_ID>)'
  export NOTARY_PROFILE='${NOTARY_PROFILE}'
  bash scripts/notarize-release.sh
EOF
  exit 3
}

echo "==> P5.1 notarize-release"

if [[ ! -d "$APP" ]]; then
  die "missing app bundle: $APP — run scripts/package-release-app.sh first"
fi

# Discover Developer ID if not provided
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1 || true)"
  COUNT="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | sort -u | wc -l | tr -d ' ')"
  if [[ "${COUNT}" -gt 1 ]]; then
    die "multiple distinct Developer ID Application identities; set SIGNING_IDENTITY explicitly"
  fi
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    need_identity
  fi
fi

if ! security find-identity -v -p codesigning 2>/dev/null | grep -F "$SIGNING_IDENTITY" >/dev/null; then
  need_identity
fi

# Credential probe — profile name is not secret; failure means manual setup
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  need_credentials
fi

echo "==> Localization bundle validation (NO_RELEASE_SIGNING_WITHOUT_LOCALIZATION_BUNDLE_VALIDATION)"
bash "$ROOT/scripts/validate-localization-bundle.sh" "$APP"

echo "==> Signing with Developer ID + hardened runtime (inside-out)"
# Nested resource bundles must be signed before the outer app.
while IFS= read -r -d '' nested; do
  echo "    nested bundle: $nested"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$nested"
done < <(find "$APP/Contents" -name '*.bundle' -print0 2>/dev/null || true)

while IFS= read -r -d '' nested; do
  echo "    nested: $nested"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$nested"
done < <(find "$APP/Contents" \( -name '*.dylib' -o -name '*.framework' -o -name '*.appex' -o -name '*.xpc' \) -print0 2>/dev/null || true)

codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  --entitlements "$ROOT/packaging/AIStorageManager.entitlements" \
  "$APP"
echo "==> codesign verify"
codesign --verify --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | sed -n '1,40p'

echo "==> entitlements (expect empty / minimal)"
codesign -d --entitlements :- "$APP" 2>/dev/null || true

echo "==> notarization ZIP (submission only)"
rm -f "$NOTARY_ZIP"
ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"

echo "==> notarytool submit --wait"
SUBMIT_OUT="$(mktemp)"
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json | tee "$SUBMIT_OUT"

STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$SUBMIT_OUT" 2>/dev/null || true)"
SUB_ID="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("id") or d.get("submissionId") or "")' "$SUBMIT_OUT" 2>/dev/null || true)"

if [[ "${STATUS}" != "Accepted" ]]; then
  echo "notarization status: ${STATUS:-unknown}" >&2
  if [[ -n "$SUB_ID" ]]; then
    xcrun notarytool log "$SUB_ID" --keychain-profile "$NOTARY_PROFILE" || true
  fi
  die "NOTARIZATION_REJECTED"
fi

echo "==> staple app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Gatekeeper assess"
spctl --assess --type execute --verbose=4 "$APP"

echo "==> final ZIP from stapled app"
rm -f "$FINAL_ZIP"
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"
rm -f "$NOTARY_ZIP"

ZIP_BYTES="$(wc -c < "$FINAL_ZIP" | tr -d ' ')"
ZIP_SHA="$(shasum -a 256 "$FINAL_ZIP" | awk '{print $1}')"
TEAM_ID="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"

python3 - <<PY
import json, datetime, subprocess, hashlib
from pathlib import Path

app = Path("${APP}")
catalog = app / "Contents/Resources/Localization/LocalizationCatalog.json"
if not catalog.exists():
    catalog = app / "Contents/MacOS/AIStorageManager_AppServices.bundle/LocalizationCatalog.json"
locales = []
missing = []
expected = ["en", "ja", "zh-Hans", "zh-Hant", "ko", "es", "fr", "de", "pt-BR"]
if catalog.exists():
    obj = json.loads(catalog.read_text(encoding="utf-8"))
    locales = obj.get("locales") or []
    missing = [l for l in expected if l not in locales]

manifest = {
  "productName": "${PRODUCT_NAME}",
  "releaseVersion": "${VERSION}",
  "version": "${VERSION}",
  "buildNumber": "${BUILD}",
  "build": "${BUILD}",
  "bundleIdentifier": "com.tomystudio.aistoragemanager",
  "bundleID": "com.tomystudio.aistoragemanager",
  "minimumMacOS": "13.0",
  "architecture": ["arm64"],
  "supportedLocales": expected,
  "packagedLocales": locales,
  "missingPackagedLocales": missing,
  "localizationResourceVerified": catalog.exists() and len(missing) == 0,
  "appPath": "${APP}",
  "zipPath": "${FINAL_ZIP}",
  "zipBytes": int("${ZIP_BYTES}"),
  "zipSHA256": "${ZIP_SHA}",
  "signingIdentityType": "Developer ID Application",
  "teamID": "${TEAM_ID}" or None,
  "hardenedRuntime": True,
  "codesignVerified": True,
  "notarizationStatus": "Accepted",
  "notarizationSubmissionID": "${SUB_ID}" or None,
  "stapled": True,
  "stapleValidated": True,
  "gatekeeperAccepted": True,
  "zipReextractValidated": False,
  "extractedLocalizationValidated": False,
  "p5_5_status": "PENDING_ZIP_REEXTRACT",
  "generatedAt": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
}
Path("${MANIFEST}").write_text(json.dumps(manifest, indent=2) + "\n")
print("wrote", "${MANIFEST}")
PY

echo "P5_1_STATUS=EXTERNAL_DISTRIBUTION_READY"
echo "P5_5_STATUS=SIGNED_NOTARIZED_STAPLED_PENDING_REEXTRACT"
echo "zipSHA256=${ZIP_SHA}"
exit 0
