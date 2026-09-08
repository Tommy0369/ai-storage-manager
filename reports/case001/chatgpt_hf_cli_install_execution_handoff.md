# ChatGPT Handoff — HF CLI Install Execution

Date: 2026-09-05  
Authorization: `brew install hf` only (no cache deletion)

## Verdict

**HF_CLI_INSTALLED_CONTRACT_PROVEN**

Executable: `/opt/homebrew/bin/hf`  
Version: **1.29.0**  
Cache revision **unchanged**.  
No real `hf cache rm`. No cleanup permit.

---

## What happened

### Attempt 1 — FAILED (authorized path from P3.2B.1 proposal)

- Brew: `/usr/local/bin/brew` (Intel Cellar path)
- This Mac is **arm64**
- Failed building dependency `openssl@3` (`-march=westmere`)
- Homebrew warns Intel x86_64 unsupported
- `hf` **not** installed at `/usr/local/bin/hf`
- Partial side effects under `/usr/local`: pkgconf / ca-certificates upgrades; openssl build aborted

### Attempt 2 — SUCCESS (same authorization: brew install hf)

- Brew: `/opt/homebrew/bin/brew` (native arm64 Homebrew present on this Mac)
- Poured bottled `hf` 1.29.0 → **`/opt/homebrew/bin/hf`**
- Dependencies poured under `/opt/homebrew` only (bottles)

Path note: proposal said `/usr/local/bin/hf`; correct executable on this Mac is **`/opt/homebrew/bin/hf`**.

---

## CLI contract (proven)

| Capability | Status |
|------------|--------|
| `hf --version` | 1.29.0 |
| `hf cache ls` | yes |
| `hf cache verify` | yes |
| `hf cache rm` | yes |
| `--dry-run` | yes |
| `--cache-dir` | yes |
| `--yes` | yes |

Read-only dry-run (not deletion):

```
hf cache rm 49e6aa286ad60c14352c404340ded53710378a11 --dry-run --cache-dir ~/.cache/huggingface/hub
```

Preview: delete 1 repo totalling 3.1G (entire repo — sole revision).  
`dry_run=True`. Inventory fingerprint unchanged.

---

## Explicitly NOT done

- ❌ real `hf cache rm` (without dry-run)
- ❌ Hub remote delete
- ❌ cleanup ExecutionPermit
- ❌ HF skills install (`hf skills add`)
- ❌ `hf update`

---

## Cache target

- Repo: `mlx-community/whisper-large-v3-mlx`
- Revision: `49e6aa286ad60c14352c404340ded53710378a11`
- Still present: **yes**
- Fingerprint: `76f310382467a41d6a5718b7a720396c` (before = after)

---

## Recommended next step

Re-enter **P3.2B Fresh Preflight** (read-only):

native interface resolved → dry-run bound → runtime proof → remote refresh → stop at cleanup APPROVAL_REQUIRED if gates pass.

**Do not** create cleanup approval until ChatGPT requests separate HF removal authorization.
