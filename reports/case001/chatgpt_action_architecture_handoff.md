# ChatGPT Handoff — Action Architecture & iCloud Storage Offload
Date: 2026-08-29  
Audience: ChatGPT（ACT フェーズ設計用）  
Repo: `~/Workspace/10_進行中/ai-storage-manager`  
Phase: **PROVE 中**（ACT 実行は **NOT STARTED**）

---

## 0. 先に貼る指示

```text
P2.0 実装済み（Recommendation + Preflight Preview のみ。Executor なし）

重要な設計修正:
MOVE_TO_ICLOUD は source_of_truth=FALSE を一般要件にしない。
ユーザー原本（Documents/動画/PDF）は SOT TRUE VERIFIED でも MOVE_TO_ICLOUD 候補になりうる（preservation action）。

MOVE_TO_TRASH と MOVE_TO_ICLOUD は Source-of-Truth 契約が完全に別。
```

---

## 1. 核心メッセージ

**Storage Decision Intelligence の ACT は「消す」ではない。**

```text
KEEP
MOVE_TO_TRASH
MOVE_TO_ICLOUD          ← ユーザー所有ファイル向け
REMOVE_LOCAL_DOWNLOAD   ← クラウドは残す（File Provider eviction）
VENDOR_NATIVE_CLEANUP
```

Permanent Delete: v0.1 対象外。

---

## 2. MOVE_TO_ICLOUD

### UI 文言 vs 内部契約

UI: 「iCloudへ移動」  
内部: **COPY → VERIFY → RELEASE ORIGINAL**（破壊的 move 禁止）

### 自動提供 OK

Documents, Desktop, Downloads のユーザー作成物、動画、PDF、アーカイブ

### 自動提供 NG

Application Support, Containers, Group Containers, Cursor storage, Claude VM, DerivedData, Caches, node_modules, runtime DB 等

→ relocation contract が entity 単位で VERIFIED された場合のみ例外

### Preflight（UNKNOWN なら実行しない）

- user-owned VERIFIED
- canonical path VERIFIED
- source exists / readable / not modifying
- iCloud available, destination known
- quota / conflict / size
- SOT 意味理解
- provider state 観測可能

### Post-copy verify

destination / identity / size / upload / remote-backed state

失敗 → local 原本維持、`TRANSFER_PENDING` or `VERIFICATION_UNKNOWN`

---

## 3. REMOVE_LOCAL_DOWNLOAD

**DELETE ではない。** クラウドコピーは残す。

- File Provider backed 必須
- `NSFileProviderManager` 等ネイティブ eviction
- remote backing VERIFIED（可能な範囲）
- unsynced changes なし
- fresh preflight + user approval

失敗 → rm フォールバック禁止

### DELETE との分離例

iCloud 上のユーザードキュメント:

| Action | 意味 | Safety |
|--------|------|--------|
| DELETE | クラウド含む破壊的 | RED / 明示的 destructive |
| REMOVE_LOCAL_DOWNLOAD | ローカル実体のみ解放 | verified なら GREEN 候補 |

---

## 4. iCloud Transaction State Machine

```text
NOT_STARTED → PREFLIGHT → COPYING → LOCAL_COPY_VERIFIED → UPLOAD_PENDING
  → VERIFYING_REMOTE → REMOTE_VERIFIED → LOCAL_RELEASE_ELIGIBLE
  → RELEASING_LOCAL_COPY → COMPLETED
失敗: FAILED / UNKNOWN / CANCELLED（source 維持）
```

---

## 5. Case Study #001 実測（2026-08-29 scan）

| Metric | Value |
|--------|-------|
| Entities | 506 |
| recommended KEEP | 501 |
| recommended MOVE_TO_ICLOUD | 5（git 関連 — **品質課題**） |
| preflight MOVE_TO_ICLOUD allowed | 24 |
| preflight MOVE_TO_TRASH allowed | 0 |
| REMOVE_LOCAL_DOWNLOAD candidates | 0 |

詳細: **`chatgpt_p20_handoff.md` §4–§7**

---

## 5b. Action Recommendation Engine（設計例）

出力イメージ:

```json
{
  "entityID": "user.video.large",
  "recommended": "MOVE_TO_ICLOUD",
  "alternatives": ["MOVE_TO_TRASH", "KEEP"],
  "why": ["USER_OWNED", "ICLOUD_AVAILABLE", "RECOVERY_8.4GB"],
  "blockedReasons": []
}
```

