# ChatGPT Handoff — P1.12 Entity Safety Snapshot & Resolver Memoization
Date: 2026-08-29  
Audience: ChatGPT（設計・実装継続用）  
Repo: `~/Workspace/10_進行中/ai-storage-manager`  
Phase: **PROVE**（ACT Executor **NOT STARTED**）

---

## 0. 先に貼る指示（ChatGPT用）

```text
P1.12 は「Entity を一度理解して、複数 Action に使い回す」フェーズ。
Safety 意味論は変えていない。速度だけ変えた。

絶対NG（継続）:
- UNKNOWN→GREEN / INFERRED→strict predicate
- preview.executable=true / destructiveActionsExecuted=true
- ACT Executor 実装
- resolver 結果を Action decision として永続化

P1.12 で達成:
- EntitySafetySnapshot + finalizeSnapshot + evaluateActions
- proof verified claim → resolver skip
- DerivedData GREEN → MOVE_TO_TRASH 推薦整合
- 218 tests / 0 failures / False GREEN=0

未達:
- safety_eval <15s（実測 26.2s）
- 主ボトルネック = active_state resolver ~11.3s

次フェーズ P1.13 候補:
- active_state の process snapshot 単位バッチ解決
- runtime-sensitive でない entity への defer
- ACT readiness（read-only preflight 硬化、executor なし）
```

---

## 1. Implemented

| Component | File |
|-----------|------|
| EntitySafetySnapshot / EntityPredicateSnapshot | `Sources/SafetyCore/Engine/EntitySafetySnapshot.swift` |
| Snapshot builder + resolver memoization | `Sources/SafetyCore/Engine/EntitySafetySnapshotBuilder.swift` |
| Session snapshot cache + evaluateActions | `Sources/SafetyCore/Engine/SafetyEvalSession.swift` |
| Loop integration | `Sources/SafetyCore/Verification/EntityVerificationLoop.swift` |
| Proof→Safety verification cache | `Sources/SafetyCore/Verification/VerificationStrategies.swift` |
| Action layer snapshot consumption | `Sources/SafetyCore/Action/ActionSafetyEvaluator.swift` |
| Recommendation/preflight wiring | `ActionRecommendationEngine.swift`, `ActionPreflightEngine.swift` |
| Pipeline + reports | `ReadOnlyAnalysisPipeline.swift`, `main.swift` |
| Tests (+7) | `Tests/SafetyCoreTests/P112EntitySafetySnapshotTests.swift` |

---

## 2. Snapshot architecture

```text
Entity
  ↓ EvidenceResolutionCache（proof verified claims 引き継ぎ）
  ↓ finalizeSnapshot (SafetyEvalSession, once per entity)
EntitySafetySnapshot (immutable)
  ├ evidence + state + verification
  ├ EntityPredicateSnapshot（static predicates batched）
  └ cacheKey = entityID + evidenceVersion + verificationGen + runtimeGen
  ↓ evaluateActions(snapshot, includeCloudVariants?)
SafetyDecision × ActionMode (USER_REVIEW / MOVE_TO_TRASH / CLOUD_EVICT_ONLY)
  ↓ ActionSafetyEvaluator(snapshot, safetyDecisions)
ActionDecision × StorageAction
```

**Claim precedence:** canonical verified claim → resolver supplement → conflict → UNKNOWN  
**Action isolation:** MOVE_TO_TRASH SOT=FALSE contract ≠ MOVE_TO_ICLOUD preservation contract

---

## 3. Runtime before/after

| Metric | P1.11 | P1.12 | Target |
|--------|------:|------:|--------|
| **Total scan** | 87.1 s | **81.6 s** | <80s ✓ |
| entity_verification_loop | 31.0 s | 31.5 s | — |
| **safety_eval** | 25.5 s | **26.2 s** | <15s ✗ |
| proof_execution | 5.4 s | 5.3 s | — |
| snapshot_finalization | — | **17.0 s** | new |
| resolver time (active) | — | **11.3 s** | new bottleneck |

Stretch `<75s total`, `<10s safety_eval` — **NOT met**.

