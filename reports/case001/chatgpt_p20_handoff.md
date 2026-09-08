# ChatGPT Handoff — P2.0 Action Architecture（Recommendation + Preflight）
Date: 2026-08-29  
Audience: ChatGPT（ACT 設計継続・品質レビュー用）  
Repo: `~/Workspace/10_進行中/ai-storage-manager`  
Phase: **PROVE + P2.0/P2.1/P2.2 実装済み**（ACT Executor **NOT STARTED**）

---

## 0. 先に貼る指示

```text
あなたは AI Storage Manager の共同開発パートナーです。
Mac Cleaner ではなく Storage Decision Intelligence。

現在: PROVE フェーズ + P2.0 Action Layer（Recommendation / Preflight Preview のみ）
ACT 実行（Trash / iCloud move / eviction）は NOT STARTED

絶対ロック:
- preview.executable = false
- destructiveActionsExecuted = false
- False GREEN = 0（現状維持必須）
- Permanent Delete v0.1 禁止
- raw rm フォールバック禁止
- Recommendation が Safety を上書きしない
- LLM が SafetyClass / ActionDecision / VERIFIED を上書きしない

重要な設計修正（P2.0 で確定）:
MOVE_TO_ICLOUD は source_of_truth=FALSE を一般要件にしない。
ユーザー原本（Documents/動画/PDF）は SOT TRUE VERIFIED でも MOVE_TO_ICLOUD 候補になりうる。
MOVE_TO_TRASH と MOVE_TO_ICLOUD は Source-of-Truth 契約が完全に別。

やってほしいこと:
1. Case Study #001 の action recommendation 品質レビュー（下記 FACT を前提）
2. P2.3 以降（transaction models / first executor）の設計提案
3. 誤 recommendation の修正方針（git repo → MOVE_TO_ICLOUD 等）
4. GREEN entity と Action recommendation の乖離解消案
5. 推測で GREEN を増やす提案は不要
```

---

## 1. 今回完了したこと（FACT）

### P2.0 — Canonical Action Model
- `StorageAction`: keep / moveToTrash / moveToICloud / removeLocalDownload / vendorNativeCleanup
- `ActionDecision`: Entity × Action × State（action-specific safety）
- `ActionBlockReason`: 明示コード（VOICE_MEMO_NATIVE_SYNC_REQUIRED 等）
- `ActionMode` → `StorageAction` bridge（hardBlock / permanentDelete → nil、推測禁止）
- `ICloudTransactionPhase.localCopyVerified` 追加

### P2.1 — ActionRecommendationEngine
- Safety とは独立。Safety eligible を上書きしない
- `RecommendationDisposition`: actionable / keep / verifyMore
- ranking: preservation > deletion, verified > inferred, bytes alone 禁止

### P2.2 — ActionPreflightEngine（read-only）
- `wouldExecuteNow: false` 固定
- PROVE claims → preflight SATISFIED / MISSING / STALE

### Pipeline 接続 + Reports
```text
reports/case001/action_recommendations.json
reports/case001/action_preflight_preview.json
reports/case001/action_blocked_reasons.json
reports/case001/icloud_move_candidates.json
reports/case001/remove_local_download_candidates.json
```

### Tests
- **204 tests**, 0 failures
- `P20ActionArchitectureTests.swift` — SOT TRUE iCloud、Voice Memo block、DerivedData trash 等

---

## 2. Product flow（不変）

```text
SCAN → UNDERSTAND → VERIFY → PROVE
  → CHOOSE BEST ACTION          ← P2.1 ここまで実装
  → PREVIEW                     ← P2.2 read-only preview
  → USER APPROVAL
  → FRESH PREFLIGHT
  → SAFE ACTION                 ← NOT STARTED
  → POST-ACTION VERIFY
```

必須 invariant:

```text
ActionRecommendationEngine → 直接 execution 禁止
Recommendation → ActionDecision → Fresh Preflight → User Approval → Transaction → Post Verify
```

---

## 3. Action 契約サマリ

| Action | 意味 | SOT 契約 |
|--------|------|----------|
| KEEP | 安全側デフォルト | — |
| MOVE_TO_TRASH | 生成物/disposable | **SOT FALSE VERIFIED** + regen 等 |
| MOVE_TO_ICLOUD | preservation（原本保護） | **SOT TRUE 可** + preservation contract |
| REMOVE_LOCAL_DOWNLOAD | ローカル実体のみ解放 | remote/cloud VERIFIED 必須 |
| VENDOR_NATIVE_CLEANUP | 明示 vendor 契約のみ | contract 依存 |

Permanent Delete: v0.1 除外。

---

## 4. Case Study #001 — Action Scan 結果（FACT, 2026-08-29）

| Metric | Value |
|--------|-------|
| Runtime | **122.5 sec**（P1.10: 89s → action eval 分 +22 entity） |
| Entities | **506** |
| Unique bytes | **~64.3 GiB**（69049700352） |
| False GREEN | **0** |
| GREEN after audit | **1**（DerivedData Runner-ckovnoskqurramhgydmrtirfscgd） |
| preview.executable | **false** |
| destructiveActionsExecuted | **false** |
| Tests | **204** |

