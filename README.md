# AI Storage Manager

**v0.2.0 (build 51) — Signed & Notarized for direct macOS distribution**

Mac storage, understood safely.

DaisyDisk-class visual exploration  
**+** AI Storage Decision Intelligence

## What it does

SEE → UNDERSTAND → DECIDE → ACT → VERIFY

- Map where space went
- Explain what it is
- Recommend Keep / Verify / Act from evidence
- Only mutate through Fresh Preflight → Approval → Permit → Executor → PostVerify

## What it is not

A one-click cleaner.  
It will not delete something just because it is large, old, or called cache.

## Requirements

- macOS 13.0 or later
- Apple Silicon (arm64)

## Supported languages

- English
- 日本語
- 简体中文
- 繁體中文
- 한국어
- Español
- Français
- Deutsch
- Português (Brasil)

Default follows the macOS system language.  
Optional override: Settings → Language.

## Install

1. Download `AIStorageManager-0.2.0-rc51-arm64.zip`
2. Extract it
3. Move **AI Storage Manager.app** to `/Applications`
4. Launch it normally

The app is signed with a Developer ID Application certificate and notarized by
Apple, with the notarization ticket stapled to the bundle. No Gatekeeper
workaround is needed, and none should be used.

## Run from source (development)

```bash
swift run -c release ai-storage-manager
# or
bash scripts/package-dev-app.sh
open "dist-dev/AI Storage Manager.app"
```

Release packaging (does **not** touch frozen `dist/`):

```bash
DIST_DIR="$PWD/dist-0.2" bash scripts/package-release-app.sh
DIST_DIR="$PWD/dist-0.2" bash scripts/notarize-release.sh
```

## Docs

- [Install](docs/INSTALL.md)
- [Safety](docs/SAFETY.md)
- [Privacy](docs/PRIVACY.md)
- [Known limitations](docs/KNOWN_LIMITATIONS.md)
- [Release notes](RELEASE_NOTES.md)

## Development

```bash
swift test
swift run storage-intel scan   # read-only CLI
```

## Safety invariants (non-negotiable)

```
UNKNOWN NEVER AUTO-PROMOTES TO GREEN
PATH ALONE IS NOT SAFETY
FALSE GREEN IS A CRITICAL BUG
LLM NEVER OVERRIDES SAFETY RULES
NO VENDOR CLEANUP WITHOUT ALIGNED CONTRACT
```

## Distribution

**Signed and notarized for direct macOS distribution.**

| | |
|---|---|
| Signing | Developer ID Application (Team `2MK7L9N4N7`) |
| Hardened Runtime | Enabled |
| Notarization | Accepted by Apple (`9698df53-d30a-48a7-ba52-5c447be2a5bf`) |
| Ticket | Stapled to the app bundle |
| Gatekeeper | `spctl` accepted — `source=Notarized Developer ID` |
| Architecture | arm64 |
| Locales | 9 (en, ja, zh-Hans, zh-Hant, ko, es, fr, de, pt-BR) |
| Final ZIP | `dist-0.2/AIStorageManager-0.2.0-rc51-arm64.zip` |
| Final ZIP SHA-256 | `a5eb688a77084555af880f7c9bd2be54ff8d1fd4954efc7fb3d530be667c89b1` |

Frozen v0.1 evidence remains under `dist/` and must not be rebuilt.  
App Store packaging is not required for v0.2.
