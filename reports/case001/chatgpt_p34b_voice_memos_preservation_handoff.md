# ChatGPT Handoff — P3.4B Voice Memos Preservation Contract

**Date:** 2026-09-05  
**Repo:** `~/Workspace/10_進行中/ai-storage-manager`  
**Git:** NO COMMIT / NO PUSH

## Verdict

**VOICE_MEMOS_NO_NATIVE_LOCAL_EVICTION**

Voice Memos syncs via **CloudKit** (Core Data mirroring).  
Permanent delete **propagates** across Apple devices.  
No proven **Remove Download / local-only eviction** contract.  
**eligibleLocalEvictionBytes = 0.**  
Recordings: **KEEP.**

## Why this is success

A naive cleaner asks “delete 14GB?”  
We asked “keep + free local?”  
Answer: **Apple does not expose a safe local-only offload we can prove.**  
Do not invent a workaround.

## Key evidence

- Media ~14.02GB RESIDENT in group container  
- CloudKit linked; File Provider **not** linked  
- `CloudRecordings.db` ANSCK* mirroring live  
- UI: Delete Recording / iCloud Syncing — **no** Remove Download  
- Daemon hint `CloudRecordingsMarkedPlayableAndEvicted` ≠ product contract  

## Next

Pivot: **`DIFFERENT_CURRENT_ENTITY`** (Chrome / Claude intelligence).

## Locks

Cursor KEEP / actionable 0 · executors unchanged · no mutation · qwen3/HF absent
