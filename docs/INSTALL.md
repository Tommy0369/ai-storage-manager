# AI Storage Manager — Install (v0.2)

## Requirements

- macOS 13.0 or later
- Apple Silicon (arm64) for this build
- Optional: Full Disk Access for deeper Library visibility

## Direct distribution (signed & notarized)

1. Download `AIStorageManager-0.2.0-rc51-arm64.zip`
2. Extract
3. Move `AI Storage Manager.app` to Applications (optional)
4. Launch normally

Signed and notarized for direct macOS distribution.  
Do **not** bypass Gatekeeper.

Current release artifact (packaging machine):

`dist-0.2/AIStorageManager-0.2.0-rc51-arm64.zip`  
SHA-256: `a5eb688a77084555af880f7c9bd2be54ff8d1fd4954efc7fb3d530be667c89b1`

Supported UI languages (offline): English, 日本語, 简体中文, 繁體中文, 한국어, Español, Français, Deutsch, Português (Brasil).
Default follows the macOS system language; override in Settings → Language.

Frozen v0.1 ZIP remains under `dist/` and must not be overwritten.

## Rebuild from source (maintainers)

```bash
export SIGNING_IDENTITY='Developer ID Application: Katsuhiro Tomita (2MK7L9N4N7)'
export NOTARY_PROFILE='AIStorageManagerNotary'
DIST_DIR="$PWD/dist-0.2" bash scripts/package-release-app.sh
DIST_DIR="$PWD/dist-0.2" bash scripts/notarize-release.sh
```

Secrets stay in the Keychain profile — never in the repo.

## Local run without packaging

```bash
swift run -c release ai-storage-manager
```

## First launch

1. Open the app
2. Scan Storage
3. Explore the map (Structure / Meaning / Decision)
4. Use Plan / History as needed

No real cleanup happens until:

Fresh Preflight → exact Human Approval → single-use Permit → Executor → PostVerify.

## Permissions

Without Full Disk Access the app still launches and maps what it can.
Inaccessible areas stay UNKNOWN — they are never treated as empty or safe.
