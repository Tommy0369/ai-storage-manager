# AI Storage Manager — Safety (v0.1)

AI Storage Manager does **not** delete something just because it is large, old, or named “cache.”

## Core principles

- UNKNOWN never auto-promotes to actionable
- Path / filename alone is not Safety
- Old ≠ unused; unused ≠ unnecessary
- Regenerable ≠ always safe to remove
- Running / open targets block relevant actions
- User originals are protected
- Cloud sync / delete propagation must be verified before local-only claims
- Vendor-native cleanup requires an aligned contract (vendor × store × target × blast radius × state)
- Human approval cannot override UNKNOWN, store mismatch, or unbounded blast radius
- Verified recovery requires post-verification — not vendor exit code alone

## What the app will do

- Show where storage is
- Explain what it likely is
- Recommend Keep / Verify / Act only from canonical evidence
- For supported actions: review, preflight, approve, execute, verify

## What the app will not do

- One-click “clean your Mac”
- Raw `rm` fallbacks
- Treat Chrome IndexedDB / site state as disposable cache
- Treat Voice Memos deletion as local cleanup
- Treat Claude VM images as regenerable by filename
- Auto-retry interrupted mutations

## Actions in v0.1

1. Move to Trash (with pending recovery until Trash is emptied)
2. Ollama model cleanup (vendor-native)
3. Hugging Face snapshot cleanup (vendor-native)

Everything else is Keep / Verify More until a proven contract exists.
