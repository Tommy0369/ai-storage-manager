# ChatGPT Handoff — P3.4A Inventory Re-baseline & Preservation-First

**Date:** 2026-09-05  
**Repo:** `~/Workspace/10_進行中/ai-storage-manager`  
**Git:** NO COMMIT / NO PUSH

## Verdict

Cursor investigation **closed** (actionable=0).  
Next centerpin: **`VOICE_MEMOS_SYNC_SEMANTICS_PROOF`**.  
~14GB Voice Memos = user originals.  
Question: keep recordings + free local — **not** delete 14GB.  
Preservation contract: **NOT ready** (remote/propagation/native eviction unproven).

## Cursor closure

| Entity | Bytes | Decision |
|--------|------:|----------|
| state.vscdb | ~10GB | KEEP |
| agent-cli GS | ~2.68GB | KEEP |
| state.vscdb.backup | ~1.28GB | KEEP |
| **Actionable** | **0** | — |

## Ranking (next proof, not size alone)

1. Voice Memos ~14.09GB — preservation-first winner  
2. Claude ~12.6GB — KEEP/VERIFY_MORE  
3. Chrome ~10.7GB — decompose first  
4. Cursor — score 0 (closed)

## Voice Memos (selected)

- Media ~14.02GB (m4a+qta); waveforms ~66MB; DB metadata present  
- CloudKit schema live (`ZCLOUDRECORDING`=125; `ZEVICTIONDATE` set on 7)  
- Remote bytes **not verified**  
- Delete propagation **UNKNOWN**  
- Native local-only eviction **not proven**  
- Generic MOVE_TO_ICLOUD: **blocked**  
- Raw delete: **forbidden**

## Recovered / goal

- Completed verified: **5,580,814,899**  
- Remaining 20GB goal: **14,419,185,101**  
- Current actionable potential: **0**

## Next

`VOICE_MEMOS_SYNC_SEMANTICS_PROOF` — prove remote residency + delete propagation + native eviction (if any).
