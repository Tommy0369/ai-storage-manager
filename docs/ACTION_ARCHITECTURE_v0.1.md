# Action Architecture v0.1 — Storage Decision Intelligence

Status: **DESIGN**（実装は ACT フェーズ。現在は PROVE。`preview.executable=false`）

## 1. 目的

ACT の目的は DELETE だけではない。

> このデータをどう扱えば、ユーザーのデータを守りながら Mac の容量を安全に解放できるか

Safety の評価単位は変わらない:

```text
Entity × Action × State
```

## 2. First-class actions

| Action | 意味 | v0.1 実行 |
|--------|------|-----------|
| **KEEP** | 現状維持 / ブロック | preview のみ |
| **MOVE_TO_TRASH** | 生成物・再生成可能キャッシュ等 | 条件付き |
| **MOVE_TO_ICLOUD** | ユーザー所有ファイルを iCloud Drive へ安全移転 | 条件付き |
| **REMOVE_LOCAL_DOWNLOAD** | クラウド上は残しローカル実体のみ解放 | File Provider ネイティブのみ |
| **VENDOR_NATIVE_CLEANUP** | brew/docker/npm 等ベンダー CLI | 条件付き |
| Permanent Delete | — | **v0.1 除外** |

## 3. 既存コードとの対応（移行メモ）

現在の `ActionMode`（SafetyRuleEngine 用）:

| 新 First-class | 既存 ActionMode |
|----------------|-----------------|
| KEEP | `NO_ACTION`, `USER_REVIEW`, `HARD_BLOCK` |
| MOVE_TO_TRASH | `MOVE_TO_TRASH`, `OS_API_ONLY` |
| MOVE_TO_ICLOUD | **未実装**（新規） |
| REMOVE_LOCAL_DOWNLOAD | `CLOUD_EVICT_ONLY`（名称・契約を明確化） |
| VENDOR_NATIVE_CLEANUP | `TOOL_CLI_ONLY`, `PACKAGE_MANAGER_COMMAND`, `APP_API_ONLY` |

**DELETE ≠ REMOVE_LOCAL_DOWNLOAD** — 別 Safety 判定・別監査ログ。

## 4. MOVE_TO_ICLOUD — 対象と非対象

### 自動提供してよい例

- Documents / Desktop / Downloads のユーザー作成ファイル
- 動画・アーカイブ・PDF・プロジェクトアーカイブ

### 自動提供してはいけない例

- `~/Library` アプリ状態全般
- Application Support / Containers / Group Containers
- Cursor globalStorage / snapshots
- Claude VM / node_modules / DerivedData / Caches
- runtime images / 意味不明 DB

例外: entity 固有の **relocation contract** が VERIFIED の場合のみ。

## 5. MOVE_TO_ICLOUD — verified transaction

「移して祈る」ではない。内部は **COPY → VERIFY → RELEASE ORIGINAL**。

```text
SOURCE
  ↓ PREFLIGHT
  ↓ TRANSFER TO ICLOUD
  ↓ VERIFY ICLOUD DESTINATION
  ↓ VERIFY UPLOAD / REMOTE STATE
  ↓ VERIFY DATA INTEGRITY
  ↓ OPTIONALLY RELEASE LOCAL COPY
  ↓ VERIFY RECLAIMED STORAGE
```

クラウド永続化が十分 VERIFIED になるまで **ローカル原本を削除しない**。

### Preflight（必須）

- user-owned または relocation-supported
- canonical path VERIFIED
- source exists / readable
- 変更中でない
- iCloud Drive 利用可能
- destination 確定
- quota / conflict / expected size
- SOT 意味理解
- provider state が観測可能

critical evidence が UNKNOWN → **自動実行しない**。

## 6. REMOVE_LOCAL_DOWNLOAD

- クラウドコピーは残す。ローカル materialized copy のみ解放。
- File Provider バックアップ必須。`NSFileProviderManager` eviction 等。
- **raw rm で fake eviction 禁止**。

### Contract

- provider 特定
- File Provider backed
- remote backing VERIFIED（可能な範囲）
- unsynced local changes なし
- sync state safe
- provider が eviction 許可
- fresh preflight + user approval

失敗時: 安全に abort。rm フォールバック禁止。

## 7. iCloud transaction state machine

```text
NOT_STARTED
PREFLIGHT
COPYING
UPLOAD_PENDING
VERIFYING_REMOTE
REMOTE_VERIFIED
LOCAL_RELEASE_ELIGIBLE
RELEASING_LOCAL_COPY
COMPLETED
FAILED
UNKNOWN
CANCELLED
```

部分失敗は正直に。copy 成功だけで local を消さない。

## 8. Failure behavior

| 状況 | 動作 |
|------|------|
| transfer fail | source 維持 |
| upload unknown | source 維持 |
| remote verify fail | source 維持 |
| eviction fail | cloud/source 状態を可視化 |

## 9. Audit log（ファイル内容は保存しない）

- entityID, source/destination path, action
- bytes expected, verification results
- copy/upload/remote/release timestamps
- bytes reclaimed, errors, user approval

## 10. Action Recommendation Engine

「消せる？」だけ答えない。

```json
{
  "recommendedAction": "MOVE_TO_ICLOUD",
  "alternatives": ["MOVE_TO_TRASH", "KEEP"],
  "why": ["USER_OWNED", "ICLOUD_AVAILABLE", "RECOVERY_8.4GB"]
}
```

例:

| Entity | recommended | alternative |
|--------|-------------|-------------|
| user video | MOVE_TO_ICLOUD | MOVE_TO_TRASH |
| DerivedData | MOVE_TO_TRASH | KEEP |
| iCloud doc synced | REMOVE_LOCAL_DOWNLOAD | KEEP |
| Voice Memo original | KEEP | SYNC_TO_ICLOUD_NATIVE（将来） |
| Claude VM unknown | KEEP / VERIFY_MORE | — |
| iOS Backup dir | KEEP / REVIEW | MIGRATE_TO_ICLOUD_BACKUP（将来・別契約） |

## 11. v0.1 ACT target（実行フェーズ到達後）

1. 証明済み生成 entity → Trash
2. 適格 user file → iCloud Drive（verify 後 release）
3. File Provider verified entity → Remove Local Download
4. RED / UNKNOWN → Keep / Block
5. Post-action storage verification
6. 完全監査履歴

除外: Permanent Delete, 自動一括, unsafe bulk, LLM override, raw rm fallback

## 12. Product flow

```text
SCAN → UNDERSTAND → VERIFY → PROVE
  → CHOOSE BEST ACTION
  → PREVIEW → USER APPROVAL → FRESH PREFLIGHT
  → SAFE ACTION → POST-ACTION VERIFY
```

## 13. 実装ファイル（design-only, PROVE 中）

- `Sources/SafetyCore/Action/ActionArchitecture.swift` — 型と契約のみ
- 実行: `ActionExecutor`（P2, NOT STARTED）

## 14. PROVE フェーズとの関係

PROVE で積む VERIFIED claim が ACT preflight の入力になる。

例: MOVE_TO_ICLOUD には `user-owned VERIFIED` + `canonical_path VERIFIED` が必要。  
DerivedData に MOVE_TO_ICLOUD を出さないのは Safety だけでなく **semantic contract** でも禁止。
