# v0.2 UX FIX 001 — 総合レポート

**判定: `UX_FIX_001_COMPLETE`**

- 日付: 2026-09-08
- 対象: 分割線の視覚的ズレ / トップバー文言 / スキャン状態文言 / ネイティブAppメニュー
- 基準: **v0.1 は `V0_1_GLOBAL_RELEASE_FROZEN` のまま不変**

---

## 1. v0.1 の保護

| 項目 | 結果 |
|------|------|
| ZIP SHA-256 | `3f9983dbcc705e99cf252ab6e1750ae854b7881271d3a23b452ec2a0ef2e2819`（変化なし） |
| bundle fingerprint | `b509184cbdc9967bf2142c43505766e728d36116b868a57f0ce819751a838d9e`（変化なし） |
| staple | 依然 valid |
| 再ビルド / 再署名 / 再公証 | いずれも実施していない |
| v0.2 の開発出力 | `dist-dev/AI Storage Manager.app`（別ディレクトリ） |

`scripts/package-release-app.sh` に**凍結ガード**を追加した。
`dist/` に凍結マーカーがある間は再ビルドを構造的に拒否する。
以前のスクリプトは `rm -rf` で凍結成果物を壊せる状態だった。

---

## 2. 分割線 — 根本原因

`StorageExplorerView.mapSplit` が分割を手組みしていた。

```swift
HStack {
    map
    Divider()                                   // 装飾。境界ではない
    ExplorerInspectorView.frame(width: 320)     // 境界はこの固定幅の中にあった
}
```

セパレータと境界の所有者が別々だった。結果として画面には
**見分けのつかない縦線が2本**あり、片方（NavigationSplitView の `AXSplitter`）だけが
ドラッグ可能な本物の境界だった。

### 実測（修正前）

| 計測 | 値 |
|------|-----|
| ドラッグ可能な splitter | **1本**（x=1127pt） |
| 画面上の縦線 | **2本**（x=1612px / 2254px） |
| 装飾線（x=579pt）をドラッグ | **何も動かない** |

本物をドラッグすると、動かない方が取り残される。
これが「古い位置に太い縦線が残る」の正体。

---

## 3. 分割線 — 修正

`HSplitView` に置き換え、AppKit の `NSSplitView` にセパレータと境界の
**両方を所有させた**。線を隠したのではなく、所有権を1つにした。

- インスペクタの既定幅は **320pt**（v0.1 と同一）
- 固定ではなく **320〜560pt でドラッグ可能**になった
- マップ側に `layoutPriority(1)` を与え、余白はマップが取る

### 検証（修正後）

不変条件: **画面上の縦線の本数 == ドラッグ可能な splitter の本数、かつ各線が splitter 上にある**

| 状態 | splitter | 可視線 | 判定 |
|------|---------|--------|------|
| フルスクリーン 既定 | 2 | 2 | PASS |
| フルスクリーン 左へ（約35%） | 2 | 2 | PASS |
| フルスクリーン 中央（約50%） | 2 | 2 | PASS |
| フルスクリーン 右へ（約65%） | 2 | 2 | PASS |
| ウィンドウ復帰 | 2 | 2 | PASS |
| 縮小 1000×780 | 2 | 2 | PASS |
| 拡大 1400×900 | 2 | 2 | PASS |
| 再フルスクリーン | 2 | 2 | PASS |

ゴースト線 **0本** / 重複 divider **0本** / 復帰後のジャンプ **なし**。

検証はスクリーンショットの目視だけに頼らず、
AXのsplitter座標とピクセル検出した縦線位置を突き合わせて行った。

---

## 4. lens ラベル

| 内部識別子 | 日本語 | 英語 |
|-----------|--------|------|
| `STRUCTURE` | どこにある？ | Where? |
| `MEANING` | これは何？ | What is it? |
| `DECISION` | どうする？ | What can I do? |

内部の enum・rawValue は **STRUCTURE / MEANING / DECISION のまま不変**。
表示ラベルのみを 9 ロケール分カタログ化した。
セグメンテッドコントロールは幅を 280/300 → 360 に広げた（フォント縮小はしていない）。

---

## 5. スキャン状態

### 修正前の問題

バナーが「ステージ名」と「さらに詳しくスキャン中…」チップを
**常時回転するスピナーの横に並べていた**。
そのため失敗時に次の3つが同時に出た。

- スピナー（進行中の合図）
- 「スキャンに失敗しました」
- 「さらに詳しくスキャン中…」

### 修正後

`StorageScanStatus` に一本化した。**1つの状態 → 1つの文**。

| 状態 | 日本語 |
|------|--------|
| ACTIVE | スキャン中… |
| DEEPENING | さらに詳しく確認しています… |
| PARTIAL_CONTINUING | 一部を確認できませんでした。残りをスキャンしています… |
| COMPLETE | スキャン完了 |
| FAILED | スキャンを完了できませんでした |

- **部分的に読めなかっただけの状態を「失敗」とは呼ばない**
- スピナーは実際に処理が動いているときだけ出す
- カバレッジは「状態」であって「進行」ではない。
  サンバースト中央とストーリーチップの「さらに詳しくスキャン中…」も
  「一部を確認できませんでした」に直した（スキャン停止後も残る表示だったため）

