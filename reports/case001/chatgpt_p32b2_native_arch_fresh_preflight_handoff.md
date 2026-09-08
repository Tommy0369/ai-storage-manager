# ChatGPT Handoff — P3.2B.2 Native Architecture + HF Fresh Preflight

**Verdict: READY_FOR_HF_REMOVAL_AUTHORIZATION**

Date: 2026-09-05  
Git: NO COMMIT / NO PUSH  
Real HF cache rm: **NOT EXECUTED**  
Approval / ExecutionPermit: **NOT CREATED**

---

## 83-point return

1. Verdict: **READY_FOR_HF_REMOVAL_AUTHORIZATION**
2. Host architecture: **arm64** (sysctl `hw.optional.arm64=1`; not Rosetta `uname`)
3. Homebrew installations: `/opt/homebrew` (arm64 native), `/usr/local` (x86_64 foreign)
4. Incorrect brew selected previously?: **YES** (P3.2B.1 → `/usr/local`)
5. Why incorrect: PATH/prefix order; ignored host-native preference
6. Failed Intel brew outcome: **FAILED** (openssl@3 source build / westmere)
7. Partial side effects found?: historical pkgconf/ca-certificates under `/usr/local`; openssl build aborted
8. Cleanup performed on failed brew?: **false**
9. Correct native brew: `/opt/homebrew/bin/brew`
10. Native brew architecture: **arm64**
11. Actual HF executable: `/opt/homebrew/bin/hf`
12. Actual HF version: **1.29.0**
13. Old executable expectation stale?: **true** (`/usr/local/bin/hf`)
14. HF binary fingerprint: `path=/opt/homebrew/Cellar/hf/1.29.0/libexec/bin/hf;size=202;mtime=1788565428;version=1.29.0`
15. supports cache ls: **true**
16. supports cache verify: **true**
17. supports cache rm: **true**
18. supports dry-run: **true**
19. supports cache-dir: **true**
20. Fresh target present?: **true**
21. Repo: `mlx-community/whisper-large-v3-mlx`
22. Revision: `49e6aa286ad60c14352c404340ded53710378a11`
23. Revision count: **1**
24. Refs: `main` → exact revision
25. Unique bytes: **3,083,520,968**
26. Shared bytes: **0**
27. Reference graph: **VERIFIED**
28. Vendor verify executed?: **true**
29. Vendor verify result: **OK** (exit 0; mismatch=0)
30. Dry-run executed?: **true**
31. dry_run true?: **true**
32. Dry-run mutation detected?: **false**
33. Targeted revision count: **1**
34. Other revisions retained?: **0**
35. Repo directory removal expected?: **true** (sole revision consequence)
36. Refs affected: **main**
37. Vendor expected freed bytes: **3,100,000,000** (3.1G)
38. Semantic expected freed bytes: **3,083,520,968**
39. Size agreement: **AGREES_WITH_FORMATTING_DIFFERENCE**
40. Preview complete?: **true**
41. Blast radius bound?: **true**
42. Runtime observation source: `lsof -nP -Fn` (OpenFileSnapshot.capture equivalent)
43. Runtime snapshot completeness: **COMPLETE**
44. Target open handles: **0**
45. Runtime state: **INACTIVE_VERIFIED**
46. Runtime fresh?: **true** (freshUntil +5m from observation)
47. Remote exact revision: **49e6aa286ad60c14352c404340ded53710378a11**
48. Remote reacquisition: **REACQUIRABLE_VERIFIED**
49. Remote fresh?: **true**
50. Fresh ActionDecision: **APPROVAL_REQUIRED**
51. Strict required predicates: 20 (see `p3_2b_2_hf_final_preflight.json`)
52. Verified predicates: **20 / 20**
53. Unknown strict predicates: **[]**
54. Conflicts: **[]**
55. Fresh Preflight: **APPROVAL_REQUIRED**
56. Remaining blockers: **USER_APPROVAL** only
57. Approval only remaining gate?: **true**
58. Human boundary reached?: **true** — STOP
59. Real approval created?: **false**
60. ExecutionPermit created?: **false**
61. Real hf cache rm mutation executed?: **false**
62. Hub remote deletion?: **false**
63. Plan before: HF **VERIFY_MORE**
64. Plan after: HF **APPROVAL_REQUIRED**
65. HF tier: **APPROVAL_REQUIRED**
66. HF potential bytes: **3,083,520,968**
67. Ollama regression: none (capability unchanged)
68. qwen3 absent?: **true**
69. HF raw blob regression: still **NOT_SUPPORTED**
70. MOVE_TO_TRASH regression: unchanged
71. Tests before: **555** (P3.2B.1 baseline)
72. Tests after: **572**
73. Failures: **0**
74. False GREEN: **0**
75. duplicateEvaluations: **0**
76. secondCrawlerAdded: **false**
77. First-map impact: **false**
78. Reports: `reports/case001/p3_2b_2_*.json`
79. Screenshots: not generated (truth is JSON reports; no UI approval surface minted)
80. tasks.md: P3.2B.2 marked DONE
81. Known limitations: live preflight orchestration used product-equivalent RO script + aligner catalog; install consent ≠ cleanup consent
82. git commit?: **NO**
83. Recommended exact next step: ChatGPT may request human authorization **only** for:

```
repo: mlx-community/whisper-large-v3-mlx
revision: 49e6aa286ad60c14352c404340ded53710378a11
action: VENDOR_NATIVE_CLEANUP
consequence: remove exact local cached revision;
  because it is the final local revision,
  local repository cache is expected to become empty (~3.08 GB vendor-managed).
does NOT authorize: Hub remote deletion, hf prune, other revisions/repos, raw delete.
```

---

## Product fix summary

- `HomebrewArchitectureResolver` + `HomebrewInstallationResolution`
- Host-native brew > PATH order; MULTIPLE_HOMEBREW_INSTALLATIONS first-class
- Host arch via `hw.optional.arm64` (Rosetta-safe)
- Proposals bind brew executable / prefix / arch / architectureMatch
- Dry-run sole-revision vendor language accepted as complete
- Runtime: COMPLETE batched open-file snapshot → INACTIVE_VERIFIED