---

## 4. Resolver before/after

| Resolver | P1.11 calls | P1.12 invocations | Cache hits | Runtime before | Runtime after |
|----------|------------:|------------------:|-----------:|---------------:|--------------:|
| source_of_truth | ~506 | 506 | **21** | ~0ms* | ~0ms |
| regenerability | ~506 | 506 | **20** | ~0ms* | ~0ms |
| active_state | ~506 | 506 | **53** | ~25s† | **11256ms** |
| open_file | inline | snapshot内 | — | — | — |
| relationship | inline | annotation直接 | — | — | — |

\* P1.11 では finalizeResolvers 内で毎回呼び出し（計測分離なし）  
† P1.11 safety_eval 全体 ~25.5s の大部分が resolver + engine

**Slowest resolver:** `active_state` (median 26ms/entity, p95 29ms)  
**Slowest entities:** `claude.vm.bundle.*`, `appsupport.Code.cache`, `git.*`

---

## 5. Entity snapshot telemetry (`entity_safety_snapshot_runtime.json`)

| Metric | Value |
|--------|------:|
| entitiesFinalized | 506 |
| snapshotsCreated | 506 |
| snapshotCacheHits | 0 |
| snapshotCacheMisses | 506 |
| averageFinalizationMs | 33.7 |
| p95FinalizationMs | 47 |
| resolverContributionMs | 17042 |

snapshot cache hit=0 は正常（1 scan = 1 finalize/entity）。

---

## 6. Action eval telemetry (`action_eval_runtime.json`)

| Action | entities | avg rules | snapshot reuse | runtimeMs |
|--------|----------|-----------|----------------|----------:|
| USER_REVIEW | 506 | 2.19 | 506 | 2448 |
| MOVE_TO_TRASH | 5 | 1.6 | 5 | 0 |
| CLOUD_EVICT_ONLY | 5 | 1.6 | 5 | 0 |
| **Total** | **516** | — | **516** | — |

Action 層は snapshot + precomputed SafetyDecision を消費。engine 二重評価を回避。

---

## 7. Safety eval profiler (`safety_eval_runtime.json`)

| Metric | P1.11 | P1.12 |
|--------|------:|------:|
| entitiesEvaluated | 506 | 506 |
| actionsEvaluated | 516 | 516 |
| auditorInvocations | 506 | 506 |
| auditorSkippedNonGreen | 505 | 505 |
| fullGreenAudits | 1 | 1 |
| averageRulesPerEntity | 1.4 | 2.19‡ |
| resultCacheHits | 0 | 0 |
| staticPredicatesComputed | — | 506 |
| snapshotFinalizationMs | — | 17042 |

‡ cloud variant 含む全 action eval を rulesConsidered に計上したため上昇。lookup 自体は indexed。

---

## 8. Correctness KPIs（必須）

| KPI | Value |
|-----|-------|
| False GREEN | **0** |
| reference equivalence mismatches | **0** |
| preview.executable | **false** |
| destructiveActionsExecuted | **false** |
| unique accounting | **valid** |
| REAL_MAC_VERIFIED rules | **0**（変更なし） |
| Tests before | 211 |
| Tests after | **218** |
| Failures | **0** |

---

## 9. P2 regression corpus

| Case | Result |
|------|--------|
| **DerivedData GREEN alignment** | **FIXED** — `xcode.deriveddata.Runner-ckovnoskqurramhgydmrtirfscgd` → recommendedAction=**MOVE_TO_TRASH**, green_audit 一致 |
| Git MOVE_TO_ICLOUD | **FIXED** — icloud_move_candidates=0, generic block 維持 |
| Voice Memo protection | **PASS** — KEEP, native sync block |
| iOS Backup protection | **PASS** — KEEP, device-aware block |
| REMOVE_LOCAL_DOWNLOAD separation | **PASS** — != DELETE 維持 |
| MOVE_TO_ICLOUD SOT=true | **PASS** — preservation contract 維持 |
| Claude runtime | **PASS** — KEEP/verifyMore |

