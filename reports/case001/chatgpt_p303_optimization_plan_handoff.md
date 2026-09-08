# AI Storage Manager — P3.0.3 ハンドオフ
# Goal-Based Optimization Plan

**日付:** 2026-09-03  
**Repo:** `~/Workspace/10_進行中/ai-storage-manager`  
**フェーズ:** P3.0.3 — Goal-Based Optimization Plan  
**Git:** commit / push **なし**（`gitCommitCreated = false`）

---

## 一言で言うと

P3.0.1 は **WHERE**。  
P3.0.2 は **WHAT CHANGED**。  
P3.0.3 は **WHAT CAN BE ACHIEVED — HONESTLY**。

20 GB 欲しくても、証明済みが 0 なら 0 と答える。  
UNKNOWN で不足分を埋めない。

---

## 1. Implemented

- `OptimizationGoal`（`FREE_LOCAL_SPACE`、GB入力、ゼロ/負/過大を拒否）
- `OptimizationCandidate`（Entity × StorageAction のみ）
- `ActionExecutionCapabilityRegistry`（enum存在 ≠ 実装）
- Eligibility tiers / conflict·overlap / constrained selection
- Recovery semantics（Trash は potential ≠ immediate）
- Plan UI（Overview 入口 + Storage Goal 画面）
- Per-item Review / Check Safety（既存 preflight。一括実行なし）
- Live reports: `p3_0_3_optimization_plan.json` + `p3_0_3_candidate_funnel.json`
- Fixture screenshots（live JSON は上書きしない）

## 2. Changed files

- `Sources/AppServices/Optimization/*`（新規）
- `Sources/AIStorageManagerUI/Optimization/OptimizationPlanView.swift`（新規）
- `Sources/AIStorageManagerUI/{ProductCopy,AppShellView,StorageExplorerView,StorageViewModel,OverviewScreenshotExport}.swift`
- `Sources/AppServices/{LiveStorageActionCoordinator,FakeStorageActionCoordinator}.swift`
- `Sources/AppServices/StorageChange/{StorageHistoryBuilder,StorageSnapshotDiffEngine}.swift`（重複 identity で crash しない）
- `Sources/StorageIntel/main.swift`
- `Tests/AppServicesTests/P303OptimizationPlanTests.swift`（新規）
- `Tests/AppServicesTests/P302StorageChangeIntelligenceTests.swift`
- `tasks.md`
- `reports/case001/p3_0_3_*.json`
- `reports/case001/screenshots/overview_p303_goal_entry.png`
- `reports/case001/screenshots/optimization_plan_p303_{partial,achievable,no_safe_options}.png`
- `reports/case001/chatgpt_p303_optimization_plan_handoff.md`

## 3–5. Tests

- **before:** 369 / 0 failures
- **after:** 389 / 0 failures
- **failures:** 0

## 6–7. Safety counters

- **False GREEN:** 0
- **duplicateEvaluations:** 0

## 8. OptimizationGoal

`FREE_LOCAL_SPACE(bytes)`。初期 UI は GB 入力（10 / 20 / Custom）。  
将来用: `excludeEntities` / `excludeCategories` / `allowedActions` / `maxActionCount` / `preferReversible`。

## 9. Candidate source

既存 `UICandidateItem` + canonical `ActionDecision`（`OptimizationActionFact`）。  
size / age / growth / path / filename / category / LLM からは作らない。

## 10. Eligibility tiers

1. `EXECUTABLE_NOW` / `APPROVAL_REQUIRED` → Ready now  
2. `VERIFIED_BUT_EXECUTOR_UNAVAILABLE` → Future verified  
3. `PREFLIGHT_REQUIRED` → 保証しない  
4. `VERIFY_MORE`  
5. `BLOCKED` / `PROTECTED`

## 11. Execution capability registry

- `MOVE_TO_TRASH` → IMPLEMENTED  
- `MOVE_TO_ICLOUD` / `REMOVE_LOCAL_DOWNLOAD` / `VENDOR_NATIVE_CLEANUP` / `KEEP` → NOT_IMPLEMENTED

## 12–16. Live Mac inventory（goal 20 GB）

実スキャン結果（捏造なし）:

| 層 | count | bytes |
|----|-------|-------|
| Ready now | **0** | **0** |
| Verified future | 1 | 107,298,816（約 107 MB） |
| Preflight | 0 | 0 |
| Blocked | 599 | — |
| Protected | 1332 | — |

## 17–22. Goal math（live）

- Goal: 20,000,000,000  
- Available now potential: **0**  
- Verified future potential: **107,298,816**  
- Preflight possible: **0**  
- Shortfall: **20,000,000,000**  
- Goal status: **`NEEDS_MORE_VERIFICATION`**  
- Selected plan entries: **なし**

## 23–26. Conflicts / overlap

