# AI Storage Manager — P2.0.4 Handoff (ChatGPT)

**Phase:** ACT READINESS  
**Date:** 2026-09-01  
**Repo:** `~/Workspace/10_進行中/ai-storage-manager`

---

## P2.0.4 Objective

Validate whether a naturally generated real DerivedData entity traverses the existing UNDERSTAND → VERIFY → PROVE → MutationGate pipeline correctly.

**NOT asked:** "How can we make it pass?"

---

## Implementation Summary

### New Component

`RealCandidateRevalidationAnalyzer` — read-only diagnostic that:

- Combines `DerivedDataSurfaceFunnel` + `DerivedDataMutationReadiness` + `FirstRealMutationGate`
- Reports per-child end-to-end diagnostic (entityID, proof states, blockers, contracts)
- Classifies outcome: A/B/C/D
- Classifies blockers: REAL_RUNTIME_STATE_BLOCK, SOT_PROOF_INCOMPLETE, etc.
- **Never creates entities, never launches Xcode, never generates ExecutionPermit**

### New Report

`reports/case001/p2_0_4_real_candidate_revalidation.json`

Key flags:
- `humanSetupExpected = true`
- `storageManagerCreatedCandidate = false`
- `executionPermitGenerated = false`

### Tests Added

`P204RealCandidateRevalidationTests.swift` (+7 tests)

---

## Real Mac Scan Results (2026-09-01)

| Metric | Value |
|--------|-------|
| Tests before | 270 |
| Tests after | **277** |
| Failures | **0** |
| False GREEN | **0** |
| duplicateEvaluations | **0** |
| preview.executable | **false** |
| destructiveActionsExecuted | **false** |
| ACT Executor | **NOT STARTED** |
| actualMutationImplementations | **0** |
| mutation_surface_audit | **PASSED** |

### DerivedData State

| Metric | Value |
|--------|-------|
| Xcode build performed by human | **NO** (awaiting human setup) |
| DerivedData root exists | **YES** |
| DerivedData direct child count | **0** |
| newly observed children | **[]** |
| semantic child count | **0** |
| proof candidate count | **0** |
| Historical Runner entities | **NO_LONGER_EXISTS** |

### P2.0.4 Outcome

**Outcome D: TEST_SETUP_INCOMPLETE**

```
No DerivedData direct children on filesystem.
Human Xcode build required before revalidation.
storageManagerCreatedCandidate=false.
```

### Gate Status (unchanged)

```
FIRST_REAL_MUTATION_GATE = NO_SAFE_REAL_MUTATION_CANDIDATE
selectedCandidate = null
approvalRequired = 0
rankingEligibleCount = 0
preflightRequiredCount = 2
```

---

## Safety Locks (all preserved)

- ActionDecisionSet = canonical single source
- duplicateEvaluations = 0
- Voice Memo → KEEP
- iOS Backup → KEEP / REVIEW
- Git generic iCloud relocation → blocked
- Claude VM → KEEP / VERIFY_MORE
- Cursor internal state → protected
- MOVE_TO_ICLOUD SOT=true → preserved
- REMOVE_LOCAL_DOWNLOAD != DELETE
- Downloads root → ENTITY_GRANULARITY_TOO_BROAD

---

## Human Action Required

Before next revalidation:

1. Perform ONE ordinary Xcode build of an existing project (human-initiated, not Storage Manager)
2. Re-run read-only pipeline:

```bash
cd ~/Workspace/10_進行中/ai-storage-manager
python3 tools/compile_knowledge_base.py
swift test
swift run storage-intel scan
```

3. Check `p2_0_4_real_candidate_revalidation.json` for outcome A/B/C

### Possible Outcomes After Human Build

| Outcome | Meaning | Next Step |
|---------|---------|-----------|
| **A** READY_FOR_HUMAN_AUTHORIZATION | Strict proof passes | **STOP** — human authorization only gate |
| **B** BLOCKED_BY_REAL_EVIDENCE | Entity surfaces but evidence blocks (Xcode running, etc.) | Report blocker; optional later scan after Xcode closes |
| **C** SEMANTIC_SURFACE_FAILURE | Filesystem exists but pipeline breaks | Investigate architectural regression |
| **D** TEST_SETUP_INCOMPLETE | No DerivedData generated | Repeat human build |

---

## Do NOT

- Implement Executor
- Generate ExecutionPermit
- Perform MOVE_TO_TRASH
- Launch Xcode from Storage Manager
- Create synthetic DerivedData entities
- Relax Safety predicates
- Auto-promote Downloads root

---

## Files Changed

- `Sources/SafetyCore/Mutation/RealCandidateRevalidationAnalyzer.swift` (new)
- `Sources/SafetyCore/Intelligence/ReadOnlyAnalysisPipeline.swift`
- `Sources/StorageIntel/main.swift`
- `Tests/SafetyCoreTests/P204RealCandidateRevalidationTests.swift` (new)
- `tasks.md`

---

## Recommended Next Step

**Human:** Run one ordinary Xcode build on an existing project.  
**Then:** Re-scan and evaluate `p2_0_4_real_candidate_revalidation.json`.

If outcome A → STOP at gate, request explicit human authorization.  
If outcome B → believe the evidence, report blockers.  
If outcome C → investigate pipeline regression only if filesystem+scanner both confirm child exists.
