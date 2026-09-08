# AI Storage Manager — P3.0.2 ハンドオフ
# Storage Change Intelligence

**日付:** 2026-09-03  
**Repo:** `~/Workspace/10_進行中/ai-storage-manager`  
**フェーズ:** P3.0.2 — Storage Change Intelligence  
**Git:** commit / push **なし**（`gitCommitCreated = false`）

---

## 一言で言うと

P3.0.1 が答えたのは **WHERE**。  
P3.0.2 が答えるのは **WHAT CHANGED / WHEN / HOW MUCH / WHAT WE STILL CANNOT EXPLAIN**。

増えただけでは「消していい」にならない。  
Safety / ActionDecision が唯一の行動根拠。

---

## 実装サマリ

### P3.0.1 residuals（先に閉じた）

1. **Deterministic deep timeout fixture**  
   `testDeterministicDeepTimeoutHierarchyNeverCollapsesToZero`  
   TIMEOUT + known children → lower bound / PARTIAL / center ≠ 0 GB / no diskUsed fallback

2. **Partial Map UI（静か）**  
   `coverage == PARTIAL` で center と story chip に `Partial map`  
   警報 UI ではない

### P3.0.2 core

```text
StorageExplorerSnapshot
  → StorageHistoryBuilder（IOなし）
  → StorageHistoryStore（Application Support）
  → StorageSnapshotDiffEngine（IOなし）
  → StorageChangeReport + Explanation
  → Overview compact panel + Change detail
```

- second crawler: **false**
- schemaVersion: **1**
- retention: soft window **30**（物理削除は mutation surface を汚さないため保留）
- privacy: identity / size / category / kind / timestamps のみ

---

## テスト

| 項目 | 値 |
|------|-----|
| before | 356 |
| after | **369 / 0 failures** |
| 追加 | P301 deep timeout +1、P302 suite 12 |

False GREEN = **0**  
duplicateEvaluations = **0**  
MOVE_TO_TRASH only = **維持**  
Safety production rules = **変更なし**  
New mutation APIs = **なし**

---

## Live 結果（2026-09-03）

```text
comparisonQuality = NO_COMPARISON_YET   ← 初回履歴として正しい
historySnapshotCount = 1
snapshotWriteSuccess = true
historyStoreLocationType = applicationSupport
secondCrawlerAdded = false
falseGREEN = 0
duplicateEvaluations = 0
mappedCurrent ≈ 191.6 GB（ROOT_MEASURED live explorer）
```

比較付き数値（fixture demo / スクショ）:

```text
diskUsedDelta = +18.4 GB
diskFreeDelta = -18.4 GB
topGrowing = Ollama Models +8.1 GB
topShrinking = DerivedData -3.4 GB
new = movie.mov
```

---

## レポート / スクショ

- `reports/case001/p3_0_2_storage_change.json`
- `reports/case001/p3_0_2_history_status.json`
- `reports/case001/screenshots/overview_p302_first_run.png`
- `reports/case001/screenshots/overview_p302_change_intelligence.png`
- `reports/case001/screenshots/change_detail_p302.png`

Production history:  
`~/Library/Application Support/AIStorageManager/History/`

---

## Known limitations

1. Soft retention（古い JSON を物理削除しない）— mutation surface ロック優先  
2. MOVE 推定は identity 証拠がある場合のみ（現状は保守的に NEW/REMOVED）  
3. Change lens overlay は未実装（detail + compact panel で充足）  
4. P3.0.3 Optimization Plan は未着手  

---

## Recommended next

**P3.0.3 — Optimization Plan**  
「20GB空けたい」→ 現在 verified な独立候補のみ。change history から actionable を推論しない。

---

## 意味の芯

```text
Do not lie about what is mapped.   (P3.0.1)
Do not lie about what changed.     (P3.0.2)

If free space fell 18 GB and we can explain 12 GB:
say we can explain 12 GB.
Do not invent the remaining 6 GB.

GROWING != SAFE TO CLEAN
```
