# P3.3B Handoff — Cursor Database Growth Root Cause & Retention Semantics

Date: 2026-09-05  
Repo: ai-storage-manager  
Git: **NO COMMIT / NO PUSH**

## Verdict

**DONE.** `state.vscdb` ~10.4GB is **live user/agent logical payload**, not freelist bloat and not proven cache.

Primary root cause: `LIVE_USER_AGENT_STATE_DOMINANT`  
Selected next: **AGENT_CLI_VERSION_CLEANUP_PROOF** (~2.45GB inactive versions)

## Physical accounting (live RO)

| Metric | Value |
|--------|------:|
| DB bytes | ~10.45 GB |
| WAL | ~186 MB (not significant) |
| SHM | ~0.4 MB |
| page_size | 4096 |
| freelist | ~934 pages ≈ **3.7 MB** (not significant) |
| journal | wal |
| auto_vacuum | 0 |
| DB open | true |
| inspection mutated DB | **false** (RO contract) |
| largest object | `cursorDiskKV` ~10.40 GB pages |

## Logical KV (privacy-safe)

| Class | Count | Bytes | Note |
|-------|------:|------:|------|
| bubbleId | 186,711 | ~5.13 GB | chat message bodies (vendor label) |
| agentKv | 94,852 | ~4.40 GB | mostly `agentKv:blob` |
| checkpointId | 1,224 | ~0.27 GB | composer file checkpoints |
| other/composer | residual | ~0.26 GB | |
| **total logical** | ~291k | **~10.07 GB** | |

## Retention / delete

- `NO_VENDOR_RETENTION_PROOF_FOUND` (no TTL / max-entry / size GC for cursorDiskKV)
- No `DELETE FROM cursorDiskKV` in inspected Cursor.app
- UI chat delete blast radius: **UNKNOWN**
- Sync/reacquisition of KV: **UNKNOWN**
- Reinstall ≠ data restore

## Backup

`state.vscdb.backup` ~1.28 GB — older/smaller snapshot; vendor lifecycle **UNKNOWN**; **PROTECTED**

## Next centerpin

**AGENT_CLI_VERSION_CLEANUP_PROOF**  
inactive ~2.45 GB / 12 versions · active `2026.08.31-4057e58`  
Why: do not chase destroying ~10GB of valuable chat/agent state without a proven native contract.

## Suites

| | |
|--|--|
| before | **616 / 0** |
| after | **629 / 0** |
| False GREEN | 0 |
| duplicateEvaluations | 0 |
| secondCrawlerAdded | **false** |

## Reports

`reports/case001/p3_3b_*.json` + fixture screenshots `cursor_p33b_*.png`
