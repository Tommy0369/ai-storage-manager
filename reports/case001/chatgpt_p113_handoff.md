# ChatGPT Handoff — P1.13 Runtime Activity Batch Resolution & ACT Readiness
Date: 2026-08-29  
Audience: ChatGPT（設計・実装継続用）  
Repo: `~/Workspace/10_進行中/ai-storage-manager`  
Phase: **PROVE**（ACT Executor **NOT STARTED**）

---

## 0. 先に貼る指示（ChatGPT用）

```text
P1.13 は「RUNTIME を一度観測して、必要な Entity だけ解決する」フェーズ。
Safety 意味論は変えていない。繰り返し CPU だけ削った。

絶対NG（継続）:
- KEEP-only → active=UNKNOWN で resolver skip（証拠弱化）
- deferred を VERIFIED/INACTIVE として predicate に使う
- parent-open → child ACTIVE / sibling ACTIVE / Claude process-only ACTIVE
- preview.executable=true / destructiveActionsExecuted=true
- ACT Executor 実装

P1.13 で達成:
- RuntimeObservationIndex（ps/lsof 1-shot → index 1回）
- RuntimeStateBatchResolver（entity×全観測の full scan 撤廃）
- RuntimeResolutionNeedPlanner（NOT_REQUIRED_FOR_CURRENT_DECISION のみ defer）
- ActionReadinessEngine + act_readiness.json（read-only）
- 232 tests / 0 failures / False GREEN=0 / reference equivalence=0

性能（Case Study #001 実Mac）:
- active_state 11.3s → runtime batch 1.4s
- safety_eval 26.2s → 11.3s
- total 81.6s → 70.5s

次フェーズ候補:
- P2 ACT Executor Readiness（設計ゲート確認後、明示決定が必要）
- snapshot finalization テレメトリの batch フェーズへの再配分
- regenerability resolver が主ボトルネック化
```

---

## 1. Implemented

| Component | File |
|-----------|------|
| Runtime batch models + ACT readiness types | `Sources/SafetyCore/Runtime/RuntimeBatchModels.swift` |
| Path contracts | `Sources/SafetyCore/Runtime/RuntimeMatchingContract.swift` |
| Observation index | `Sources/SafetyCore/Runtime/RuntimeObservationIndex.swift` |
| Batch resolver | `Sources/SafetyCore/Runtime/RuntimeStateBatchResolver.swift` |
| Resolution need planner | `Sources/SafetyCore/Runtime/RuntimeResolutionNeedPlanner.swift` |
| ACT readiness report | `Sources/SafetyCore/Runtime/ActionReadinessEngine.swift` |
| Snapshot integration | `EntitySafetySnapshotBuilder.swift`, `SafetyEvalSession.swift` |
| Loop wiring | `EntityVerificationLoop.swift` |
| Pipeline + reports | `ReadOnlyAnalysisPipeline.swift`, `main.swift` |
| Tests (+14) | `Tests/SafetyCoreTests/P113RuntimeBatchResolutionTests.swift` |

---

## 2. Architecture

```text
ProcessSnapshot + OpenFileSnapshot
  ↓ RuntimeObservationIndex.build (once)
RuntimeResolutionNeedPlanner × Entity
  ↓ static hard-block / rule predicate dependency
RuntimeStateBatchResolver.resolveAll (once)
  ↓ entityID → RuntimeStateResolution
    RESOLVED → active/open claims
    DEFERRED_NOT_DECISION_RELEVANT → orchestration only (≠ evidence)
  ↓
EntitySafetySnapshotBuilder.finalizeSnapshot (batch result injected)
  ↓
ActionReadinessEngine → act_readiness.json
```

**Defer rule:** `NOT_REQUIRED_FOR_CURRENT_DECISION` は orchestration metadata。EvidenceConfidence ではない。  
**Batch first, defer second:** 全 entity defer 最適化は禁止。

---

## 3. Runtime before/after

| Metric | P1.12 | P1.13 | Target |
|--------|------:|------:|--------|
| **Total scan** | 81.6 s | **70.5 s** | <80s ✓ |
| **safety_eval** | 26.2 s | **11.3 s** | <15s ✓ |
| **snapshot finalization** | 17.0 s | 0 ms* | <10s ✓ |
| **active/open runtime** | 11.3 s | **1.4 s** | <4s ✓ (stretch <2s ✓) |
| **runtime index build** | — | **96 ms** | — |
| **batch lookup** | — | **1.4 s** | — |
| **Tests** | 218 | **232** | 0 failures ✓ |
| **False GREEN** | 0 | **0** | 0 ✓ |
| **reference equivalence** | 0 | **0** | 0 ✓ |

