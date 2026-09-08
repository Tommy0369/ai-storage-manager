# P3.3C Handoff — Cursor Agent CLI Version Retention & Native Cleanup Proof

Date: 2026-09-05  
Repo: ai-storage-manager  
Git: **NO COMMIT / NO PUSH**

## Verdict

**DONE (read-only).** Agent-cli ~2.68GB is a dual-store vendor toolchain.

| Store | Role | Bytes |
|-------|------|------:|
| globalStorage worker `.../agent-cli/versions` | **material** (13 versions) | ~2.68GB |
| `~/.local/share/cursor-agent/versions` | CLI home install | ~0.23GB (1 ver) |

**Current selected (GS):** `2026.08.31-4057e58` via selection symlink — **KEEP**

**Native cleanup FOUND:**
`agent cleanup-install-versions <currentVersion>`  
Algorithm: keep **current + 2 newest non-current** (skip in-use / active bins).  
**Default target: HOME store — NOT proven for GS worker store.**

Therefore: **0 NATIVE_CLEANUP_CANDIDATE bytes** this phase.  
Hypothetical if GS contract binds: ~1.98GB outside keep window.

## Next centerpin

**CURSOR_AGENT_CLI_NATIVE_CLEANUP_CONTRACT**  
Prove cleanup applies to GS worker versions (or worker-managed equivalent). No mutation until then.

## Suites

| | |
|--|--|
| before | **629 / 0** |
| after | **644 / 0** |
| False GREEN | 0 |
| duplicateEvaluations | 0 |
| secondCrawlerAdded | **false** |

## Reports

`reports/case001/p3_3c_*.json` + fixtures `cursor_p33c_*.png`
