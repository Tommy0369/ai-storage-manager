# Cursor → ChatGPT Handoff
# AI Storage Manager — P3.1.1 DONE
# Bounded Remote Reacquisition Verification (HF + Ollama)

Date: 2026-09-04  
Repo: `~/Workspace/10_進行中/ai-storage-manager`  
Git: **NO COMMIT / NO PUSH**

---

## One-line verdict

P3.1.1 answered the narrow question honestly:  
**exact local HF snapshot + exact Ollama model are remotely reacquirable now.**  
Ready Now stays **0**. Executor still **NOT_IMPLEMENTED**.

---

## Baseline entering P3.1.1

- P3.0 → P3.1 DONE / PASS
- Tests before: **409 / 0 failures**
- False GREEN = 0
- duplicateEvaluations = 0
- Executor: **MOVE_TO_TRASH only**
- Unresolved AI inventory: HF ~3.084 GB + Ollama ~2.497 GB (remote UNKNOWN)

---

## Required final answers (1–59)

1. **Implemented:**  
   `RemoteReacquisitionProof` + budgeted transport/session;  
   `HuggingFaceRemoteVerifier` (exact revision API + bounded HEAD);  
   `OllamaRemoteVerifier` (exact manifest GET + digest compare);  
   late pipeline stage `remote_reacquisition_proof`;  
   freshness-bound claims; plan wiring to Verified Future (not Ready Now);  
   UX evidence lines; P3.1.1 reports; mock-transport unit tests; live read-only Mac proof.

2. **Changed files (major):**
   - `Sources/SafetyCore/Verification/RemoteReacquisitionModels.swift` *(new)*
   - `Sources/SafetyCore/Verification/RemoteReacquisitionVerifiers.swift` *(new)*
   - `Sources/SafetyCore/Models/EvidenceObservation.swift` (remote proof fields)
   - `Sources/SafetyCore/Intelligence/ReadOnlyAnalysisPipeline.swift` (late remote stage)
   - `Sources/SafetyCore/Action/ActionSafetyEvaluator.swift` (`evaluateVendorCleanup` freshness)
   - `Sources/AppServices/Optimization/*` (vendor-native → verifiedFuture when eligible)
   - `Sources/AppServices/UICandidateMapper.swift`
   - `Sources/AppServices/StorageExperience/P31ProofReports.swift`
   - `Sources/AppServices/StorageExperience/P311RemoteReports.swift` *(new)*
   - `Sources/StorageIntel/main.swift`
   - `Tests/AppServicesTests/P311RemoteReacquisitionTests.swift` *(new)*
   - `reports/case001/p3_1_1_*.json`
   - `tasks.md`

3. **Tests before:** 409 / 0 failures  
4. **Tests after:** **421 / 0 failures** (+12 P311)  
5. **Failures:** 0  
6. **False GREEN:** 0  
7. **duplicateEvaluations:** 0  

8. **Remote verifier architecture:**
   ```
   VendorStorageProofProvider (local, P3.1)
     → RemoteReacquisitionService.proveAll (late, after first map)
       → HuggingFaceRemoteVerifier / OllamaRemoteVerifier
       → RemoteRequestSession (budget / cache / coalesce)
       → RemoteReacquisitionProofIndex
     → apply onto VerificationAnnotation (claims only)
     → ActionSafetyEvaluator / OptimizationPlan (canonical Safety still owns class)
   ```
   Remote verifier **does not** assign SafetyClass.

9. **HF remote proof method:**  
   `GET /api/models/{repo}/revision/{exactCommit}`  
   optional bounded `HEAD .../resolve/{revision}/config.json`  
   **no** latest-branch fallback.

10. **HF exact revision verified?** **YES**  
    `mlx-community/whisper-large-v3-mlx@49e6aa286ad60c14352c404340ded53710378a11`

11. **HF auth class:** `ANONYMOUS`

12. **HF reacquisition result:** `REACQUIRABLE_VERIFIED`

13. **HF unique bytes remote verified:** **3,083,520,968** (~3.084 GB)

14. **HF remaining blockers:**  
    `VENDOR_NATIVE_CLEANUP_EXECUTOR_UNAVAILABLE`  
    (root/repo still not auto-cleanable; raw blob delete still blocked)

15. **Ollama remote proof method:**  
    `GET` exact registry manifest for installed identity;  
    compare local manifest/blob digests; mutable tag alone insufficient.

16. **Ollama exact manifest/digest verified?** **YES** (`library/qwen3:4b`)

17. **Ollama tag drift handling:**  
    local digest ≠ remote tag tip → `REMOTE_IDENTITY_MISMATCH`  
    (unit-tested; live Mac matched — no drift)

18. **Ollama reacquisition result:** `REACQUIRABLE_VERIFIED`

19. **Ollama unique bytes remote verified:** **2,497,293,931** (~2.497 GB)

20. **Ollama remaining blockers:**  
    `VENDOR_NATIVE_CLEANUP_EXECUTOR_UNAVAILABLE`  
    (runtime ACTIVE not claimed; service-running ≠ remote proof)

