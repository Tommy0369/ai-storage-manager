# ChatGPT Handoff — P2.0 Mutation Gate & Execution Contract Hardening
Date: 2026-08-29  
Audience: ChatGPT（設計・実装継続用）  
Repo: `~/Workspace/10_進行中/ai-storage-manager`  
Phase: **PROVE → ACT READINESS**（ACT Executor **NOT STARTED**）

---

## 0. 先に貼る指示（ChatGPT用）

```text
P2.0 は「mutation する権利があるか」を read-only で保証するフェーズ。
ファイル変更・Trash・iCloud・eviction は一切しない。

絶対NG:
- FileManager.removeItem / moveItem / copyItem（ACT実行）
- preview.executable=true
- destructiveActionsExecuted=true
- ExecutionPermit 生成
- Recommendation → Executor 直結

達成:
- MutationGate（14段階評価順）
- MutationReadiness（executable なし）
- ActionBindingFingerprint + PreflightReceipt + UserActionApproval（型のみ）
- TransactionContract / PostVerify / AuditContract
- DryRunActionPlan + mutation_surface_audit
- 248 tests / 0 failures / actualMutationImplementations=0

次: P2.1 First Mutating Executor — 明示的な人間承認後のみ。DerivedData 1 entity × MOVE_TO_TRASH のみ。
```

---

## 1. Architecture

```text
ActionRecommendationEngine
  ↓
ActionSafetyEvaluator → ActionDecision
  ↓
ActionPreflightEngine → ActionPreflightResult
  ↓
ActionReadinessEngine（P1.13、mutationReadiness 付与）
  ↓
MutationGate → MutationReadiness
  ↓
DryRunActionPlan（executorImplemented=false）
  ↓
[FUTURE] Fresh Preflight → UserActionApproval → ExecutionPermit → StorageActionExecutor
```

**Capability boundary:** `StorageActionExecutor` protocol only — no implementation.

---

## 2. MutationReadiness states

| State | Meaning |
|-------|---------|
| BLOCKED | Hard block / ineligible / conflict |
| VERIFY_MORE | More proof required |
| PREFLIGHT_REQUIRED | Fresh runtime/cloud preflight needed |
| APPROVAL_REQUIRED | Contracts OK read-only but no user approval |
| CONTRACT_SATISFIED_READ_ONLY | All read-only contracts satisfied — still NOT executable |

No `executable` state. `preview.executable=false` preserved.

---

## 3. Gate evaluation order

1. Hard product block  
2. Action supported  
3. Entity identity verified  
4. Action contract exists  
5. Action-specific Safety decision  
6. Static proof complete  
7. Runtime proof requirements  
8. Transaction contract  
9. Post-action verify contract  
10. Audit contract  
11. User approval requirement  
12. Fresh preflight requirement  
13. Binding validity  
14. CONTRACT_SATISFIED_READ_ONLY  

---

## 4. Case Study #001 (this run)

| Metric | Value |
|--------|------:|
| Tests | 248 / 0 failures |
| False GREEN | 0 |
| reference equivalence | 0 |
| preview.executable | false |
| destructiveActionsExecuted | false |
| ACT Executor | NOT STARTED |
| actualMutationImplementations | 0 |
| mutation_surface_audit | PASSED |
| Total scan | ~117 s* |
| safety_eval | ~25 s* |
| mutation_gate entries | 1 (actionable MOVE_TO_ICLOUD candidate) |
| PREFLIGHT_REQUIRED | 1 |
| APPROVAL_REQUIRED | 0 |
| CONTRACT_SATISFIED_READ_ONLY | 0 |

\* 今回 scan は環境負荷で P1.13 実測より遅い。P2.0 では性能最適化を中心にしていない。

**DerivedData:** 今回 Case Study では個別 DerivedData が GREEN→MOVE_TO_TRASH actionable にならず（KEEP 多数）。Gate 契約と単体テストで DerivedData strict path を検証済み。

---

## 5. New files

| File | Role |
|------|------|
| `Mutation/MutationGateModels.swift` | Types + reports |
| `Mutation/TransactionContractRegistry.swift` | MOVE_TO_TRASH / ICLOUD / EVICT contracts |
| `Mutation/ActionBindingFingerprint.swift` | Binding + PreflightReceipt + invalidation |
| `Mutation/MutationGate.swift` | Gate evaluator |
| `Mutation/DryRunActionPlanBuilder.swift` | Read-only step plans |
| `Mutation/MutationSurfaceAudit.swift` | Repo mutation surface scan |
| `Mutation/StorageActionExecutor.swift` | Protocol only |
| `Tests/P200MutationGateTests.swift` | +16 tests |

---

## 6. New reports

- `mutation_gate.json`
- `action_dry_run_plans.json`
- `act_executor_readiness_summary.json`
- `mutation_surface_audit.json`
- `act_readiness.json`（`mutationReadiness` フィールド追加）

---

## 7. Regression locks preserved

- Voice Memo / iOS Backup / Git / Claude → blocked  
- MOVE_TO_ICLOUD SOT=TRUE preservation  
- REMOVE_LOCAL_DOWNLOAD ≠ DELETE  
- deferred ≠ evidence (P1.13)  
- False GREEN = 0  

---

## 8. P2.1 gate (do NOT auto-implement)

All must hold + at least one real DerivedData candidate at CONTRACT_SATISFIED_READ_ONLY or APPROVAL_REQUIRED with full contracts → then **explicit human authorization** before first `MOVE_TO_TRASH` executor.

---

## 9. Handoff checklist (55 items summary)

| # | Item | Result |
|---|------|--------|
| 1–17 | Models + architecture | Implemented |
| 18–22 | Tests 232→248, failures 0 | ✓ |
| 23–24 | Runtime ~117s, safety ~25s | measured (no regression work) |
| 25–32 | Gate counts | 1 evaluated, PREFLIGHT_REQUIRED=1 |
| 33–39 | Regressions | preserved in tests |
| 40–45 | Contracts + audit | complete, audit=0 |
| 46–50 | Locks | all false/zero/NOT STARTED |
| 51–52 | KB 178 PROVISIONAL, REAL_MAC=0 | unchanged |
| 53 | Limitations | Double ActionSafetyEvaluator in pipeline; DerivedData not actionable this scan |
| 54 | tasks.md | P2.0 DONE |
| 55 | Next | P2.1 First Mutating Executor (explicit approval) |