- Conflict count: 0（Ready now が空のため選択衝突なし）  
- Parent/child: パス overlap は同一プランに入れない  
- overlapBytesPrevented: 0（今回の Ready 集合が空）

## 27. Planning algorithm

1. Eligibility class でフィルタ（CLASS > SCORE）  
2. 同一 entity / 親子パスを排除  
3. blast radius → reversibility/complexity → 必要バイト  
4. 同 tier なら過大単独より小さい組合せを優先  
UNKNOWN/RED は到達のため昇格しない。

## 28. Blast-radius ordering

`low < medium < high < unknown`。数値最適化より先。

## 29–31. Recovery

- `logicalBytes` / `potentialRecoveryBytes` / `immediateExpectedRecoveryBytes` / `verifiedRecoveredBytes`  
- **MOVE_TO_TRASH immediate recovery claim: しない（常に 0）**  
- 実行後も PostVerify なしでは verified recovery を増やさない  
- UI 文言: 「can be moved to Trash」。freed とは言わない。Empty Trash は出さない。

## 32. Plan staleness

`planningSnapshotID` が現世代と違う → `STALE`。  
行動前は候補ごとに Fresh Preflight。

## 33–36. Planning の副作用

- Approval created? **No**  
- ExecutionPermit created? **No**  
- Executor called? **No**  
- Bulk action added? **No**（Run All / Clean All なし）

## 37–38. P3.0.2

Growth は explanation/context のみ。  
Safety 資格は作らない。  
「Ollama が増えた」≠ プラン候補。

## 39. Exclusion explanations

実Mac上位:

- Voice Memos 14.0 GB — protected  
- Cursor global storage 13.7 GB — protected  
- Claude VM bundle 10.7 GB — protected  
- Chrome App Support 10.5 GB — protected  
- HuggingFace hub 3.1 GB — needs verification  
- Ollama blobs 2.5 GB — needs verification  

巨大フォルダを選ばない理由を隠さない。

## 40–42. UI

- Overview: Need more space? / Free 10 GB / Free 20 GB / Custom（Sunburst は残す）  
- Sidebar: Storage Goal  
- Plan screen: Ready / Verified opportunities / Needs verification / Why not chosen / shortfall  
- Review → 既存 per-item フロー。プラン横断の許可は無い。

## 43. Plan performance（live、FS IO なし）

- candidateBuildMs: 35  
- conflictResolutionMs: 0  
- planSelectionMs: 0  
- planTotalMs: 47

## 44–47.

- **secondCrawlerAdded:** false  
- **New mutation APIs?** なし  
- **Existing executor scope:** MOVE_TO_TRASH only  
- **Safety production behavior changed?** 変更していない（Plan は既存決定を読むだけ）

履歴 identity 重複で Diff が fatal していたので、identity uniquify のみ防御。Safety Class は触っていない。

## 48. Regression suite

389 tests / 0 failures。False GREEN=0。duplicateEvaluations=0。

## 49. Screenshot paths（fixture のみ）

- `reports/case001/screenshots/overview_p303_goal_entry.png`  
- `reports/case001/screenshots/optimization_plan_p303_partial.png`  
- `reports/case001/screenshots/optimization_plan_p303_achievable.png`  
- `reports/case001/screenshots/optimization_plan_p303_no_safe_options.png`

## 50. Report paths

- `reports/case001/p3_0_3_optimization_plan.json`  
- `reports/case001/p3_0_3_candidate_funnel.json`  
- `reports/case001/chatgpt_p303_optimization_plan_handoff.md`

## 51. tasks.md

`P3.0.3 — Goal-Based Optimization Plan` を DONE で追加。

## 52. Real-Mac plan result

**20 GB 目標。Ready Now = 0。不足 20 GB。**  
安全に今すぐ実行できるプランは存在しない。  
これは失敗ではなく、正しい答え。

## 53. Known limitations

- プランはセッション中心（大規模永続化なし）  
- 自然言語パーサ / チャット UI なし  
- 制約 UI（除外カテゴリ等）はモデルのみ  
- extraFacts は in-process decision catalog 依存  
- 実Macの GREEN MOVE_TO_TRASH 在庫が空

## 54. git commit created?

**No.**

## 55. Recommended next phase — 自動開始しない

実在庫:

- 実行可能バイト: 0  
- 検証済みだが Executor 未実装: **約 107 MB**  
- 大きいものは Protected / Verify More

**推奨: C. P3.0.4 — Scan Speed / Time-to-First-Map**

理由（事実）: A/B の新 Executor を足しても、今の証明済み在庫は 107 MB。20 GB には届かない。  
iCloud が強く聞こえるから選ぶのは、今回の原則（嘘をつかない）に反する。

VERIFY_MORE（Ollama / HF）を GREEN にするのは Safety/Proof 仕事。P3.1 の前に在庫を見ろ、が今回の結論。