21. **Remote requests:** **2** (HF 1 entity attempt accounted in vendor report with request budget; live session total requests = 2)  
22. **Remote bytes received:** **2,146**  
23. **Remote timeouts:** **0**  
24. **Auth-required count:** **0**  
25. **Rate-limit count:** **0**  
26. **Remote identity conflicts:** **0**  

27. **Freshness model:** `REMOTE_STATE_FRESH` equivalent via `verifiedAt` + `freshUntil` (default **900s**)  
28. **Proof expiry:** stale `.verified` → strict consumer treats as UNKNOWN (`REMOTE_PROOF_STALE`); UI: “needs to be checked again”  
29. **Credentials persisted?** **NO**  
30. **Credentials logged?** **NO**  
31. **Full model downloads?** **NO**

32. **First-map before (P3.0.4 baseline used):** 1,021 ms  
33. **First-map after:** **814 ms**  
34. **First-map regression %:** **-20.3%** (faster; no regression)  
35. **Remote proof total time:** **764 ms** (pipeline stage)  
36. **Network on first-map path?** **NO**  
37. **Remote proof directly changed Safety?** **NO** (claims/eligibility only; SafetyClass unchanged by verifier)  
38. **Raw blob cleanup permitted?** **NO**  
39. **User-original protection:** preserved (custom/local → NOT_APPLICABLE / KEEP path; remote alone cannot bypass)

40. **Vendor-native eligible entity count:** **2** (HF snapshot + Ollama model) — plan `verifiedFutureCount` total **3** (includes non-AI future slots)  
41. **vendorNativeVerifiedFutureBytes:** **5,580,814,899** (~5.581 GB)

42. **Verify More bytes before (AI unresolved target):** ~5.58 GB  
43. **Verify More bytes after (AI remote-unknown):** **0** for HF/Ollama exact entities (other review surface still exists in UI map totals)  
44. **Verified Future before:** ~103.5 MB  
45. **Verified Future after:** **5,684,664,883** (~5.685 GB) = ~5.581 GB vendor-native + ~103.8 MB prior  
46. **Ready Now before:** **0**  
47. **Ready Now after:** **0**  

48. **20GB Plan result:**  
    - goalStatus: `NEEDS_MORE_VERIFICATION`  
    - Ready Now: 0  
    - Verified Future: ~5.685 GB  
    - shortfall vs 20 GB still large  
    - VENDOR_NATIVE_CLEANUP capability: **NOT_IMPLEMENTED**

49. **ActionExecutionCapabilityRegistry changed?** **NO**  
50. **Existing Executor scope:** **MOVE_TO_TRASH only**  
51. **New mutation APIs?** **NO**  
52. **secondCrawlerAdded:** **false**  
53. **Safety regressions:** none observed (False GREEN=0, dup=0, protections intact)  

54. **Reports:**
    - `reports/case001/p3_1_1_remote_reacquisition.json`
    - `reports/case001/p3_1_1_inventory_before_after.json`
    - `reports/case001/p3_1_1_remote_performance.json`
    - plus refreshed `p3_1_ai_model_inventory.json` / `p3_0_3_optimization_plan.json`

55. **Screenshots:** not added this phase (UX evidence lines only)  

56. **tasks.md:** P3.1.1 marked DONE  

57. **Known limitations:**
    - Manual “Check remote availability” button not shipped (auto late proof + freshness UX present)
    - HF repository entity not remote-proven when snapshot exists (dedupe; snapshot is the exact identity)
    - Runtime ACTIVE for models still largely UNKNOWN/INFERRED
    - No credentials path for gated private HF models beyond anonymous/existing-env (none used live)
    - Plan JSON `selectedEntries` empty by design (Ready Now selection only); Verified Future counted separately

58. **git commit created?** **NO**  

59. **Recommended next phase:**  
    **P3.2 — Vendor Native Cleanup Executor**  
    Reason: ~5.58 GB unique is now **strict remote VERIFIED** + action-eligible + blocked only by **EXECUTOR_UNAVAILABLE**.  
    Do **not** auto-start. Still no Ready Now until executor exists and Fresh Preflight/Permit hold.

---

## Live Mac remote truth (read-only)

| Vendor | Entity | Exact ID | Status | Auth | Unique |
|--------|--------|----------|--------|------|--------|
| Hugging Face | SNAPSHOT | whisper-large-v3-mlx @ 49e6aa28… | VERIFIED | ANONYMOUS | ~3.084 GB |
| Ollama | MODEL | library/qwen3:4b | VERIFIED | ANONYMOUS | ~2.497 GB |

Network: 2 requests, 2146 bytes, 0 timeouts, no mutation verbs.

---

## Hard locks preserved

- FALSE GREEN = 0  
- UNKNOWN never auto-promotes to GREEN  
- REACQUIRABLE ≠ REGENERABLE  
- NATIVE CLEANUP > RAW DELETE  
- PATH ALONE IS NOT SAFETY  
- Remote proof ≠ free to delete  
- No second crawler  
- No full model download  
- No credential persistence/logging  

---

## Decision rule outcome

Meaningful vendor-native unique bytes are strict verified + action-eligible + only blocked by EXECUTOR_UNAVAILABLE  
→ recommend **P3.2**. Do not build it in this phase.
