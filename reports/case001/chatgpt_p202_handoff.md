# P2.0.2 Handoff — DerivedData Proof Surface Recovery & Root-Cause Closure

Phase: **ACT READINESS**  
P2.1 Gate: **BLOCKED_BY_REAL_EVIDENCE**  
ACT Executor: **NOT STARTED**  
Mutation: **STRICTLY FORBIDDEN**

---

## Executive Summary

**Root cause: REAL_STATE_CHANGED (Outcome C)**

Historical Runner DerivedData directories **no longer exist** on disk. Current `~/Library/Developer/Xcode/DerivedData` is **empty** (0 Product-hash children). Detector architecture is **not regressed** — `XcodeDerivedDataProofDetector` ran with `matchCount=0` because there is nothing to match.

P2.1 remains blocked for the **correct reason**: no current real DerivedData proof entity exists.

---

## 1. Implemented

- `DerivedDataSurfaceAnalyzer` — filesystem → scanner → detector → entity → proof funnel
- Reports: `deriveddata_surface_funnel.json`, `deriveddata_detector_registration.json`, `deriveddata_surface_root_cause.json`
- Sanitized fixture: `Tests/Fixtures/ProofCases/DerivedData/info.plist.template`
- Tests: `P202DerivedDataSurfaceTests.swift` (+9)
- `tasks.md` updated

## 2. Changed files

| Area | Files |
|------|-------|
| Mutation | `DerivedDataSurfaceAnalyzer.swift` |
| Pipeline | `ReadOnlyAnalysisPipeline.swift` |
| CLI | `main.swift` |
| Tests | `P202DerivedDataSurfaceTests.swift` |
| Fixtures | `Tests/Fixtures/ProofCases/DerivedData/info.plist.template` |
| Docs | `tasks.md` |

## 3. Historical path check (read-only)

| Path | Status |
|------|--------|
| `Runner-ecnbmvkdltyrtnevcspalufxjhdq` | **NO_LONGER_EXISTS** |
| `Runner-ckovnoskqurramhgydmrtirfscgd` | **NO_LONGER_EXISTS** |

## 4. Current filesystem truth

| Metric | Value |
|--------|-------|
| DerivedData root exists | yes |
| Direct child count | **0** |
| Historical still exist | **0/2** |

## 5. Detector registration (verified, not regressed)

| Detector | Tier | Enabled | matchCount |
|----------|------|---------|------------|
| XcodeDetector | CORE | yes | 4 |
| XcodeDerivedDataProofDetector | OPT_IN_PROOF | yes (default `derived-data`) | **0** |

Default `storage-intel scan` includes `proof=derived-data`. Detector ran; zero matches = empty directory.

## 6. Funnel counts (real Mac)

| Stage | Count |
|-------|-------|
| filesystem children | 0 |
| detector matched | 0 |
| entity emitted | 0 |
| proof candidates | 0 |
| concrete semantic entities | 0 |
| root entity surfaced | 1 (`xcode.derived_data`) |

## 7. Root cause classification

```json
{
  "classification": "REAL_STATE_CHANGED",
  "secondaryClassifications": ["EXPECTED_CURRENT_BEHAVIOR"],
  "architecturalFixRequired": false,
  "architecturalFixMade": false
}
```

**Not** DETECTOR_REGRESSION, CATALOG_ROUTING, ENTITY_DEDUP, or REPORTING regression.

## 8. P2.1 gate

```json
{
  "status": "BLOCKED_BY_REAL_EVIDENCE",
  "realDerivedDataCandidates": 0,
  "approvalRequired": 0
}
```

Implication: `NO_CURRENT_REAL_DERIVEDDATA_PROOF_ENTITY`

## 9. Safety locks (preserved)

| Lock | Value |
|------|-------|
| Tests | **263 / 0 failures** (was 254) |
| duplicateEvaluations | **0** |
| False GREEN | **0** |
| preview.executable | **false** |
| destructiveActionsExecuted | **false** |
| actualMutationImplementations | **0** |
| ActionDecisionSet canonical | **preserved** |

## 10. Regression fixture proof

Sanitized temp-dir tests confirm when children **do** exist:

- root + concrete child both surface
- metadata absent → entity surfaces, proof UNKNOWN
- explicit WorkspacePath + source exists → VERIFIED relationship
- missing source → relationship present but `.missing`
- multiple children remain distinct

## 11. Architectural fix

**None required.** Gate was correct; evidence was absent.

## 12. Recommended next step

1. **Do not implement Executor**
2. When Xcode builds again, DerivedData children will reappear — re-run Case Study
3. If children exist but fail to surface → re-open P2.0.2 funnel (now instrumented)
4. Optional: investigate **why DerivedData was cleared** (user cleanup / Xcode / time) — out of scope for Safety architecture

Human P2.1 authorization withheld until real entity reaches gate with strict proof.