---

## 6. トップバーの英語混入

| 箇所 | 修正前 | 修正後（日本語） |
|------|--------|-----------------|
| ストーリー | `.colima is the largest mapped folder: 10.1 GB.` | `.colima が現在もっとも大きいフォルダです：10.1 GB` |
| マップ内訳 | `In this folder` | このフォルダ直下 |
| サイドバー見出し | `Navigate` | 移動 |
| サイドバー見出し | `At a glance` | ひと目で |

新規キー 13 件、全 9 ロケールに翻訳あり（欠損 0）。総キー数 235。
**9言語対応は削っていない。**

---

## 7. ネイティブ App メニュー

### 根本原因

アプリバンドルに **日本語ローカライズ（`ja.lproj`）が無かった**。
AppKit は標準メニューを**バンドルのローカライズから**描画し、
SwiftUI は起動後にメニューを作り直す。
そのため `NSApp.mainMenu` を実行時に書き換えても上書きされ、
日本語UIの隣で英語メニューが残り続けていた。

実行時の書き換えだけを試した段階では、
Services だけが変わって**日英が混在する**という、より悪い状態になった。

### 修正

1. パッケージング時に **`en.lproj` と `ja.lproj` を同梱**し、macOS 自身に標準メニューを
   ローカライズさせる（Edit / View / Window / Help も含めて一貫する）
2. アプリ内の言語選択を **アプリ自身の `AppleLanguages`** に反映し、
   次回起動時にネイティブメニューへ届くようにした
   （再起動が必要な旨は設定画面が既に表示している）

`en` + `ja` のみを同梱するのは意図的。
製品UIは9言語のまま、ネイティブメニューは日本語か英語かの二択という設計。

### 検証（実画面のスクリーンショット）

| 言語 | About | サービス | 非表示 | ほか | すべて | 終了 |
|------|-------|---------|--------|------|--------|------|
| 日本語 | AI Storage Managerについて | サービス | AI Storage Managerを非表示 | ほかを非表示 | すべてを表示 | AI Storage Managerを終了 |
| 英語 | About AI Storage Manager | Services | Hide AI Storage Manager | Hide Others | Show All | Quit AI Storage Manager |

- ショートカット **⌘H / ⌥⌘H / ⌘Q** すべて保持
- Services サブメニュー健在
- action / selector は一切変更していない
- 日英の混在なし

`AppMenuTitles` は selector で項目を特定する。
title 文字列での照合はしていない（title こそが変わる対象なので、
title 照合は必要になった瞬間に壊れる）。
`terminate:` は Quit とその Option 代替の両方が使うため、`isAlternate` で判別している。

---

## 8. 回帰

| | 結果 |
|---|---|
| Tests（前） | **819 / 0 failures** |
| Tests（後） | **843 / 0 failures** |
| 新規テスト | 24 件 |

| Safety カウンタ | 値 |
|----------------|-----|
| False GREEN | 0 |
| duplicateEvaluations | 0 |
| secondCrawlerAdded | false |
| UNKNOWNAuthorizationCount | 0 |
| contractGateBypassCount | 0 |
| approvalBypassCount | 0 |
| unverifiedRecoveryPresentationCount | 0 |
| fakeRecoverableByteCount | 0 |
| mutationAutoRetryCount | 0 |

- Safety セマンティクスの差分: **なし**
- ActionDecision の差分: **なし**
- 実 storage mutation: **0件**
- 正規 recovery 合計: 5,580,814,899 bytes（不変）
- Executor: 3個（不変）

ロケールを 10 種類切り替えても
`verifiedCompletedRecoveryTotal` と executor 集合が動かないことをテストで固定した。

---

## 9. 途中で見つけた既存の不具合（今回の範囲外）

**設定画面が空白**。言語ピッカーに到達できない。

- **凍結済み v0.1 でも同じ**ことを確認済み。今回の変更が原因ではない
- 影響: アプリ内での言語切替を UI 経由で実行できない。
  切替の仕組み自体はテストと、言語設定を与えた状態での起動で検証した
- 今回の指示範囲（分割線・lens文言・スキャン文言・Appメニュー）外のため修正していない

---

## 10. スクリーンショット

- `reports/case001/screenshots/v02_split_fullscreen_left.png`
- `reports/case001/screenshots/v02_split_fullscreen_right.png`
- `reports/case001/screenshots/v02_topbar_ja.png`
- `reports/case001/screenshots/v02_topbar_en.png`
- `reports/case001/screenshots/v02_appmenu_ja.png`
- `reports/case001/screenshots/v02_appmenu_en.png`

---

## 11. Git

- commit: なし
- tag: なし
- push: なし

指示どおり未実施。

---

## 12. 推奨する次のステップ

1. 設定画面が空白になる既存不具合の調査（言語切替が塞がれている）
2. v0.2 のスコープ確定 — 今回の UX 修正を v0.2 に載せるか、v0.1.1 として切るか
3. 確定後に P5.5 相当の署名・公証フローを **dist-dev ではなく新しいリリース出力**に対して実行
