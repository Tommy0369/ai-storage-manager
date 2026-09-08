# AI Storage Manager — P3.0.1 Fix ハンドオフ
# Physical Map Accounting Recovery on Root Measurement Timeout

**日付:** 2026-09-03  
**Repo:** `~/Workspace/10_進行中/ai-storage-manager`  
**種別:** 新フェーズではない。P3.0.1 の **corrective pass**  
**Git:** commit / push **なし**（`gitCommitCreated = false`）

---

## 一言で言うと

バグは「円が 0 と出る」ではない。

**測定 UNKNOWN / TIMEOUT を numeric 0 に潰し、既に測れている子の真実を捨てていた。**

UNKNOWN は UNKNOWN のまま。  
既知の子があるなら、正直な **mapped lower bound** を出す。  
disk used で埋めるのは禁止。

---

## 製品ロック（維持）

```text
MOVE_TO_TRASH only
False GREEN = 0
duplicateEvaluations = 0
UNKNOWN NEVER AUTO-PROMOTES TO GREEN
PATH ALONE IS NOT SAFETY
No Safety rule modification
No MutationGate modification
No new Executor
No Permanent Delete / Empty Trash / MOVE_TO_ICLOUD / REMOVE_LOCAL_DOWNLOAD
No second filesystem crawler
```

---

## Before / After（事実）

### BEFORE（修正前 live report）

| 項目 | 値 |
|------|-----|
| root measurement | TIMEOUT / UNKNOWN（子は正の値あり） |
| physicalMapBytes | **0** |
| accountingValid | **false** |
| center | **0 GB** |
| 意味 | UNKNOWN を「マップ済みゼロ」に誤変換 |

出典: 旧 `reports/case001/p3_0_1_storage_explorer.json`  
（`physicalMapBytes: 0`, `accountingValid: false`, `physicalNodeCount: 411`）

### AFTER — 回帰テスト（timeout 経路の証明）

| 項目 | 値 |
|------|-----|
| root | UNKNOWN / TIMEOUT |
| children | 既知の正のバイト |
| physicalMapBytes | 既知子の合算（lower bound） |
| basis | `KNOWN_CHILDREN_LOWER_BOUND` |
| coverage | `PARTIAL` |
| accountingValid | `true`（内部整合） |
| center | 正の mapped / または「— Mapping unavailable」 |
| disk used fallback | **なし** |

### AFTER — live scan（2026-09-03 この回）

**この回は root `du` が成功した。fallback は live 未行使。**

| 項目 | 値 |
|------|-----|
| generatedAt | `2026-09-03T04:49:52Z` |
| rootMeasurementStatus | `EXACT` |
| rootMeasuredBytes | `191580434432`（≈191.58 GB） |
| knownChildMappedBytes | `191580400379` |
| physicalMapBytes | `191580434432` |
| physicalMapAccountingBasis | `ROOT_MEASURED` |
| physicalMapCoverage | `COMPLETE` |
| fallbackUsed | `false` |
| accountingValid | `true` |
| rootTotalKnown | `true` |
| unknownRemainderKnown | `true` |
| diskUsedBytes | `347901644612`（≠ map。混同禁止） |
| falseGREEN | `0` |
| duplicateEvaluations | `0` |
| physicalNodeCount | `411` |
| timeToFirstHierarchyMs | `48560` |
| timeToSafetyEnrichmentMs | `157000` |

出典:

- `reports/case001/p3_0_1_storage_explorer.json`
- `reports/case001/p3_0_1_explorer_performance.json`

---

## Root cause（証明済み）

```text
ScanSessionContext / measurement
  → PhysicalHierarchyBuilder（UNKNOWN → bytes=0, bytesKnown=false）
  → makeStats.representedBytes = root.bytesKnown ? root.bytes : 0
  → StorageExplorerSnapshot.physicalMapBytes
  → accountingValid=false
  → Sunburst center = focus.bytes（0）
```

壊れていた意味:

- A. 「root 全体サイズは不明」  
- B. 「マップした量がゼロ」  

A は B を含意しない。旧実装が A→B に潰していた。

---

## Fix strategy

1. `PhysicalMapAccounting` を導入  
   - basis: `ROOT_MEASURED` / `KNOWN_CHILDREN_LOWER_BOUND` / `NO_MEASUREMENT`  
   - coverage: `COMPLETE` / `PARTIAL` / `UNKNOWN`  
   - `accountingValid` = **選択した basis との内部整合**（完全スキャン完了フラグではない）

2. root 測定不可時  
   - 直接の既知子のみ合算（親子 inclusive の二重計上禁止）  
   - `mappedBytes` = lower bound  
   - `unknownRemainderKnown = false`（diskUsed − childSum の捏造禁止）

3. center label（`MapCenterLabel`）  
   - measured → 数値 + scope  
   - fallback → 正の mapped + `"mapped"`  
   - 測定なし → `"—"` / `"Mapping unavailable"`（偽の 0 GB 禁止）  
   - diskUsed への fallback 禁止

4. geometry / arcs の分母 = `accounting.mappedBytes`  
   - fallback 時は「既知マップの 360°」であり、未測定 remainder の主張ではない