**DerivedData fix root cause:** Action 層が `ActionArchitecture.evidenceBundle(from:)` で openFileHandle を落としていた。P1.12 は snapshot.evidence をそのまま渡すよう修正。

---

## 10. Proof backlog（P1.11 から継続）

| Metric | P1.11 | P1.12 |
|--------|------:|------:|
| CursorMetadata attempts | 0 | 0 |
| verification yield | 42.6% | ~同程度 |
| claimsVerified | 49 | ~同程度 |
| claimsUnknown | 5 | ~同程度 |

KB: **178 rules**, PROVISIONAL reconstructed canonical（provenance 維持）

---

## 11. Locks maintained

```text
preview.executable = false
destructiveActionsExecuted = false
False GREEN = 0
reference equivalence = 0
ACT Executor = NOT STARTED
```

---

## 12. Known limitations

1. **safety_eval 微増**（25.5→26.2s）— snapshot 構築オーバーヘッドが active resolver 削減を上回った
2. **active_state が残ボトルネック** — 453 misses, 11.3s（safety_eval の ~43%）
3. resultCacheHits=0 — entity×action 一意評価のため正当（無理に hit を増やさない）
4. snapshotCacheHits=0 — 1 scan 1 finalize が正常パターン
5. L5 actionable = 0%（変更なし）
6. REAL_MAC_VERIFIED = 0（変更なし）

---

## 13. Remaining safety_eval bottleneck（計測済み）

```text
snapshot finalization   17.0s (100%)
  └ active_state resolver  11.3s (66%)
  └ SOT/regen (verified cache hit) ~0ms
  └ predicate batch + state build     ~5.7s
engine evaluate (516 actions)        ~2.4s
green auditor (1 full)               ~0ms
```

**次に切るべきは active_state。** SOT/regen は proof verified cache で解決済み。

---

## 14. Recommended P1.13

1. **RuntimeSnapshotBatch** — ProcessSnapshot/OpenFileSnapshot 単位で active/open を一括解決、entity ごとに再計算しない
2. **Defer active resolution** — KEEP-only / non-runtime entity は active UNKNOWN のまま safety eval（Action 契約で block）
3. **ACT readiness** — read-only preflight transaction design、executor なし
4. **まだ ACT に進まない**

---

## 15. tasks.md status

```text
P1.12 — Entity Safety Snapshot & Resolver Memoization: PARTIAL
  Architecture: DONE
  DerivedData alignment: DONE
  Performance stretch (<15s safety_eval): NOT MET
```

---

## 16. Reports

```text
reports/case001/safety_eval_runtime.json
reports/case001/resolver_runtime.json
reports/case001/entity_safety_snapshot_runtime.json
reports/case001/action_eval_runtime.json
reports/case001/predicate_cache_stats.json
reports/case001/safety_rule_index_stats.json
reports/case001/green_auditor_runtime.json
reports/case001/p1_12_runtime_comparison.json
reports/case001/action_recommendations.json
reports/case001/green_candidates_case001.json
```

---

## 17. 再現コマンド

```bash
cd ~/Workspace/10_進行中/ai-storage-manager
python3 tools/compile_knowledge_base.py
swift test                    # expect 218 tests, 0 failures
swift run storage-intel scan    # read-only, proof=derived-data
```

---

## 18. ChatGPT への依頼テンプレ

```text
上記 P1.12 handoff を読んだ上で:

1. EntitySafetySnapshot アーキテクチャが Safety 意味論を保っているか確認
2. active_state 11.3s を弱めずに削る P1.13 設計案
3. defer vs batch の trade-off（どの entity が active 解決必須か）
4. ACT readiness に進む条件（executor なし）

推測で GREEN を増やす提案は不要。
```

---

## 19. One-line status

**P1.12 PARTIAL:** Entity を一度理解して複数 Action に使い回す架构完成。DerivedData→MOVE_TO_TRASH 整合。total 87→82s。safety_eval 25.5→26.2s（active_state 11s が残ボトルネック）。218 tests / False GREEN=0。次は P1.13 active_state batch。