### Recommendation 分布

| recommendedAction | count |
|-------------------|------:|
| KEEP | 501 |
| MOVE_TO_ICLOUD | 5 |
| MOVE_TO_TRASH | 0 |
| REMOVE_LOCAL_DOWNLOAD | 0 |

| disposition | count |
|-------------|------:|
| keep | 491 |
| verifyMore | 10 |
| actionable (MOVE_TO_ICLOUD) | 5 |

### Preflight preview（read-only）

| Action | allowed=true rows |
|--------|------------------:|
| MOVE_TO_ICLOUD | 24 |
| MOVE_TO_TRASH | **0** |
| Total preflight rows | 2010 |

### Block reason TOP（entity×action 集計）

| Reason | count |
|--------|------:|
| SAFETY_CLASS_RED | 1337 |
| RELOCATION_CONTRACT_MISSING | 913 |
| VERIFICATION_INCOMPLETE | 506 |
| SYNC_STATE_UNKNOWN | 506 |
| FILE_PROVIDER_REQUIRED | 504 |
| REMOTE_COPY_UNKNOWN | 486 |
| APPLICATION_MANAGED_DATA | 481 |
| SOURCE_ACTIVE | 206 |

---

## 5. 代表 Entity の recommendation（FACT）

| Entity | recommended | 期待 | 結果 |
|--------|-------------|------|------|
| Voice Memo (4 entities) | KEEP | KEEP | ✅ |
| iOS Backup (2) | KEEP | KEEP | ✅ |
| Claude VM (7) | KEEP / verifyMore | KEEP / verifyMore | ✅ |
| Cursor snapshots | KEEP | KEEP | ✅ |
| DerivedData (5) | KEEP / verifyMore | MOVE_TO_TRASH（1 GREEN あり） | ⚠️ 乖離 |
| REMOVE_LOCAL_DOWNLOAD candidates | 0 | synced cloud があれば候補 | ⚠️ File Provider 未証明 |
| Git repos under Documents | MOVE_TO_ICLOUD (5) | KEEP or block | ❌ 誤候補 |

### MOVE_TO_ICLOUD actionable 5件（要レビュー）

すべて **git 関連**（`.git` / working tree / objects）:

```text
git.dot_git      → .../ファイル整理/.git
git.working_tree → .../ファイル整理
git.objects      → .../.git/objects
git.packfiles    → .../.git/objects/pack
user.downloads   → ~/Downloads（root 単位）
```

**問題:** git repository / VCS metadata は preservation relocation の対象外であるべき。  
user-owned root だけでは MOVE_TO_ICLOUD を auto-offer してはいけない。

### GREEN vs Action recommendation 乖離（重要）

唯一の GREEN entity:

```text
xcode.deriveddata.Runner-ckovnoskqurramhgydmrtirfscgd
  green_audit.recommendedAction = MOVE_TO_TRASH  ✅
  action_recommendations.recommendedAction = KEEP (verifyMore)  ❌
  blocked MOVE_TO_TRASH: SAFETY_CLASS_RED×2, SOURCE_ACTIVE, VERIFICATION_INCOMPLETE
```

**原因候補（FACT ベース）:**
- `openFileHandle == unknown` → VERIFICATION_INCOMPLETE で trash block
- `SOURCE_ACTIVE`（Xcode / build process 推定）
- ActionSafetyEvaluator が KB engine の RED/UNKNOWN と action proof を未統合
- GREEN audit と Action layer の claim 入力が一致していない

---

## 6. うまくいっている Safety block（FACT）

```text
Voice Memo     → MOVE_TO_ICLOUD blocked (VOICE_MEMO_NATIVE_SYNC_REQUIRED)
iOS Backup     → MOVE_TO_ICLOUD blocked (IOS_BACKUP_REQUIRES_DEVICE_AWARE_MIGRATION)
Library paths  → MOVE_TO_ICLOUD blocked (RELOCATION_CONTRACT_MISSING)
Claude runtime → MOVE_TO_ICLOUD + MOVE_TO_TRASH blocked (APPLICATION_MANAGED_DATA)
REMOVE_LOCAL_DOWNLOAD → FILE_PROVIDER_REQUIRED（cloud path alone 不十分）
Permanent Delete → StorageAction に存在しない / ActionMode → nil
```

---

## 7. 既知の品質課題（P2.1 レビュー待ち）

### P2.1-A: Git / VCS を MOVE_TO_ICLOUD から除外
- `userOwnedRoot` だけでは不十分
- semanticType / lifecycle / `.git` path / git detector 連携が必要
- 推奨: `RELOCATION_CONTRACT_MISSING` or 専用 block `VCS_REPOSITORY_REQUIRES_NATIVE_WORKFLOW`

### P2.1-B: GREEN entity → MOVE_TO_TRASH recommendation 乖離
- PROVE GREEN と Action recommendation の claim ソース統一
- open file state: PROVE で verified なら Action でも再利用
- DerivedData proven trash path: action-specific proof override の適用条件見直し

