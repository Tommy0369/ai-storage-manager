# P3.3A Handoff — Current Inventory Re-baseline & Cursor Global Storage Intelligence

Date: 2026-09-05  
Repo: ai-storage-manager  
Git: **NO COMMIT / NO PUSH**

## Verdict

**DONE.** Fresh ranking after 5.58GB recovery. Cursor globalStorage remains #1 (~14.42GB). Decomposed without mutation.

## Why ~14GB?

| Component | Bytes | % | Kind | Action |
|-----------|------:|--:|------|--------|
| `state.vscdb` | ~10.37GB | 72% | DATABASE (OPEN) | **KEEP** |
| agent-cli versions | ~2.69GB | 19% | VENDOR_TOOLCHAIN_VERSIONS | NATIVE_CLEANUP_**CANDIDATE** (not executable) |
| `state.vscdb.backup` | ~1.28GB | 9% | CHECKPOINT/BACKUP | VERIFY_MORE |
| other | small | | WAL/SHM/conversation-search/namespaces | KEEP / VERIFY_MORE |

Inside `state.vscdb` → `cursorDiskKV` (privacy-safe key-class only):

- `bubbleId` ≈ 5.07GB — AI conversation/agent bubble state  
- `agentKv` ≈ 4.39GB — agent KV state  
- `checkpointId` ≈ 0.26GB  

**Not junk. Not “Cursor cache.” Protected user/agent state.**

## Next centerpin

**CURSOR_DATABASE_GROWTH_ROOT_CAUSE**  
Prove vendor retention/cleanup semantics for cursorDiskKV classes. No mutation next until proof + consent model exist.

Secondary: agent-cli multi-version native cleanup proof (~2.6GB).

## Suites

| | |
|--|--|
| before | **597 / 0** |
| after | **616 tests / 0 failures** |
| False GREEN | 0 |
| duplicateEvaluations | 0 |
| secondCrawlerAdded | **false** |

## Reports

`reports/case001/p3_3a_*.json` + fixture screenshots `cursor_p33a_*.png`
