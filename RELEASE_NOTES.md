# AI Storage Manager — Release Notes v0.2.0

**Build:** 51  
**Date:** 2026-09-08  
**Channel:** Direct macOS distribution  
**Distribution:** **Signed and notarized for direct macOS distribution.** Developer ID Application (Team `2MK7L9N4N7`), Hardened Runtime, notarization Accepted by Apple, ticket stapled, Gatekeeper `accepted` (`source=Notarized Developer ID`).

## Artifact

| | |
|---|---|
| File | `AIStorageManager-0.2.0-rc51-arm64.zip` |
| Path | `dist-0.2/AIStorageManager-0.2.0-rc51-arm64.zip` |
| Size | 5,616,890 bytes |
| SHA-256 | `a5eb688a77084555af880f7c9bd2be54ff8d1fd4954efc7fb3d530be667c89b1` |
| Architecture | arm64 |
| Minimum macOS | 13.0 |
| Locales | en, ja, zh-Hans, zh-Hant, ko, es, fr, de, pt-BR |

Install: download → extract → move to `/Applications` → launch normally.  
No Gatekeeper bypass is required.

Frozen v0.1 remains immutable under `dist/` and must not be overwritten.

## What’s new in 0.2.0

- Settings pane no longer blank (language picker reachable)
- Remaining product UI English hardcodes recovered into the offline L10n catalog
- Split divider ownership fixed (ghost vertical line removed)
- Lens labels clarified (Where? / What is it? / What can I do?)
- Scan status is one state → one sentence (partial ≠ failure)
- Native app menu follows en/ja bundle localization
- Unused `ContentView` shell removed

## Unchanged Safety / Executors

- Executor set still exactly three: MOVE_TO_TRASH / Ollama MODEL / Hugging Face SNAPSHOT
- Canonical verified recovery total still **5,580,814,899** bytes
- Research remains COMPLETE / FROZEN
- No live storage mutation in this packaging cycle

## Intentionally not claimed

- Automatic cleanup of your whole Mac
- “Free X GB” on protected recordings/app state
- Universal x86_64 / Intel support in this build
- Network / AI translation backends
- Every world language / RTL support

## Safety

See `docs/SAFETY.md`. Mutation still requires Fresh Preflight → Approval → Permit → Executor → PostVerify.