### P2.1-C: duplicate block reasons
- 例: `SAFETY_CLASS_RED` が同一 action に2回出る
- blockedReasons は Set 化 or dedupe

### P2.1-D: iCloudEnabled nil → 過剰な MOVE_TO_ICLOUD preflight allowed
- `iCloudEnabled: nil` 時は recommendation を conservative に（KEEP / verifyMore）
- preflight allowed=24 vs actionable=5 のギャップ整理

### P2.1-E: Downloads root recommendation
- `~/Downloads` ディレクトリ全体を MOVE_TO_ICLOUD は product 的に危険
- entity 単位（ファイル）のみ offer すべき

### P2.1-F: Runtime regression
- P1.10: 89s → P2.0 scan: 122s（506 entities × 5 actions eval）
- 次: action eval の batch / cache（safety_eval 26s と同様）

---

## 8. コードマップ（FACT）

| ファイル | 役割 |
|----------|------|
| `Sources/SafetyCore/Action/ActionArchitecture.swift` | StorageAction, ICloudTransactionPhase, ActionMode bridge |
| `Sources/SafetyCore/Action/ActionModels.swift` | ActionDecision, ActionBlockReason, ActionPreflightResult |
| `Sources/SafetyCore/Action/ActionSafetyEvaluator.swift` | Entity × Action × State gates |
| `Sources/SafetyCore/Action/ActionRecommendationEngine.swift` | Recommendation（Safety 非上書き） |
| `Sources/SafetyCore/Action/ActionPreflightEngine.swift` | Read-only preflight |
| `Sources/SafetyCore/Action/ActionPolicy.swift` | Voice Memo / iOS Backup / Library / user-owned roots |
| `Sources/SafetyCore/Intelligence/ReadOnlyAnalysisPipeline.swift` | actionArchitecture report 生成 |
| `Tests/SafetyCoreTests/P20ActionArchitectureTests.swift` | 契約テスト |
| `docs/ACTION_ARCHITECTURE_v0.1.md` | 設計正本 |

---

## 9. v0.1 実装順序（残タスク）

| Phase | 内容 | Status |
|-------|------|--------|
| P2.0 | Canonical Action Model | **PARTIAL/DONE** |
| P2.1 | Recommendation Engine | **PARTIAL**（品質レビュー待ち） |
| P2.2 | Preflight Preview | **PARTIAL/DONE** |
| P2.3 | Transaction models only | NOT STARTED |
| P2.4 | First executor: Move To Trash（DerivedData allowlist） | NOT STARTED |
| P2.5 | Post-action verify（Trash） | NOT STARTED |
| P2.6 | MOVE_TO_ICLOUD executor | NOT STARTED |
| P2.7 | REMOVE_LOCAL_DOWNLOAD | NOT STARTED |
| P2.8 | SwiftUI | NOT STARTED |

**P2.4 に進む前に:** Case Study recommendation 品質を GREEN entity で一致させること。

---

## 10. ChatGPT への依頼（コピペ用）

```text
chatgpt_p20_handoff.md + docs/ACTION_ARCHITECTURE_v0.1.md を読んだ上で:

1. Case Study #001 の action recommendation 品質問題（git→iCloud, GREEN DerivedData 乖離）の修正設計
   - 新 block reason / RelocationContract / semantic guard のどれが最適か
   - PROVE GREEN claims を Action layer がどう再利用すべきか

2. P2.1 品質修正の最小 diff 方針（executor なし、tests 追加込み）

3. P2.3 ICloudTransactionPhase 各段階の preflight predicate 一覧（設計レビュー）

4. P2.4 Move To Trash executor の allowlist 設計（DerivedData 1 entity から）

5. REMOVE_LOCAL_DOWNLOAD が 0 件なのは正しいか（File Provider proof 不足 vs detector gap）

推測で GREEN を増やす提案は不要。
UNKNOWN + exact reason を維持。
```

---

## 11. 再現コマンド

```bash
cd ~/Workspace/10_進行中/ai-storage-manager
python3 tools/compile_knowledge_base.py
swift test                    # expect 204 tests, 0 failures
swift run storage-intel scan    # read-only, generates action_*.json
```

---

## 12. 関連 handoff

| ファイル | 用途 |
|----------|------|
| **本ファイル** | **P2.0 Action Layer + Case Study 品質レビュー（ChatGPT 主正本）** |
| `chatgpt_dev_status_handoff.md` | PROVE P1.6→P1.10 開発状況 |
| `chatgpt_action_architecture_handoff.md` | ACT / iCloud 設計概要 |
| `chatgpt_disk_pressure_handoff.md` | 容量判断（別物） |
| `tasks.md` | タスクステータス |

---

## 13. One-line status

**P2.0/P2.1/P2.2 PARTIAL:** Action recommendation + preflight preview 実装。Executor なし。Voice Memo/iOS Backup block は正しい。git→iCloud 誤候補と GREEN DerivedData 乖離が P2.1 品質課題。204 tests / False GREEN=0 維持。
