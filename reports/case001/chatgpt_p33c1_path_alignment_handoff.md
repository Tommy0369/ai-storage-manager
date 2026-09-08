# P3.3C.1 Handoff — Cleanup Contract Path Alignment

Date: 2026-09-05  
Repo: ai-storage-manager  
Git: **NO COMMIT / NO PUSH**

## Verdict

**DONE.** Formal result: **CLEANUP_CONTRACT_PATH_MISMATCH** / relationship **SIBLING_STORE**.

| | Path | Bytes |
|--|------|------:|
| **ACTUAL** | GS `.../agent-cli/.local/share/cursor-agent/versions` | ~2.68GB |
| **CLEANUP** | HOME `~/.local/share/cursor-agent/versions` | ~0.23GB |

Cleanup command is LIVE for HOME.  
It does **not** cover the 2.68GB worker store.  
**Potential recovery for actual root: 0.**

UX: *"Cursor has a cleanup command, but it targets a different store, not the 2.68GB installed-version store."*

## Next

**CURSOR_AGENT_CLI_LEGACY_STORE_REMEDIATION**  
Do not design executor for wrong-target command.

## Suites

| | |
|--|--|
| before | **644 / 0** |
| after | **659 / 0** |
| False GREEN | 0 |
| duplicateEvaluations | 0 |
| secondCrawlerAdded | **false** |
