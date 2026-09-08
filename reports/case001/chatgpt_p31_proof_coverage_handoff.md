# Cursor → ChatGPT Handoff
# AI Storage Manager — P3.1 DONE
# High-Value Proof Coverage Expansion (Ollama + Hugging Face)

Date: 2026-09-04  
Repo: `~/Workspace/10_進行中/ai-storage-manager`  
Git: **NO COMMIT / NO PUSH**

---

## One-line verdict

P3.1 made the product **know more** about Ollama/HF storage.  
It did **not** declare more storage safe. Ready Now remains **0**.

---

## Product state entering P3.1

Baseline complete: P3.0 / P3.0.1 / P3.0.2 / P3.0.3 / P3.0.4  
Tests before P3.1: **394 / 0 failures**  
False GREEN = 0  
duplicateEvaluations = 0  
Concrete executor: **MOVE_TO_TRASH only**

P3.0.3 live 20GB plan (before):
- Ready Now: 0
- Verified Future: ~107 MB
- Large unresolved: HF ~3.1 GB VERIFY_MORE, Ollama ~2.5 GB VERIFY_MORE

---

## What P3.1 implemented

### Architecture
```
Detector (existing paths)
  → exact vendor entity discovery (bounded metadata under known roots)
  → VendorStorageProofProvider (Ollama / Hugging Face)
  → Verification strategies → VerificationAnnotation claims
  → EntitySafetySnapshot / ActionDecisionSet (canonical Safety unchanged)
```

Providers produce **EVIDENCE / CLAIMS only**.  
They do **not** assign SafetyClass.

### New adapters
- `OllamaStorageProofProvider`
- `HuggingFaceStorageProofProvider`
- smallest abstraction: `VendorStorageProofProvider`

### Explicitly NOT implemented
- ollama rm / HF cache delete / any mutation
- VENDOR_NATIVE_CLEANUP Executor
- MOVE_TO_ICLOUD / REMOVE_LOCAL_DOWNLOAD / Permanent Delete / Empty Trash / bulk cleanup
- generic “AI cache safe” path rules
- second crawler
- network-required first map

### Preferred action semantics (evidence-gated)
- Ollama model → KEEP or VENDOR_NATIVE_CLEANUP candidate
- HF repo/snapshot → KEEP or VENDOR_NATIVE_CLEANUP candidate
- Raw shared blobs → never independent MOVE_TO_TRASH

---

## Required final answers (1–57)

1. **Implemented:** Vendor proof providers; reverse blob refs; shared/unique byte accounting; verification strategy wiring; UI explanations; P3.1 reports; P3.0.4 metric layer split; fixture tests; screenshots; real Mac read-only rescan.
2. **Changed files (major):**
   - `Sources/SafetyCore/Verification/VendorStorageProofModels.swift`
   - `Sources/SafetyCore/Verification/OllamaStorageProofProvider.swift`
   - `Sources/SafetyCore/Verification/HuggingFaceStorageProofProvider.swift`
   - `Sources/SafetyCore/Verification/EntityVerificationModels.swift`
   - `Sources/SafetyCore/Verification/VerificationCandidateBuilder.swift`
   - `Sources/SafetyCore/Verification/VerificationStrategies.swift`
   - `Sources/SafetyCore/Verification/ProofFeasibility.swift`
   - `Sources/SafetyCore/Detectors/AIToolDeepDetector.swift`
   - `Sources/SafetyCore/Action/ActionPolicy.swift`
   - `Sources/SafetyCore/Action/ActionSafetyEvaluator.swift`
   - `Sources/SafetyCore/Action/ActionRecommendationEngine.swift`
   - `Sources/SafetyCore/Action/ActionModels.swift`
   - `Sources/SafetyCore/Models/EvidenceObservation.swift`
   - `Sources/SafetyCore/Scanner/ScanSessionContext.swift`
   - `Sources/SafetyCore/Intelligence/ReadOnlyAnalysisPipeline.swift`
   - `Sources/AppServices/StorageExperience/P304ScanPerformance.swift`
   - `Sources/AppServices/StorageExperience/P31ProofReports.swift`
   - `Sources/AppServices/UICandidateMapper.swift`
   - `Sources/AIStorageManagerUI/Details/EntitySelectionPanel.swift`
   - `Sources/AIStorageManagerUI/OverviewScreenshotExport.swift`
   - `Sources/StorageIntel/main.swift`
   - `Tests/SafetyCoreTests/P31VendorStorageProofTests.swift`
   - `Tests/AppServicesTests/P31OptimizationVendorFutureTests.swift`
   - `tasks.md`
