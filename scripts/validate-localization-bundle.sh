#!/usr/bin/env bash
# P5.5 — validate localization resources inside an ACTUAL .app bundle.
# Fails non-zero if translations exist only in the repo (historical English-only packaging bug).
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: $0 /path/to/AI Storage Manager.app" >&2
  exit 1
fi

EXPECTED=(en ja zh-Hans zh-Hant ko es fr de pt-BR)
CATALOG=""
for CANDIDATE in \
  "$APP/Contents/Resources/Localization/LocalizationCatalog.json" \
  "$APP/Contents/MacOS/AIStorageManager_AppServices.bundle/LocalizationCatalog.json" \
  "$APP/Contents/MacOS/AIStorageManager_AppServices.bundle/Localization/LocalizationCatalog.json"
do
  if [[ -f "$CANDIDATE" ]]; then
    CATALOG="$CANDIDATE"
    break
  fi
done

if [[ -z "$CATALOG" ]]; then
  cat >&2 <<'EOF'
SHIPPING_APP_LOCALIZATION_RESOURCES_PRESENT=false
error: LocalizationCatalog.json missing from packaged .app
This is the historical English-only packaging regression.
Refuse signing/notarization until packaging includes localization runtime resources.
EOF
  exit 1
fi

python3 - "$CATALOG" <<'PY'
import json, sys
path = sys.argv[1]
expected = ["en", "ja", "zh-Hans", "zh-Hant", "ko", "es", "fr", "de", "pt-BR"]
obj = json.load(open(path, encoding="utf-8"))
locales = obj.get("locales") or []
strings = obj.get("strings") or {}
if not strings:
    print("error: empty localization catalog", file=sys.stderr)
    sys.exit(1)
missing = [l for l in expected if l not in locales]
if missing:
    print("error: missingPackagedLocales=" + ",".join(missing), file=sys.stderr)
    sys.exit(1)
# Sample critical keys must exist and differ for ja vs en
for key in ("decision.keep.title", "navigation.settings", "action.moveToTrash.title"):
    row = strings.get(key)
    if not row:
        print(f"error: missing key {key}", file=sys.stderr)
        sys.exit(1)
    for loc in expected:
        if not (row.get(loc) or "").strip():
            print(f"error: empty translation {key}/{loc}", file=sys.stderr)
            sys.exit(1)
    if row.get("ja") == row.get("en"):
        print(f"error: ja equals en for critical key {key}", file=sys.stderr)
        sys.exit(1)
print("SHIPPING_APP_LOCALIZATION_RESOURCES_PRESENT=true")
print("catalog=" + path)
print("packagedLocales=" + ",".join(locales))
print("totalKeys=" + str(len(strings)))
print("missingPackagedLocales=0")
PY

# Bundle cleanliness: no QA reports, screenshots, git, credentials.
BAD=0
while IFS= read -r hit; do
  echo "error: unexpected path inside app: $hit" >&2
  BAD=1
done < <(find "$APP" \( \
  -path '*/reports/case001/*' \
  -o -path '*/screenshots/*' \
  -o -path '*/.git/*' \
  -o -path '*/knowledge/reports/*' \
  -o -name 'credentials.json' \
  -o -name '*.p12' \
  -o -name 'AuthKey_*.p8' \
\) -print 2>/dev/null || true)
if [[ "$BAD" -ne 0 ]]; then
  exit 1
fi

echo "localization_bundle_validation=PASS"
exit 0
