# ChatGPT Handoff — P3.2B.1 HF CLI Install Authorization Boundary

Date: 2026-09-05  
Repo: ai-storage-manager  
Git: **NO COMMIT / NO PUSH**

## Verdict

**READY_FOR_HF_CLI_INSTALL_AUTHORIZATION**

HF CLI is genuinely absent.  
Selected method: **HOMEBREW** (`brew install hf`).  
**No software installed. No cache touched. No cleanup auth.**

---

## Human install boundary

| Field | Value |
|-------|-------|
| Product | Hugging Face `hf` CLI |
| Purpose | restore vendor-native cache management |
| Selected method | HOMEBREW |
| Package | `hf` (homebrew-core, stable **1.29.0**) |
| Source | official Homebrew core / huggingface_hub upstream |
| Expected executable | `/usr/local/bin/hf` |
| HF cache deletion | **NOT AUTHORIZED** |
| HF Hub remote deletion | **NOT AUTHORIZED** |
| Target cache revision | **UNCHANGED** |

After install authorization (separate phase): re-verify CLI → vendor dry-run → separate cleanup auth.

---

## 55-point return

1. Verdict: **READY_FOR_HF_CLI_INSTALL_AUTHORIZATION**
2. HF CLI genuinely absent?: **yes**
3. Existing trusted hf executable found?: **no**
4. Root cause of P3.2B unresolved: **HF_CLI_NOT_INSTALLED** (not a resolver miss of a present binary)
5. Homebrew present?: **yes**
6. Homebrew path/prefix: `/usr/local/bin/brew` / `/usr/local`
7. HF brew formula installed?: **no**
8. HF brew executable present?: **no**
9. uv present?: **no**
10. uv version: n/a
11. existing uv HF tool?: **no**
12. pipx present?: **no**
13. existing pipx HF?: **no**
14. huggingface_hub Python package found?: **no** (brew/pyenv/Xcode python inspected)
15. package version/location: n/a
16. existing hf entry point found?: **no**
17. existing entry point trusted?: n/a
18. Resolver updated?: **yes** (uv tools path + brew-prefix derived candidates)
19. Existing CLI contract proven?: **no** (absent)
20. Installation required?: **yes**
21. Selected install method: **HOMEBREW**
22. Why: brew already on Mac; official formula `hf`; deterministic `/usr/local/bin/hf`; no new PM
23. Package identity: `hf`
24. Source trust: **OFFICIAL_VERIFIED**
25. Desired version policy: homebrew-stable (1.29.0) with cache ls/verify/rm --dry-run --cache-dir
26. Expected executable class: homebrew-linked-bin → `/usr/local/bin/hf`
27. Expected dependency changes: certifi, git-lfs, libyaml, python@3.14 (declared)
28. Credential changes?: **false**
29. HF agent skills by proposal?: **false**
30. Standalone curl\|bash selected?: **no**
31. Why rejected: project policy — pipe-to-shell not auditable
32. Rollback method: `brew uninstall hf`
33. Install authorization boundary reached?: **yes**
34. Install approval created?: **false**
35. Software installed?: **false**
36. HF cache modified?: **false**
37. HF cache rm executed?: **false**
38. HF cache dry-run executed?: **false**
39. Exact HF target still present?: **yes**
40. Exact revision: `49e6aa286ad60c14352c404340ded53710378a11`
41. Current unique bytes: **3,083,520,968**
42. Plan tier: **VERIFY_MORE** (reason: management tool required)
43. Remaining blockers: HF_EXECUTABLE_UNRESOLVED / HF_CLI_INSTALL_REQUIRED / dry-run / remote freshness / runtime product proof
44. Tests before: **542 / 0**
45. Tests after: **555 / 0**
46. Failures: **0**
47. False GREEN: **0**
48. duplicateEvaluations: **0**
49. secondCrawlerAdded: **false**
50. First-map impact: package-manager metadata **not** on first-map path
51. Performance: `p3_2b_1_performance.json`
52. Reports: `p3_2b_1_hf_cli_environment.json`, `p3_2b_1_install_proposal.json`, `p3_2b_1_preflight_blockers.json`
53. tasks.md: P3.2B.1 added
54. git commit?: **no**
55. Recommended exact next step: ChatGPT requests explicit **software-install authorization** for `brew install hf` only — then re-enter P3.2B read-only dry-run path. Still no cache removal.