3. **Tests before:** 394 / 0 failures
4. **Tests after:** 409 / 0 failures (+15 P3.1)
5. **Failures:** 0
6. **False GREEN:** 0
7. **duplicateEvaluations:** 0
8. **P3.0.4 metric inconsistency root cause:** `cacheHits`/`cacheMisses` mixed measurement-cache + ScannedNode-cache, while `measurementRequests` counted only `measure()` callers → hits+misses ≠ requests.
9. **Measurement metric definitions after fix:**
   - `measurementRequests` = `measure()` caller count
   - `measurementCacheHits` + `measurementCacheMisses` = size-cache layer only
   - `nodeCacheHits` / `nodeCacheMisses` = ScannedNode layer
   - `cacheHits` / `cacheMisses` = aggregated totals across both layers
   - semantics string recorded in `p3_0_4_scan_performance.json`
10. **First-map regression:** live `timeToFirstUsefulMapMs=546` vs prior ~1021 → improved (not regressed)
11. **HF entity model:** Hub root → Repository (`models--org--name`) → Snapshot/revision → Blobs (symlink targets); reverse shared-blob index
12. **HF real entity count:** 1 hub + 1 repository + 1 snapshot
13. **HF observed bytes:** ~3.084 GB
14. **HF shared bytes known:** 0 on this Mac (single revision)
15. **HF unique bytes known:** ~3.084 GB
16. **HF origin/revision proof:** local repo id + commit/ref VERIFIED; remote availability UNKNOWN
17. **HF reacquisition proof:** UNKNOWN (default path no network; failure stays UNKNOWN, never FALSE/TRUE by assumption)
18. **HF top unresolved predicates:** `REACQUISITION_REMOTE_UNKNOWN`, executor unavailable, root not auto-cleanable
19. **HF ActionDecision distribution:** VERIFY_MORE / USER_REVIEW; MOVE_TO_TRASH blocked (`APPLICATION_MANAGED_DATA`); VENDOR_NATIVE preferred but not eligible without remote reacquisition VERIFIED
20. **Ollama entity model:** Models root → Model (manifest tag) → Blobs via digests; reverse index blob→models
21. **Ollama real model count:** 1 (`library/qwen3:4b`)
22. **Ollama observed bytes:** ~2.497 GB
23. **Ollama shared blobs:** 0 on this Mac (exclusive layers)
24. **Ollama unique bytes:** ~2.497 GB
25. **Ollama reference-graph completeness:** VERIFIED for installed model
26. **Ollama runtime proof:** service process may be INFERRED; model ACTIVE never claimed from service alone → UNKNOWN
27. **Ollama origin/reacquisition proof:** local origin identity VERIFIED; remote reacquisition UNKNOWN
28. **Ollama top unresolved predicates:** `REACQUISITION_REMOTE_UNKNOWN`, `VENDOR_NATIVE_CLEANUP_EXECUTOR_UNAVAILABLE`
29. **Ollama ActionDecision distribution:** VERIFY_MORE; trash blocked; vendor-native preferred; not Ready Now
30. **Raw blob actions permitted?** **No**
31. **User-original protection:** custom/local Ollama suspect → KEEP; unrecognized HF hub files protected
32. **Vendor CLI calls:** 0
33. **Network calls:** 0 (default path)
34. **Proof budget:** late/bounded; live HF ~4ms, Ollama ~20ms; first map independent
35. **Verified claim count before/after:** vendor claims sparse → live `proofClaimsVerified=10` / `attempted=14`
36. **Verify More bytes before:** ~5.6 GB (HF+Ollama unresolved class)
37. **Verify More bytes after:** HF ~3.08 GB + Ollama ~2.50 GB still non-actionable (eligibility unresolved); semantic identity/refs improved
38. **Verified Future bytes before:** ~107 MB
39. **Verified Future bytes after:** ~103.5 MB (DerivedData-class future; AI vendors not promoted without remote reacquisition VERIFIED)
40. **Ready Now before:** 0
41. **Ready Now after:** 0
42. **Why Ready did not change:** executor = MOVE_TO_TRASH only; AI vendor trash blocked; VENDOR_NATIVE not eligible without remote reacquisition VERIFIED; capability = NOT_IMPLEMENTED
43. **20GB Optimization Plan result:** still needs more verification; Ready Now 0; Verified Future ~103.5 MB
44. **Growth history used for Safety?** No
45. **secondCrawlerAdded:** false
46. **Safety rules loosened?** No
47. **New exact vendor rules:** proof adapters + narrow ActionPolicy/Evaluator gates only; KB not broadly expanded; reconstructed KB remains PROVISIONAL
48. **Executor scope:** MOVE_TO_TRASH only
49. **New mutation APIs:** none
50. **First-map performance:** 546 ms (live)
51. **Safety completion performance:** ~106 s (live)
52. **Proof reports:**
    - `reports/case001/p3_1_proof_coverage.json`
    - `reports/case001/p3_1_ai_model_inventory.json`
    - `reports/case001/p3_1_candidate_inventory_before_after.json`
    - `reports/case001/p3_1_proof_performance.json`
