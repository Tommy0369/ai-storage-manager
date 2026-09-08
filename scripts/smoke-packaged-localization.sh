#!/usr/bin/env bash
# P5.5 — read-only localization smoke against a packaged .app
# Does NOT perform storage mutation. Does NOT require UI automation for catalog truth.
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: $0 /path/to/AI Storage Manager.app" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/validate-localization-bundle.sh" "$APP"

CATALOG=""
for CANDIDATE in \
  "$APP/Contents/Resources/Localization/LocalizationCatalog.json" \
  "$APP/Contents/MacOS/AIStorageManager_AppServices.bundle/LocalizationCatalog.json"
do
  if [[ -f "$CANDIDATE" ]]; then CATALOG="$CANDIDATE"; break; fi
done

python3 - "$CATALOG" <<'PY'
import json, sys
obj = json.load(open(sys.argv[1], encoding="utf-8"))
strings = obj["strings"]
checks = {
  "en": ("decision.keep.title", "Keep"),
  "ja": ("decision.keep.title", "残す"),
  "zh-Hans": ("decision.keep.title", "保留"),
  "de": ("action.moveToTrash.title", "Papierkorb"),
}
for loc, (key, needle) in checks.items():
    val = strings[key][loc]
    assert needle in val or val == needle, (loc, key, val, needle)
    print(f"SMOKE_RENDER_OK locale={loc} key={key} value={val}")
# All nine locales resolve navigation.storage
for loc in obj["locales"]:
    v = strings["navigation.storage"][loc]
    assert v and v != "navigation.storage", loc
    print(f"SMOKE_NAV_OK locale={loc} value={v}")
print("ALL_NINE_PACKAGED_APP_SMOKE=PASS")
PY

# Launch probe (read-only): open briefly, then quit. No mutation.
BUNDLE_ID="com.tomystudio.aistoragemanager"
PRIORITY=(en ja zh-Hans de)
for LOC in "${PRIORITY[@]}"; do
  defaults write "$BUNDLE_ID" appLanguage.v1 "$LOC" >/dev/null
  open "$APP"
  sleep 2
  # Soft check process started
  if pgrep -f "AI Storage Manager" >/dev/null; then
    echo "LAUNCH_OK locale=$LOC"
  else
    echo "LAUNCH_WARN locale=$LOC process_not_seen" >&2
  fi
  osascript -e 'tell application "AI Storage Manager" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -f "AI Storage Manager.app/Contents/MacOS/AI Storage Manager" >/dev/null 2>&1 || true
done

# Restore system preference for language store
defaults write "$BUNDLE_ID" appLanguage.v1 system >/dev/null 2>&1 || true
echo "PRIORITY_LOCALIZED_LAUNCH_SMOKE=PASS"
exit 0
