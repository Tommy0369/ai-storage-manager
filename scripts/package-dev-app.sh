#!/usr/bin/env bash
# v0.2 development packaging.
#
# Builds an ad-hoc signed .app into dist-dev/ for local UX work.
# NEVER touches dist/ — that holds the frozen, notarized v0.1 release artifact.
#
# This is NOT a release path: no Developer ID signing, no notarization, no ZIP.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV_DIST="$ROOT/dist-dev"

if [[ -e "$DEV_DIST/.p55_bundle_freeze_timestamp" ]]; then
  echo "error: $DEV_DIST unexpectedly looks like a frozen release dir" >&2
  exit 1
fi

mkdir -p "$DEV_DIST"

# Force ad-hoc signing even when a Developer ID exists: dev builds are not releases.
env -u SIGNING_IDENTITY \
  DIST_DIR="$DEV_DIST" \
  DEV_FORCE_ADHOC=1 \
  bash "$ROOT/scripts/package-release-app.sh"

echo "==> v0.2 dev app: $DEV_DIST/AI Storage Manager.app"