| Entity | recommended | alternatives |
|--------|-------------|--------------|
| 8GB 動画 | MOVE_TO_ICLOUD | MOVE_TO_TRASH |
| DerivedData | MOVE_TO_TRASH | KEEP |
| synced iCloud doc | REMOVE_LOCAL_DOWNLOAD | KEEP |
| Voice Memo 13GB | KEEP | （将来 SYNC_TO_ICLOUD_NATIVE） |
| iOS Backup 24GB | KEEP / REVIEW | （将来 MIGRATE_TO_ICLOUD_BACKUP・別契約） |
| Claude VM unknown | KEEP / VERIFY_MORE | — |

recoverable bytes だけで recommended を決めない（PROVE と同じ哲学）。

---

## 6. 既存コード現状（FACT）

| 項目 | 状態 |
|------|------|
| `StorageAction` | **P2.0 実装済み**（keep / moveToTrash / moveToICloud / removeLocalDownload / vendorNativeCleanup） |
| `ActionDecision` / `ActionPreflightEngine` | **P2.0/P2.2 preview 実装済み** |
| `ActionRecommendationEngine` | **P2.1 実装済み** |
| `ActionMode` → `StorageAction` bridge | `ActionArchitecture.storageAction(from:)`（hardBlock/permanentDelete → nil） |
| `ActionPlanner` | preview hint のみ、実行なし |
| `preview.executable` | **false** |
| `destructiveActionsExecuted` | **false** |
| Case Study reports | `action_recommendations.json` 等 5 ファイル |
| ActionExecutor | **NOT STARTED** |
| Tests | **204**（P20ActionArchitectureTests 含む） |

`CLOUD_EVICT_ONLY` → `removeLocalDownload` にマップ済み。

---

## 7. PROVE → ACT 接続

PROVE で VERIFIED にした claim が ACT preflight の入力:

| ACT Action | 必要な PROVE claim（例） |
|------------|-------------------------|
| MOVE_TO_ICLOUD | user-owned, canonical_path, preservation contract（**SOT TRUE 可**）, not active |
| MOVE_TO_TRASH | regenerable VERIFIED, SOT false VERIFIED, no open handle |
| REMOVE_LOCAL_DOWNLOAD | File Provider, remote exists, sync safe |
| KEEP | RED / UNKNOWN / conflict |

P1.10 EntityVerificationLoop が backlog を供給。ACT はその上に乗る。

---

## 8. v0.1 ACT scope（実行フェーズ到達後）

1. Trash（証明済み生成物）
2. iCloud move（verify 後 release）
3. Remove Local Download（File Provider native）
4. Keep / Block（RED, UNKNOWN）
5. Post-action verify
6. Audit log

除外: Permanent Delete, auto bulk, raw rm, LLM override

---

## 9. Product flow

```text
SCAN → UNDERSTAND → VERIFY → PROVE
  → CHOOSE BEST ACTION
  → PREVIEW → USER APPROVAL → FRESH PREFLIGHT
  → SAFE ACTION → POST-ACTION VERIFY
```

---

## 10. ChatGPT 依頼テンプレ

```text
上記 + docs/ACTION_ARCHITECTURE_v0.1.md を読んだ上で:

1. StorageAction enum と既存 ActionMode の migration 方針
2. ICloudTransactionPhase 各段階の preflight predicate 一覧
3. ActionRecommendationEngine の入力（ClassifiedItem + VerificationAnnotation）設計
4. Voice Memo / iOS Backup を MOVE_TO_ICLOUD から守る rule 設計
5. v0.1 実装順序（Executor なしで Recommendation だけ先に作れるか）

推測で GREEN を増やす提案は不要。
```

---

## 11. 関連ファイル

| ファイル | 用途 |
|----------|------|
| `docs/ACTION_ARCHITECTURE_v0.1.md` | 設計正本 |
| `Sources/SafetyCore/Action/ActionArchitecture.swift` | StorageAction, ICloudTransactionPhase, ActionMode bridge |
| `Sources/SafetyCore/Action/ActionModels.swift` | ActionDecision, ActionBlockReason, ActionPreflightResult |
| `Sources/SafetyCore/Action/ActionSafetyEvaluator.swift` | Entity × Action × State gates |
| `Sources/SafetyCore/Action/ActionRecommendationEngine.swift` | Recommendation（Safety を上書きしない） |
| `Sources/SafetyCore/Action/ActionPreflightEngine.swift` | Read-only preflight preview |
| `Sources/SafetyCore/Action/ActionPolicy.swift` | Voice Memo / iOS Backup / Library blocks |
| `Tests/SafetyCoreTests/P20ActionArchitectureTests.swift` | P2.0 契約テスト |
| `reports/case001/action_*.json` | Case Study action outputs |
| `reports/case001/chatgpt_p20_handoff.md` | **P2.0 主正本 + Case Study 品質レビュー** |
| `reports/case001/chatgpt_dev_status_handoff.md` | PROVE P1.6→P1.10 状況 |
| `tasks.md` | P2.0 status |
