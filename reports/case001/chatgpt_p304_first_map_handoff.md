# AI Storage Manager — P3.0.4 ハンドオフ
# Time-to-First-Map & Progressive Scan Acceleration

**日付:** 2026-09-03  
**Repo:** `~/Workspace/10_進行中/ai-storage-manager`  
**フェーズ:** P3.0.4  
**Git:** commit / push **なし**

---

## 一言

地図を「全部測ってから」出していた。  
それが遅さの正体だった。

今は：

子を先に測る → 約 **1.0 秒** で使える Partial Map  
根の `du` は後ろで続く（約45秒、ブロックしない）  
Safety は従来どおり後から（約157秒）

真実は弱めていない。  
早く見せているだけ。

---

## 1. Root performance bottleneck

**`ROOT_DU_BLOCKING`**

## 2. Evidence

- baseline `timeToFirstHierarchyMs` ≈ 48,560（P3.0.1 report）
- live `root_measurement` span = **45,058 ms**
- live `child_measurement` = **1,019 ms**
- live `timeToFirstUsefulMapMs` = **1,021 ms**
- `rootTimedOut = true`（根の正確計測は後でも地図は出る）

根の `du` が終わるまで子列挙に進まない旧 walk が主因。

## 3. Architecture fix

1. 根の direct children を先に列挙・計測（bounded concurrency ≤ 4）
2. 根 `du` は非同期開始。first map をブロックしない
3. known-child lower bound で Partial Map を publish
4. 深い階層は後続
5. in-flight measurement coalesce + session cache
6. MapReadiness + progressive immutable snapshots
7. history duplicate identity は snapshot-local。跨スナップショットの偽マッチ禁止

## 4. Changed files

- `Sources/SafetyCore/Scanner/{PhysicalHierarchyBuilder,PhysicalStorageNode,ScanSessionContext,SizeMeasurement,ScanPerformanceTrace}.swift`
- `Sources/AppServices/StorageExperience/{StorageExplorerModels,StorageExplorerBuilder,P304ScanPerformance}.swift`
- `Sources/AppServices/LiveStorageActionCoordinator.swift`
- `Sources/AppServices/StorageChange/{StorageHistoryBuilder,StorageHistoryModels,StorageSnapshotDiffEngine}.swift`
- `Sources/StorageIntel/main.swift`
- `Sources/AIStorageManagerUI/{ProductCopy,StorageViewModel,Explorer/*,Change/*,OverviewScreenshotExport}.swift`
- `Tests/AppServicesTests/P304ProgressiveScanTests.swift`
- `tasks.md`
- `reports/case001/p3_0_4_*.json` + screenshots

## 5–9. Tests / Safety

- before: **389 / 0**
- after: **394 / 0**
- failures: **0**
- False GREEN: **0**
- duplicateEvaluations: **0**

## 10. MapReadiness

`NOT_READY` → `STRUCTURE_READY_PARTIAL` → `STRUCTURE_READY_MEASURED` → `SEMANTIC_ENRICHED` → `DECISION_ENRICHED` → `COMPLETE`

## 11. Progressive publication

`onPublication(.firstUsefulMap / .directChildrenMeasured / .complete)`  
UI は immutable `StorageExplorerSnapshot` のみ。

## 12–13.

- ScanSessionContext reuse: **yes**
- secondCrawlerAdded: **false**

## 14–20. Measurement (live run)

| metric | value |
|--------|-------|
| measurementRequests | 1331 |
| uniqueMeasurementKeys | 916 |
| cacheHits | 458 |
| cacheMisses | 1811 |
| coalescedRequests | 0（同パス同時要求は今回ほぼ無し） |
| maxMeasurementConcurrency | **4** |

## 21–24. Blocking?

- Root measurement blocks first map? **No（非同期）**
- Deep hierarchy blocks first map? **No**
- Semantic blocks first map? **No**
- Safety blocks first map? **No**

## 25–33. Timing (live)

| | before | after |
|--|--------|-------|
| First useful map | 48,560 ms | **1,021 ms** |
| Improvement | | **47,539 ms（約 97.9%）** |
| Full hierarchy | ~48.5s | 45,060 ms（根待ち込み） |
| Semantic/Safety | ~157s | 157,433 ms |
| Total scan | | 162,227 ms |

注: run は warm filesystem の可能性あり。構造改善は「根待ちを外した」こと。OS cache だけの加速とは区別する。

## 34–38. First map

- basis: **KNOWN_CHILDREN_LOWER_BOUND**
- coverage: **PARTIAL**
- mappedBytes: **22,285,245,936**（約 22.3 GB）
- nodeCount (final reported): 412
- Final node count: 412

## 39–43. UI

- Partial map UI: Partial chip + measuring… + stage banner
- UI usable before Safety: **Yes**（探索・Reveal・Quick Look）
- Mutation CTA: Safety 完了前は無効のまま
- Main-thread: hierarchy は background Task.detached
- Sunburst: 既存 aggregation（Other smaller items）再利用
- Visual aggregation: presentation only。Safety Entity ではない

## 44–48. Regressions

- Final-equivalence fixture test: **PASS**
- P3.0.1 accounting: preserved
- P3.0.2 history final-only write: preserved（progressive は persist しない）
- P3.0.3 plan waits for decision catalog / complete stage
- Duplicate identity: snapshot-local → UNKNOWN_MATCH。偽の grew なし

## 49–52.

- History writes during progressive? **No**（complete 後のみ）
- Plan before decisions? **No**（`Finish safety analysis first`）
- Executor scope: **MOVE_TO_TRASH only**
- New mutation APIs: **0**

## 53. Screenshots

- `reports/case001/screenshots/overview_p304_scanning.png`
- `overview_p304_partial_map.png`
- `overview_p304_semantic.png`
- `overview_p304_complete.png`

## 54. Reports

- `p3_0_4_scan_performance.json`
- `p3_0_4_scan_trace.json`
- `p3_0_4_before_after.json`
- `chatgpt_p304_first_map_handoff.md`

## 55. tasks.md

P3.0.4 DONE 追記済み。

## 56. Known limitations

- 完全 hierarchy 完了は根 `du` 待ちでまだ ~45s
- Safety/semantic は意図的に遅い（弱めない）
- live coalesce 件数は 0（同時同一パスが少なかった）
- Sunburst 幾何の深い最適化は PARTIAL
- 複数 cold/warm ベンチの厳密分離は未実施（今回 1 live run + fixture 証明）

## 57. git commit created?

**No**

## 58. Recommended next phase — 自動開始しない

実在庫（P3.0.3）は Ready Now = 0。  
速度は大幅改善したが、安全に消せるバイトはまだ少ない。

**推奨: P3.1 — Proof Coverage Expansion**  
（高価値 VERIFY_MORE：Ollama / HF 等）

iCloud / RemoveLocalDownload は、証明在庫が増えてから。  
速い地図の次は「触れる真実」を増やす番。
