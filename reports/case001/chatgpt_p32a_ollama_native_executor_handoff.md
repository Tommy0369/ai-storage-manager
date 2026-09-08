# Cursor → ChatGPT Handoff
# AI Storage Manager — P3.2A DONE (implementation)
# Ollama Native Cleanup Executor
# STOPPED at human authorization boundary — NO real mutation

Date: 2026-09-04  
Repo: `~/Workspace/10_進行中/ai-storage-manager`  
Git: **NO COMMIT / NO PUSH**

---

## One-line verdict

Executor for **exact Ollama MODEL × VENDOR_NATIVE_CLEANUP** exists and is tested with fakes.  
Live Mac read-only preflight for `library/qwen3:4b` is **VERIFY_MORE** (runtime / executable unresolved).  
**Do not ask for deletion authorization yet. No `ollama rm` ran.**

---

## Required final answers (1–70)

1. **Implemented:** Scoped capability key; `BoundedProcessRunner` + `FakeProcessRunner`; `OllamaNativeCleanupExecutor` (`ollama rm <canonical>` argv only); `OllamaRunningModelsObserver` (`ollama ps`); contract/post-verify/audit; MutationGate path for Ollama MODEL; Fresh Preflight Ollama enrichment; single-use permit ledger; Optimization Plan scoped support; UI label “Remove Ollama Model”; P32A reports; fixture screenshots; live read-only preflight.
2. **Changed files (major):**
   - `Sources/AppServices/Optimization/ActionExecutionCapabilityRegistry.swift`
   - `Sources/SafetyCore/Mutation/BoundedProcessRunner.swift` *(new)*
   - `Sources/SafetyCore/Mutation/OllamaModelIdentity.swift` *(new)*
   - `Sources/SafetyCore/Mutation/OllamaRunningModelsObserver.swift` *(new)*
   - `Sources/SafetyCore/Mutation/OllamaNativeCleanupExecutor.swift` *(new)*
   - `Sources/SafetyCore/Mutation/StorageActionExecutor.swift` (+ router)
   - `Sources/SafetyCore/Mutation/ActionExecutionPolicy.swift`
   - `Sources/SafetyCore/Mutation/MutationGate.swift` / `MutationGateModels.swift`
   - `Sources/SafetyCore/Mutation/TransactionContractRegistry.swift`
   - `Sources/SafetyCore/Mutation/ActionBindingFingerprint.swift`
   - `Sources/SafetyCore/Mutation/FreshReadOnlyPreflightEngine.swift`
   - `Sources/SafetyCore/Mutation/DryRunActionPlanBuilder.swift`
   - `Sources/SafetyCore/Action/ActionPolicy.swift` / `ActionModels.swift`
   - `Sources/AppServices/Optimization/OptimizationCandidateBuilder.swift`
   - `Sources/AppServices/UICandidateMapper.swift`
   - `Sources/AppServices/LiveStorageActionCoordinator.swift`
   - `Sources/AppServices/StorageExperience/P32AReports.swift` *(new)*
   - `Sources/StorageIntel/main.swift`
   - `Tests/AppServicesTests/P32AOllamaNativeCleanupTests.swift` *(new)*
   - `tasks.md`, `reports/case001/p3_2a_*.json`, screenshots
3. **Tests before:** 421 / 0  
4. **Tests after:** **445 / 0**  
5. **Failures:** 0  
6. **False GREEN:** 0  
7. **duplicateEvaluations:** 0  

