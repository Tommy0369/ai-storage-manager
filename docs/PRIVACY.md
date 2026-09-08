# AI Storage Manager — Privacy (v0.1)

## What we inspect

Structural storage metadata needed to map and classify:

- paths and sizes
- file/folder kinds
- app/vendor identity signals
- lifecycle / residency / sync *evidence summaries*
- process/open-file *batched* runtime observations where required

## What we do not read as product content

- Voice Memo audio / speech
- Browser history page contents, cookies values, passwords
- Chat/prompt bodies
- Source code contents for cleanup decisions
- Credentials / tokens / keychains

## Network

Basic SEE (map/explore) does not require network.
Localization is offline (shipped catalog). There is **no** network translation
service and **no** AI translation backend.
Network may be used only for explicit existing proof paths (for example remote reacquisition checks for supported vendor artifacts).
Offline mode keeps local map/intelligence working; remote proofs become UNKNOWN/stale — never false GREEN.

## Local history

Scan/history/receipt metadata is stored locally under Application Support for this app.
Diagnostic export should prefer semantic classes, opaque IDs, sizes, and states — not private file contents.

## Telemetry

v0.1 ships **without** analytics/crash telemetry services.
Any future telemetry needs an explicit privacy design.

## Clearing local app data

Remove the app’s Application Support / Preferences for this bundle ID if you want a fresh local history.
(Exact paths depend on install; Settings → diagnostics may point to them when available.)