53. **Screenshot paths:**
    - `reports/case001/screenshots/ai_models_p31_huggingface_detail.png`
    - `reports/case001/screenshots/ai_models_p31_ollama_shared_storage.png`
    - `reports/case001/screenshots/optimization_plan_p31_verified_future.png`
54. **tasks.md:** P3.1 marked DONE
55. **Known limitations:**
    - remote reacquisition not verified offline
    - AI models do not enter Verified Future without remote TRUE
    - this Mac HF has single revision (no cross-snapshot sharing observed)
    - no VENDOR_NATIVE executor yet
56. **git commit created?** **No**
57. **Recommended next phase:**
    - Prefer **P3.1.x — bounded remote reacquisition proof** first
    - If remote proof later verifies significant exclusive unique bytes → **P3.2 VENDOR_NATIVE_CLEANUP Executor**
    - Do **not** choose next phase by feature attractiveness
    - Choose by verified bytes × safety maturity × blast radius × user value

---

## Hard invariants preserved

- FALSE GREEN IS A CRITICAL BUG → 0
- UNKNOWN never auto-promotes to GREEN
- INFERRED cannot satisfy strict predicates
- absence of evidence ≠ negative evidence
- CACHE NAME ≠ AUTOMATIC GREEN
- REGENERABLE ≠ ALWAYS SAFE
- NATIVE CLEANUP > RAW DELETE
- CLASS > SCORE
- PATH ALONE IS NOT SAFETY
- secondCrawlerAdded = false
- no new mutation executor

---

## Principle

KNOW MORE ≠ DECLARE MORE SAFE.

Turned:
“3.1 GB mysterious AI storage”
into:
“we know what it is, what depends on it, what is shared/unique, what could maybe be reacquired, and what we still cannot prove.”

That is Proof Coverage.

---

## Ask for ChatGPT

Please review this P3.1 handoff against the original P3.1 brief.  
Confirm DONE conditions.  
Then recommend the single next phase (P3.1.x vs P3.2 A/B/C/D) based on **real verified inventory**, not attractiveness.
