# ChatGPT Handoff — P3.3C.2 Cursor Agent CLI Legacy Store Remediation Proof

**Date:** 2026-09-05  
**Repo:** `~/Workspace/10_進行中/ai-storage-manager`  
**Git:** NO COMMIT / NO PUSH

## Verdict

**GS ~2.68GB is NOT proven legacy.**  
It is **`CURRENT_PRIMARY_STORE`** for `cursor-agent-worker` (globalStorage).  
HOME is a **sibling** `CURRENT_PRIMARY_STORE` for CLI install-core.  
**Remediation contract: NONE.**  
**potentialRecoveryBytes = 0.**  
**Next centerpin: `NO_SAFE_CURSOR_AGENT_CLI_ACTION`.**  
Follow-on pivot (product): `CURSOR_BACKUP_RETENTION_PROOF`.

## Centerpin answers (short)

| Q | Answer |
|---|--------|
| Who creates GS? | `cursor-agent-worker` via `globalStorageUri.fsPath/agent-cli/.../versions` |
| Who reads/writes/launches GS? | Same worker (cache / download / spawn) |
| Current Cursor launch from GS? | **Yes** (call path + selected bin + install marker) |
| HOME equivalent versions? | Only `2026.08.11-e8db854` overlap — **SAME_LABEL_DIFFERENT_ARTIFACT** (not exact dup) |
| Migration GS→HOME? | **No evidence** |
| GS remediation? | **Not found** |
| Actionable bytes? | **0** |

## UX truth

- Cursor stores ~2.68 GB Agent CLI versions in a second location.  
- Current cleanup manages a different store (HOME).  
- This second store is still referenced by the worker.  
- AI Storage Manager will not apply HOME cleanup to GS.

## Reports

`reports/case001/p3_3c_2_*.json` + screenshots `cursor_p33c2_*.png`

## Locks preserved

- False GREEN = 0  
- duplicateEvaluations = 0  
- secondCrawlerAdded = false  
- No Cursor executor  
- state.vscdb / bubbleId / agentKv / backup protected  
- Ollama/HF fixture ALIGNED  
- No mutation
