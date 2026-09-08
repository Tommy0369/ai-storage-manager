# ChatGPT Handoff — P3.2A.4 Canonical Action-Safety Alignment

**Date:** 2026-09-04  
**Repo:** ai-storage-manager  
**Git:** NO COMMIT / NO PUSH  

---

## Verdict

**DONE — READY_FOR_MODEL_REMOVAL_AUTHORIZATION**

Exact action:

`library/qwen3:4b` × `VENDOR_NATIVE_CLEANUP`

is **ELIGIBLE** with **strictUnknown=0**.

Remaining gate: **USER_APPROVAL only**.

**MODEL REMOVAL NOT EXECUTED.**  
No approval object. No ExecutionPermit. No executor. No `ollama rm`.

---

## Required 53-point handoff

1. **Verdict:** DONE / READY_FOR_MODEL_REMOVAL_AUTHORIZATION  
2. **Exact target:** `ai.ollama.model.library.qwen3:4b` / `library/qwen3:4b`  
3. **Generic entity SafetyClass:** **RED** (KEEP/trash orientation)  
4. **KEEP recommendation:** **KEEP** (default recommendation)  
5. **MOVE_TO_TRASH decision:** **BLOCKED**  
6. **VENDOR_NATIVE_CLEANUP canonical decision:** **ELIGIBLE**  
7. **Action-specific Safety state/class:** UNKNOWN token (not GREEN; eligibility is `eligible` + predicates)  
8. **Exact strict required predicates:**  
   `ollama_model_identity_verified`, `reference_graph_verified`, `remote_reacquisition_fresh_verified`, `not_user_original_custom`, `exact_model_inactive_verified`, `ollama_native_cli_resolved`, `executor_capability_ollama_model`, `local_manifest_fingerprint_bound`, `transaction_contract`, `post_verify_contract`, `audit_contract`  
9. **Verified strict predicates:** all required (unknown=0)  
10. **Unknown strict predicates:** **[]**  
11. **Conflicted strict predicates:** **[]**  
12. **Remaining Safety blockers:** **[]** (technical)  
13. **Is approval the only remaining gate?** **Yes** → `USER_APPROVAL`  
14. **Why generic RED does/does not matter:** RED is the KEEP/trash entity class (application-managed). It is a **different action**. Vendor-native does not inherit KEEP RED as a hard block; it evaluates its own contract.  
15. **Why KEEP does/does not block native cleanup:** RecommendationEngine may still prefer KEEP. Recommendation ≠ Safety authorization. Exact ActionDecision authorizes the reviewable alternative.  
16. **REGENERABILITY required?** **No** (vendor-native contract)  
17. **REGENERABILITY current state:** UNKNOWN (irrelevant)  
18. **REACQUIRABILITY required?** **Yes**  
19. **REACQUIRABILITY current state:** REACQUIRABLE_VERIFIED_FRESH  
20. **Residual remote-label root cause:** Gate previously preferred stale snapshot verification over Fresh Preflight `item.verification`, and aliased missing remote to `REGENERABILITY_UNKNOWN`. Fixed: prefer live item; use `REACQUISITION_NOT_STRICT_VERIFIED`; filter soft residue at APPROVAL_REQUIRED.  
21. **Canonical remote state after fix:** REACQUIRABLE_VERIFIED_FRESH  
22. **Runtime:** INACTIVE / VERIFIED  
23. **Runtime fresh?** Yes  
24. **Reference graph:** VERIFIED  
25. **Manifest binding:** PRESENT / bound  
26. **Native interface:** RESOLVED_CLI  
27. **supportsRM:** Yes  
28. **Fresh Preflight:** APPROVAL_REQUIRED  
29. **Plan tier before:** PROTECTED / 0 potential  
30. **Plan tier after:** **APPROVAL_REQUIRED**  
31. **Plan potential bytes:** **2,497,293,931**  
32. **immediateExpectedRecoveryBytes:** **0**  
33. **verifiedRecoveredBytes:** **0**  
34. **Raw delete blocked?** Yes  
35. **HF executable?** No (NOT_IMPLEMENTED)  
36. **MutationGate uses exact action decision?** Yes  
37. **Permit rejects strict UNKNOWN?** Yes (`missingClaimTypes` / `blockedReasons` empty required)  
38. **Human boundary reached?** Yes  
39. **Real approval created?** **No**  
40. **ExecutionPermit created?** **No**  
41. **Executor invoked?** **No**  
42. **ollama rm executed?** **No**  
43. **Tests before:** 499  
44. **Tests after:** **507**  
45. **Failures:** 0  
46. **False GREEN:** 0  
47. **duplicateEvaluations:** 0  
48. **secondCrawlerAdded:** false  
49. **Reports:** `p3_2a_4_action_safety_alignment.json` + refreshed `p3_2a_3_plan_after_restore.json` / cleanup preflight  
50. **tasks.md:** P3.2A.4 DONE  
51. **Known limitations:** actionSpecificSafetyClass remains UNKNOWN as non-GREEN token; plan aggregate `approvalRequired` bytes bucket may still show 0 depending on entry selection math — Ollama-specific tier/bytes in plan-after-restore are aligned  
52. **git commit created?** **No**  
53. **Recommended exact next step:** ChatGPT requests **exact human authorization** for `library/qwen3:4b` × `VENDOR_NATIVE_CLEANUP` only. Then UserActionApproval → ExecutionPermit → `ollama rm` → PostVerify.

---

## Coexistence (valid)

```
RAW DELETE / MOVE_TO_TRASH: BLOCKED
KEEP: RECOMMENDED
VENDOR_NATIVE_CLEANUP: ELIGIBLE (USER_APPROVAL only)
```

Because Safety = Entity × Action × State.

---

## Stop line

```
target: library/qwen3:4b
action: VENDOR_NATIVE_CLEANUP
decision: ELIGIBLE
strictUnknown: 0
remaining: USER_APPROVAL
preflight: APPROVAL_REQUIRED
plan: APPROVAL_REQUIRED / 2,497,293,931 potential
immediateExpectedRecoveryBytes: 0
mutation: NONE
```