8. **Scoped capability architecture:** `ExecutionCapabilityKey(action, vendor?, entityKind?)`  
9. **MOVE_TO_TRASH unchanged?** YES (still IMPLEMENTED)  
10. **Ollama vendor-native:** `VENDOR_NATIVE_CLEANUP|OLLAMA|MODEL` → **IMPLEMENTED**  
11. **HF vendor-native:** **NOT_IMPLEMENTED**  
12. **Raw blob:** **NOT_SUPPORTED**  
13. **Executor class:** `OllamaNativeCleanupExecutor` (+ `StorageActionExecutorRouter`)  
14. **Native operation:** `ollama rm <exact-canonical-model>`  
15. **Shell used?** **NO**  
16. **Raw delete fallback?** **NO**  
17. **Executable resolution:** fixed candidate paths only (incl. Ollama.app Resources); no shell PATH  
18. **Canonical model ID binding:** verified entity display / reconstructed identity; regex + metachar reject  
19. **Local manifest binding:** semanticBindingDigest includes LOCAL_MANIFEST notes + unique/shared + contract version  
20. **Remote proof binding:** remote identity + revision/digest + verifiedAt/freshUntil in digest  
21. **Remote freshness enforcement:** MutationGate blocks `REMOTE_PROOF_STALE`; Fresh Preflight can refresh  
22. **Reference graph binding:** required VERIFIED in gate; included in digest  
23. **Runtime proof method:** bounded one-shot `ollama ps`; absence in COMPLETE snapshot → INACTIVE VERIFIED  
24. **Exact target runtime live result:** **UNKNOWN/UNKNOWN** (CLI binary not found on this Mac)  
25. **Service-only semantics preserved?** YES (empty COMPLETE ps ⇒ inactive; service alone ≠ active)  
26. **Fresh Preflight gates:** identity, manifest bind, ref graph, remote fresh, exact inactive, no custom/user-original, capability, contracts  
27. **Approval required?** YES (for future execution)  
28. **ExecutionPermit required?** YES  
29. **Permit single use?** YES (`ExecutionPermitLedger`)  
30. **Plan creation invokes executor?** NO  
31. **Exact command argv in fake test:** `["rm", "library/qwen3:4b"]` on resolved ollama URL  
32. **Injection tests:** pass (`; rm`, `&&`, newline, paths rejected; never reach runner)  
33. **Timeout:** TIMED_OUT recorded; no blind retry  
34. **Nonzero exit:** failureReason set; no recovery claim  
35. **Exit-0-but-model-remains:** post-verify → MODEL_REMOVAL_NOT_VERIFIED  
36. **PostVerify:** `OllamaPostMutationVerifier`  
37. **Model removal success:** exact model absent from authoritative inventory  
38. **Storage recovery model:** MODEL_REMOVED vs STORAGE_RECOVERED separated  
39. **Potential recovery bytes:** unique estimate (~2.497 GB) for planning UX only  
40. **immediateExpectedRecoveryBytes:** 0 (not promised)  
41. **verifiedRecoveredBytes:** post-state measured only (never pre-estimate)  
42. **Blob-remains:** logical success + storage remains/partial; no raw cleanup  
43. **Shared-blob:** native rm only; retained shared reported, not failure  
44. **Custom/local:** blocked / KEEP / user-original protection  
45. **P3.0.2 history:** future real action can correlate via entity/action IDs (not built this phase beyond contract)  
46. **P3.0.3 plan:** scoped capability map; Ollama MODEL → preflightRequired when eligible; HF stays Verified Future  
47. **20GB plan before (P3.1.1):** Ready Now 0 / VF ~5.685 GB  
48. **20GB plan after:** Ready Now **0** / VF ~3.189 GB (Ollama left VF due to runtime VERIFY_MORE; HF ~3.08 GB remains VF)  
49. **Ollama readiness tier:** **VERIFY_MORE**  
50. **Ollama remaining blockers:** `OLLAMA_MODEL_RUNTIME_NOT_INACTIVE_VERIFIED`, `OLLAMA_EXECUTABLE_UNRESOLVED` (CLI missing)  
51. **HF still non-executable?** **YES**  
52. **First-map before (baseline):** 1021 ms  
53. **First-map after:** **691 ms**  
54. **First-map regression %:** ~**-32%** (faster)  
55. **Real read-only preflight status:** **VERIFY_MORE**  
56. **Exact real candidate:** `library/qwen3:4b` / `ai.ollama.model.library.qwen3:4b` / unique 2,497,293,931  
57. **Human authorization required?** **NO** (preflight not at APPROVAL_REQUIRED)  
58. **Real mutation executed?** **NO**  
59. **Executor invoked against real Mac?** **NO**  
60. **New mutation capability count:** +1 scoped (`OLLAMA|MODEL|VENDOR_NATIVE_CLEANUP`)  
61. **Existing executor scope:** MOVE_TO_TRASH + Ollama MODEL native  
62. **secondCrawlerAdded:** false  
63. **Safety production rules loosened?** NO (UNKNOWN SafetyClass still not GREEN; vendor path eligibility-only)  
64. **Regression suite:** 445 / 0  
65. **Reports:**
    - `reports/case001/p3_2a_ollama_executor_contract.json`
    - `reports/case001/p3_2a_ollama_real_preflight.json`
    - `reports/case001/p3_2a_plan_before_after.json`
66. **Screenshot paths:**
    - `reports/case001/screenshots/ollama_p32a_review_ready.png`
    - `reports/case001/screenshots/ollama_p32a_preflight_blocked_runtime.png`
    - `reports/case001/screenshots/ollama_p32a_approval.png`
    - `reports/case001/screenshots/ollama_p32a_postverify_recovery_pending.png`
67. **tasks.md:** P3.2A DONE  
68. **Known limitations:**
    - Live Mac has `~/.ollama/models` but **no resolvable `ollama` CLI** → cannot prove INACTIVE or execute native rm
    - Live UI still does not auto-create real approval (by design)
    - Screenshots are deterministic fixture placeholders (not live SwiftUI captures)
    - Coordinator execute path for vendor-native not fully wired to UI end-to-end in this phase (preflight path yes)
69. **git commit created?** **NO**  
70. **Recommended next exact step:**  
    Restore/install Ollama CLI (or point resolver at real binary), re-run **read-only** Fresh Preflight for `library/qwen3:4b`.  
    **Only if** status becomes `APPROVAL_REQUIRED` / `READY_FOR_HUMAN_AUTHORIZATION`, ask for a **new exact human authorization** to run native removal.  
    Do **not** authorize deletion while runtime/executable remain UNKNOWN.

---

## Hard stop

Exact Ollama candidate is **NOT** ready for human deletion authorization.  
Implementation is ready. Evidence for safe execution is not.

Remote reacquisition remains VERIFIED and fresh.  
Reference graph VERIFIED.  
Unique bytes ~2.497 GB.  
Blockers are runtime/executable — not Safety GREEN games.