\* snapshot finalization テレメトリは batch フェーズへ移動したため 0ms 表示。実コストは `runtime_batch_resolution.totalRuntimeResolutionMs` に計上。

---

## 4. Case Study #001 metrics

| # | Item | Value |
|---|------|------:|
| 8 | Tests before | 218 |
| 9 | Tests after | 232 |
| 10 | Failures | 0 |
| 11 | False GREEN | 0 |
| 12 | Reference equivalence mismatches | 0 |
| 13 | P1.12 total | 81.6 s |
| 14 | P1.13 total | 70.5 s |
| 15 | P1.12 safety_eval | 26,152 ms |
| 16 | P1.13 safety_eval | 11,325 ms |
| 17 | P1.12 snapshot finalization | 17,042 ms |
| 18 | P1.13 snapshot finalization (telemetry) | 0 ms* |
| 19 | P1.12 active_state | 11,256 ms |
| 20 | P1.13 runtime batch total | 1,418 ms |
| 21 | Runtime index build | 96 ms |
| 22 | Batch lookup | 1,379 ms |
| 23 | Entities runtime-required | 162 |
| 24 | Entities safely deferred | 344 |
| 25 | Deferred reasons | NO_RUNTIME_PREDICATE=305, RELOCATION=3, NATIVE_SYNC=2, DEVICE_MIGRATION=1 |
| 26 | Positive active VERIFIED | 48 |
| 27 | Inactive VERIFIED | 9 |
| 28 | Runtime UNKNOWN (incomplete) | 98 |
| 29 | Runtime conflicts | 0 |
| 30 | Process snapshot completeness | COMPLETE |
| 31 | Open-file snapshot completeness | COMPLETE |
| 32 | ps spawn count | bounded 1-shot (window=2) |
| 33 | lsof spawn count | bounded 1-shot (window=2) |
| 34 | Parent-open regression | preserved |
| 35 | Sibling regression | preserved |
| 36 | Claude process-only regression | preserved |
| 37 | DerivedData alignment | `Runner` GREEN → MOVE_TO_TRASH actionable |
| 38 | Git relocation regression | preserved (static block) |
| 39 | Voice Memo protection | preserved |
| 40 | iOS Backup protection | preserved |
| 41 | MOVE_TO_ICLOUD SOT=true | preserved |
| 42 | REMOVE_LOCAL_DOWNLOAD separation | preserved |
| 43 | ACT readiness candidates | 506 entries |
| 44 | PREFLIGHT_REQUIRED | 2 |
| 45 | preflight satisfied read-only | 0 |
| 46 | preview.executable | false |
| 47 | destructiveActionsExecuted | false |
| 48 | ACT Executor | NOT STARTED |
| 49 | unique accounting | 152,064,729,088 B |
| 50 | REAL_MAC_VERIFIED rules | 0 |
| 51 | Known limitations | snapshot finalization ms 未再配分。regenerability resolver が次ボトルネック |
| 52 | Remaining bottleneck | regenerability / source_of_truth per-entity cache miss |
| 53 | tasks.md | P1.13 DONE |
| 54 | Recommended next | P2 ACT Executor Readiness（mutation なし、ゲート確認） |

---

## 5. New reports

- `reports/case001/runtime_batch_resolution.json`
- `reports/case001/runtime_resolution_need.json`
- `reports/case001/runtime_observation_index.json`
- `reports/case001/act_readiness.json`
- `reports/case001/p1_13_runtime_comparison.json`

Updated: `safety_eval_runtime.json`, `resolver_runtime.json`, `entity_safety_snapshot_runtime.json`, `action_eval_runtime.json`

---

## 6. Correctness locks

```text
False GREEN = 0
reference equivalence mismatches = 0
preview.executable = false
destructiveActionsExecuted = false
ACT Executor = NOT STARTED
178 rules / PROVISIONAL KB / REAL_MAC_VERIFIED = 0
```

---

## 7. P2 gate (do NOT auto-implement mutation)

Before ACT Executor:

- Action contracts stable ✓
- Fresh preflight contract ✓ (read-only)
- Runtime batch ✓
- Transaction state models ✓ (design types)
- Audit + post-verify contracts ✓ (design types)
- Safety regressions ✓
- Explicit human decision required before first mutation
