# P2.0.1 Handoff — Real Mutation Candidate Closure & Action Pipeline De-duplication

Phase: **ACT READINESS**  
ACT Executor: **NOT STARTED**  
Mutation: **STRICTLY FORBIDDEN**

---

## 1. Implemented

- `ActionDecisionSet` + `ActionDecisionCatalog` + `ActionDecisionBuilder` — canonical immutable decisions per snapshot generation
- Pipeline refactored: **one** `buildCatalog()` → Recommendation / Preflight / Readiness / MutationGate all reuse same map
- Telemetry: `action_safety_eval_dedup.json` with `duplicateEvaluations=0`
- `DerivedDataMutationReadinessAnalyzer` — gate-by-gate funnel for **all** DerivedData catalog entities (not recommendation-filtered)
- `MutationCandidateFunnel`, `P21GateStatusEvaluator`, `P201RuntimeComparison`
- Reports wired in `main.swift`
- Tests: `P201ActionDecisionDedupTests` (+6)

## 2. Changed files

| Area | Files |
|------|-------|
| Action | `ActionDecisionSet.swift`, `ActionRecommendationEngine.swift`, `ActionPreflightEngine.swift` |
| Mutation | `DerivedDataMutationReadinessAnalyzer.swift`, `MutationCandidateFunnel.swift`, `P21GateStatus.swift` |
| Pipeline | `ReadOnlyAnalysisPipeline.swift`, `EntityVerificationLoop.swift` |
| CLI | `main.swift` |
| Tests | `P201ActionDecisionDedupTests.swift` |
| Docs | `tasks.md` |

## 3. Canonical ActionDecision architecture

```text
EntitySafetySnapshot
→ ActionDecisionBuilder.buildCatalog()  [ONCE]
→ ActionDecisionSet per entity
→ ActionRecommendationEngine.recommend(decisionCatalog:)
→ ActionPreflightEngine.preview(decisionCatalog:)
→ ActionReadinessEngine.buildReport(actionDecisions: catalog map)
→ MutationGate.buildReport(actionDecisions: catalog map)
→ DerivedDataMutationReadinessAnalyzer(decisionCatalog:)
```

## 4–6. ActionSafetyEvaluator / dedup

| Metric | Before P2.0.1 | After P2.0.1 |
|--------|---------------|--------------|
| Pipeline evaluateAll passes | ~4× (recommend + preflight + 2× buildActionDecisionMap) | **1×** catalog build |
| `actionSafetyEvaluatorInvocations` | ~4×2510 ≈ 10040 (estimated) | **2510** |
| `duplicateEvaluations` | >0 (duplicate work) | **0** |
| `decisionReuseCount` | 0 | **2008** (502×4 downstream consumers) |

## 7–9. Tests

| | Count |
|--|-------|
| Before | 248 |
| After | **254** |
| Failures | **0** |

## 10–15. Safety locks

| Lock | Value |
|------|-------|
| False GREEN | **0** |
| Reference equivalence mismatches | **0** |
| preview.executable | **false** |
| destructiveActionsExecuted | **false** |
| ACT Executor | **NOT STARTED** |
| actualMutationImplementations | **0** |

## 16–21. Runtime

| Phase | Total | safety_eval |
|-------|-------|-------------|
| P1.13 | 70.5s | 11.3s |
| P2.0 | ~117s | ~25s |
| P2.0.1 | **97.5s** | **24.0s** |

P2.0.1 stage breakdown (ms): actionDecisionBuild **3692**, recommendation **19**, preflight **7**, readiness **11**, mutationGate **4**, runtimeBatch **2775**.

Duplicate evaluation removal did **not** fully restore P1.13 safety_eval — remaining gap is entity snapshot / verification loop cost, not duplicate ActionSafety.

## 22–26. DerivedData (real Mac)