5. CLI `storage-intel scan`  
   - 同一 `ScanSessionContext` で hierarchy → pipeline（`reuseExistingSession: true`）  
   - live explorer JSON を **常時上書き**（旧: 既存ファイルがあると demo でスキップ）

6. `overview-screenshot`  
   - live `p3_0_1_*.json` を demo で上書きしないよう修正

---

## ScanSessionContext 再利用（second crawler = false）

再利用するもの:

- 既存 session の `measure` / `SizeMeasurement`（quality / known）
- hierarchy walk が既に書いた child `bytesKnown` / `bytes`
- resolver は **木の上の算術のみ**（追加 `du` / FileManager recursive enumerator なし）

検証:

```text
secondCrawlerAdded = false
ScanSessionContextReused = true
```

---

## テスト

| 項目 | 値 |
|------|-----|
| before | 346 |
| after | **356 / 0 failures** |
| 新規 | `P301PhysicalMapAccountingTests` 10本 |

カバー:

1. ROOT_MEASURED 整合  
2. TIMEOUT → known-children lower bound  
3. center が 0 GB にならない  
4. 既知子なし → 非数値  
5. unknown child 除外  
6. 親子二重計上禁止  
7. measured が fallback に勝つ  
8. accountingValid ≠ coverage complete  
9. report JSON 意味の無矛盾  
10. diskUsed fallback 禁止  

Safety 回帰（Voice Memo / iOS Backup / Git / Claude / Cursor / Downloads / MOVE_TO_TRASH 等）: 通過。  
Safety 本番ルール変更: **なし**。

---

## スクショ

パス: `reports/case001/screenshots/overview_p30_quality_check.png`

視覚結果:

- 中心 **121.1 GB / mapped**（demo fixture。0 GB ではない）
- disk used（≈347 GB）を map 総量として出していない
- 円がメインの Overview 構成は維持（リデザインなし）

※ スクショは fixture demo。live 数値は上記 JSON を正とする。

---

## 変更ファイル（主なもの）

```text
Sources/SafetyCore/Scanner/PhysicalMapAccounting.swift          (new)
Sources/SafetyCore/Scanner/PhysicalHierarchyBuilder.swift
Sources/AppServices/StorageExperience/MapCenterLabel.swift      (new)
Sources/AppServices/StorageExperience/StorageExplorerBuilder.swift
Sources/AppServices/StorageExperience/StorageExplorerModels.swift
Sources/AppServices/StorageExperience/PreviewSnapshotFactory.swift
Sources/AIStorageManagerUI/StorageMap/MultiRingSunburstView.swift
Sources/AIStorageManagerUI/ProductCopy.swift
Sources/StorageIntel/main.swift
Sources/OverviewScreenshot/main.swift
Tests/AppServicesTests/P301PhysicalMapAccountingTests.swift    (new)
```

---

## 再現コマンド

```bash
cd ~/Workspace/10_進行中/ai-storage-manager

swift test --filter P301PhysicalMapAccounting
swift test --filter P301
swift test

swift run storage-intel scan
# → reports/case001/p3_0_1_storage_explorer.json
# → reports/case001/p3_0_1_explorer_performance.json

swift run overview-screenshot
# → reports/case001/screenshots/overview_p30_quality_check.png
# （live JSON は上書きしない）
```

---

## DONE 条件チェック

| 条件 | 結果 |
|------|------|
| root cause 特定 | ✅ |
| 失敗回帰テスト先行 | ✅ |
| UNKNOWN vs 0 区別 | ✅ |
| known-child fallback | ✅（テスト証明） |
| no second crawler | ✅ |
| ScanSessionContext reuse | ✅ |
| physicalMapBytes 正直 | ✅ |
| accountingValid = 内部整合 | ✅ |
| coverage 分離 | ✅ |
| center が 0 GB 嘘をつかない | ✅ |
| diskUsed 偽 total 禁止 | ✅ |
| full tests pass | ✅ 356/0 |
| False GREEN = 0 | ✅ |
| duplicateEvaluations = 0 | ✅ |
| MOVE_TO_TRASH-only | ✅ |
| live reports 再生成 | ✅ |
| screenshot after tests | ✅ |
| no git commit | ✅ |

---

## Known limitations

1. **この live 回は root EXACT。** timeout fallback の live 行使はしていない。  
   契約の正しさは `P301PhysicalMapAccountingTests` が担う。
2. `reportMappedBytes` は NO_MEASUREMENT 時のみ 0。UI center は非数値。
3. hierarchy 初回が ~48s。会計 fallback 自体は O(子) で軽い。
4. git 未 commit。作業ツリーは dirty / 未追跡のまま。

---

## Recommended next step

1. timeout 固定の深い fixture を CI で常時回し、live 依存を減らす  
2. fallback 時 UI の `Partial map` を静かに明示（警報 UI にしない）  
3. 必要ならこの corrective pass を commit（ユーザー指示があるまでしない）

---

## 意味の芯（引き継ぎ用）

```text
DO NOT invent a total when root is unknown.
DO NOT throw away already-known children.
DO NOT substitute diskUsedBytes.
DO NOT collapse UNKNOWN into 0.

KNOWN CHILDREN
  → HONEST MAPPED LOWER BOUND
  → PARTIAL COVERAGE
  → INTERNALLY VALID MAP

UNKNOWN stays UNKNOWN.
ZERO means zero only when zero was observed.
```
