# ChatGPT Handoff — P3.3D Cursor state.vscdb.backup Retention & Recovery

**Date:** 2026-09-05  
**Repo:** `~/Workspace/10_進行中/ai-storage-manager`  
**Git:** NO COMMIT / NO PUSH

## Verdict

**KEEP / CURRENT_RECOVERY_BACKUP.**  
`state.vscdb.backup` (~1.28GB) is Cursor’s sole SQLite recovery copy.  
Restore path is **LIVE** (open failure → rename `.backup` → main).  
**potentialRecoveryBytes = 0.**  
Next centerpin: **`CURSOR_RECOVERY_BACKUP_KEEP`**.  
Follow-on pivot: **`DIFFERENT_CURRENT_ENTITY`**.

## What it is

- Full SQLite DB copy at `${state.vscdb}.backup`
- Created on storage **close** via `copy(path, path.backup)` when backup not disabled
- Currently `cursor.storage.disableSqliteStorageBackup=true` → **no refresh**, but file retained
- On open failure: move main → `.corrupted.<ts>`, promote backup to main

## Why not delete

- Active recovery role
- Backup-only keys exist (unique recovery state)
- No vendor cleanup/remediation contract
- disableBackup ≠ permission to remove existing recovery copy

## Locks

- state.vscdb / bubbleId / agentKv protected  
- agent-cli actionable = 0  
- No Cursor executor / no mutation  
- Ollama/HF fixtures ALIGNED  

## Reports

`reports/case001/p3_3d_*.json` + `cursor_p33d_*.png`