| Metric | Value |
|--------|-------|
| Entities discovered | **1** (`xcode.derived_data` root) |
| MOVE_TO_TRASH Safety GREEN | **0** |
| Recommended MOVE_TO_TRASH | **0** |
| PREFLIGHT_REQUIRED | **0** |
| APPROVAL_REQUIRED | **0** |
| CONTRACT_SATISFIED_READ_ONLY | **0** |

**Note:** P1.12 actionable entity `xcode.deriveddata.Runner-ckovnoskqurramhgydmrtirfscgd` is **not present** in current semantic catalog — only DerivedData root folder scanned.

## 27–30. Blocker analysis

**First blocking gate:** `derived_from_workspace_verified`  
**All failing steps:** derived_from, source exists, SOT false verified, regen true verified, MOVE_TO_TRASH GREEN  
**Root cause category:** `EVIDENCE_FRESHNESS_CHANGED` / `REGENERABILITY_PROOF_CHANGED`  
**Previous (P1.12):** Runner DerivedData → GREEN → MOVE_TO_TRASH → PREFLIGHT_REQUIRED  
**Current:** root entity → UNKNOWN → KEEP → BLOCKED  
**Why:** Individual DerivedData children with info.plist proof not enriched this scan; root lacks workspace relationship + SOT/regen VERIFIED proofs.

## 31–35. Mutation funnel / gate

| Stage | Count |
|-------|-------|
| entities scanned | 502 |
| mutation_gate entries | **1** (MOVE_TO_ICLOUD `user.downloads`, PREFLIGHT_REQUIRED) |
| MOVE_TO_TRASH candidates | **0** |
| REMOVE_LOCAL_DOWNLOAD candidates | **0** |

## 36–41. Protection corpus

All preserved (KEEP / blocks unchanged in recommendations): Voice Memo, iOS Backup, Git iCloud block, Claude KEEP/VERIFY_MORE, MOVE_TO_ICLOUD SOT=true, REMOVE_LOCAL_DOWNLOAD ≠ DELETE.

## 42–47. Contracts / audit

- Transaction / post-verify / audit contracts: available for DerivedData trash path when entity qualifies
- `mutation_surface_audit`: **PASSED**, actualMutationImplementations=**0**
- unique accounting: valid
- REAL_MAC_VERIFIED: individual DerivedData proof entities **0** this scan

## 48. Known limitations

- Real Mac catalog exposes DerivedData as **root aggregate** only; lightweight proof did not surface per-project folders this run
- safety_eval still ~24s (verification loop dominates post-dedup)
- P2.1 blocked until a **real** DerivedData entity with full strict proof reaches APPROVAL_REQUIRED or CONTRACT_SATISFIED_READ_ONLY

## 49. p2_1_gate_status

```json
{
  "status": "BLOCKED_BY_REAL_EVIDENCE",
  "realDerivedDataCandidates": 0,
  "approvalRequired": 0,
  "contractSatisfiedReadOnly": 0,
  "topBlockers": [
    "SOURCE_OF_TRUTH",
    "derived_from_workspace_verified",
    "regenerable_true_verified",
    "SAFETY_CLASS_UNKNOWN"
  ],
  "executorImplemented": false,
  "previewExecutable": false,
  "destructiveActionsExecuted": false
}
```

## 50. tasks.md

P2.0.1 → **DONE** (architecture). P2.1 → **blocked** pending real DerivedData proof candidate.

## 51. Recommended next step

**Do not implement Executor.**

Option A (preferred): Re-run Case Study when Xcode is closed **and** DerivedData proof enrichment surfaces at least one child entity with VERIFIED workspace + SOT FALSE + regen TRUE — confirm funnel reaches APPROVAL_REQUIRED without weakening Safety.

Option B: If proof budget consistently skips DerivedData children, investigate **verification loop yield** for DerivedData proof targets (read-only transport only — no predicate relaxation).

Human authorization for P2.1 remains **withheld** until `p2_1_gate_status.status = READY_FOR_HUMAN_AUTHORIZATION`.
