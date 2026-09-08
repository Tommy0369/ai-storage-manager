# AI Storage Manager — Known Limitations (v0.1 RC)

## Product

- Not every large vendor has a cleanup executor
- Voice Memos: CloudKit sync exists; **no verified Apple local-only eviction contract**
- Chrome: site/app state is protected; verified cache ≠ aligned cleanup contract yet
- Claude: base runtime ≠ mutable session; active runtime stays KEEP
- Cursor large DB / backup / agent-cli: KEEP (actionable 0)
- Goal pressure never changes Safety

## Platform / distribution

- This RC build is **arm64** (Apple Silicon) — not universal / not Intel
- Minimum macOS: **13.0**
- Direct distribution ZIP is **Developer ID signed + notarized + stapled** (P5.1)
- App Store packaging is not part of v0.1

## Visibility

- Without Full Disk Access, some Library areas remain inaccessible
- Inaccessible ≠ 0 bytes and ≠ safe
- Progressive map may be PARTIAL while still useful

## Actions

- MOVE_TO_TRASH does not free disk until Trash is emptied (app does not Empty Trash)
- Historical Ollama/HF verified recovery is receipt-based — not a live candidate factory
- No auto-retry of mutations after interruption
