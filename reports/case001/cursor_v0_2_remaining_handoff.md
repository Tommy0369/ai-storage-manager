# Cursor Handoff — AI Storage Manager v0.2

Date: 2026-09-08
Repo: `~/Workspace/10_進行中/ai-storage-manager`
Branch: `main`（**コミットは1件も無い**。全ファイルが untracked）

---

## 0. 絶対に守ること

| ルール | 内容 |
|--------|------|
| **v0.1 凍結** | `dist/` は `V0_1_GLOBAL_RELEASE_FROZEN`。再ビルド・再署名・再公証・上書き **禁止** |
| **開発出力** | v0.2 の成果物は `dist-dev/` のみ。`bash scripts/package-dev-app.sh` を使う |
| **Git** | NO COMMIT / NO TAG / NO PUSH |
| **Safety** | SafetyClass / ActionDecision / MutationReadiness / candidateBytes / verifiedRecoveredBytes を変えない |
| **Executor** | 3個のまま（Trash / Ollama / HuggingFace）。追加も意味変更もしない |
| **実 mutation** | 実行しない。`ollama rm` / HFキャッシュ削除 / ゴミ箱移動は禁止 |
| **Research** | FROZEN。再開しない |

### v0.1 の指紋（作業の前後で必ず一致させること）

```
dist/AIStorageManager-0.1.0-rc50-arm64.zip
  SHA-256 3f9983dbcc705e99cf252ab6e1750ae854b7881271d3a23b452ec2a0ef2e2819

dist/.p55_bundle_content_fingerprint
  b509184cbdc9967bf2142c43505766e728d36116b868a57f0ce819751a838d9e
```

`scripts/package-release-app.sh` には**凍結ガード**を入れてある。
`dist/` に凍結マーカーがある間は再ビルドを拒否する。外そうとしないこと。

---

## 1. すでに完了していること（v0.2 UX FIX 001）

判定 `UX_FIX_001_COMPLETE`。詳細は `reports/case001/v0_2_ux_fix_001_総合レポート.md` と
`reports/case001/v0_2_ux_fix_001.json`。

- **分割線のゴースト**: `mapSplit` を `HSplitView` に置換。境界の所有者を1つにした。
  8状態で「可視の縦線＝ドラッグ可能なsplitter」を実測確認
- **lensラベル**: どこにある？ / これは何？ / どうする？（内部識別子は STRUCTURE/MEANING/DECISION のまま）
- **スキャン状態**: `StorageScanStatus` に一本化。「失敗」と「スキャン中」の同時表示を解消
- **ネイティブAppメニュー**: バンドルに `en.lproj` / `ja.lproj` を同梱 + `AppleLanguages` 同期
- **テスト**: 819/0 → **843/0**（新規24件）

変更したファイル:

```
Sources/AIStorageManagerApp/AIStorageManagerApp.swift
Sources/AIStorageManagerUI/AppMenuLocalizer.swift          （新規）
Sources/AIStorageManagerUI/AppShellView.swift
Sources/AIStorageManagerUI/Explorer/StorageExplorerView.swift
Sources/AIStorageManagerUI/ProductCopy.swift
Sources/AppServices/Localization/AppMenuTitles.swift        （新規）
Sources/AppServices/Localization/LanguageStore.swift
Sources/AppServices/StorageExperience/StorageExplorerBuilder.swift
Sources/AppServices/StorageExperience/StorageExplorerModels.swift
Sources/AppServices/StorageExperience/StorageScanStatusPresentation.swift  （新規）
Sources/AppServices/Resources/Localization/LocalizationCatalog.json  （生成物）
Sources/AppServices/Resources/Localization/Localizable.xcstrings     （生成物）
Tests/AppServicesTests/V02UXFix001Tests.swift              （新規）
scripts/generate-localization-catalog.py
scripts/package-dev-app.sh                                 （新規）
scripts/package-release-app.sh
```

---

## 2. 残作業 — 優先度順

### A. 【最優先・バグ】設定画面が空白で描画されない

**症状**: サイドバー「設定」を選ぶと、ナビゲーションタイトルは「設定」に変わるが
中央ペインが完全に空白。言語ピッカーに到達できない。

**切り分け済み**:

| セクション | 描画 |
|-----------|------|
| ストレージ（Overview） | OK |
| プラン（storageGoal） | OK |
| 履歴（recentActions） | OK |
| **設定（settings）** | **空白** |

→ シェル全体の問題ではなく `SettingsDebugGateView` 固有。

**重要**: **凍結済み v0.1 でも同じ症状**を確認済み。v0.2 の変更が原因ではない既存バグ。

**起点**:
- `Sources/AIStorageManagerUI/AppShellView.swift:82` — `case .settings:` の分岐
- `Sources/AIStorageManagerUI/AppShellView.swift:166` — `private struct SettingsDebugGateView`
- 同ファイル内で `Form { ... }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`

**未検証の仮説**（どれも実測していない。鵜呑みにしないこと）:
1. `Form` + `.frame(maxHeight: .infinity, alignment: .topLeading)` の組み合わせが
   NavigationSplitView の content カラムで潰れている
2. `@EnvironmentObject private var languageStore` が解決できず body が評価されていない
   （`AppShellView` は `.environmentObject(languageStore)` を明示的に渡している）
3. `LabeledContent` の macOS 26 上での挙動

**影響**: これが直るまで、アプリ内の言語切替をUIから実行できない。
切替の仕組み自体はテストと「言語を設定した状態での起動」で検証済み。

---

### B. 【バグ】残っている英語ハードコード 16箇所

トップバーとサイドバーは v0.2 で対応済み。**画面全体ではまだ英語が残る**。

例: 「履歴」画面は日本語UIでも `Recent Actions` / `No actions yet.` と表示される。

| ファイル | 件数 |
|---------|------|
| `Sources/AIStorageManagerUI/Lists/StorageListsView.swift` | 5 |
| `Sources/AIStorageManagerUI/CandidateDetailView.swift` | 4 |
| `Sources/AIStorageManagerUI/StorageMap/StorageMapView.swift` | 2 |
| `Sources/AIStorageManagerUI/Details/EntitySelectionPanel.swift` | 2 |
| `Sources/AIStorageManagerUI/Overview/CompactDiskSummaryBar.swift` | 1 |
| `Sources/AIStorageManagerUI/Optimization/OptimizationPlanView.swift` | 1 |
| `Sources/AIStorageManagerUI/Change/StorageChangeViews.swift` | 1 |

洗い出しコマンド:

```bash
grep -rnoE '(Text|Label|Section|navigationTitle)\("[A-Z][A-Za-z0-9 ,.'"'"'!?:%-]{3,}"' \
  Sources/AIStorageManagerUI --include=*.swift \
  | grep -v OverviewScreenshotExport | grep -v ContentView
```

アクセシビリティラベル（`Category list alternative to storage map` など）も英語のまま。

**やり方**: 文字列を直接書き換えず、`scripts/generate-localization-catalog.py` に
`add("key", en=..., ja=..., ...)` で9ロケール分追加 →
`python3 scripts/generate-localization-catalog.py` で再生成 →
ビューでは `L10n.t("key")` を呼ぶ。

**制約**: `Tests/AppServicesTests/P54LocalizationReleaseQATests.swift` が
**全ロケールでカバレッジ100% / missingKeys 0** を要求する。
1ロケールでも欠けるとテストが落ちる。

---

### C. 【未使用コード】`ContentView.swift`

`ContentView()` はどこからも呼ばれていない（本番シェルは `AppShellView`）。
英語ハードコードを6箇所抱えたまま残っている。削除するか、残すなら理由をコメントに書く。

---

### D. 【要判断・とみー】v0.2 のスコープ確定

今回の UX 修正を

- v0.2 として出すのか
- v0.1.1 のパッチとして切るのか

を決める。決まるまで署名・公証には進まない。

---

### E. 【スコープ確定後】リリース出力の作成と署名・公証

**v0.1 の `dist/` は絶対に使わない。** 新しい出力先（例 `dist-0.2/`）を用意する。

手順は P5.1 / P5.5 と同じ。Developer ID とnotary profileは設定済み:

```
署名ID : Developer ID Application: Katsuhiro Tomita (2MK7L9N4N7)
profile: AIStorageManagerNotary   （Keychain。リポジトリに秘密情報は無い）
```

`scripts/package-release-app.sh` は `DIST_DIR` 環境変数で出力先を切り替えられる。

版番号を上げる場合、`packaging/Info.plist` の
`CFBundleShortVersionString` / `CFBundleVersion` と
`scripts/package-release-app.sh` の `VERSION` / `BUILD` を揃えること。

---

## 3. 開発・検証の手順

### ビルドとテスト

```bash
cd ~/Workspace/10_進行中/ai-storage-manager
swift build
swift test                       # 期待値 843 / 0 failures
bash scripts/package-dev-app.sh  # dist-dev/ に ad-hoc 署名の .app
```

### 実機確認で踏んだ落とし穴（同じ穴を掘らないこと）

1. **`open` で起動すること。** バイナリを直接実行すると LaunchServices を通らず、
   SwiftUI のメニュー再構築タイミングが変わって**挙動が変わる**。実利用と同じ経路で確認する。

2. **バックグラウンドで `&` 起動しない。** シェルが終わると子プロセスも死ぬ。
   `open` で切り離すこと。

3. **フルスクリーン状態が保存される。** 前回フルスクリーンで終了すると、
   次の起動でウィンドウが別 Space に入り `CGWindowListCopyWindowInfo`
   （`optionOnScreenOnly`）から見えなくなる。検証前に消す:
   ```bash
   rm -rf ~/Library/Saved\ Application\ State/com.tomystudio.aistoragemanager.savedState
   ```

4. **メニューの検証はスクリーンショットを正とする。**
   アクセシビリティ API のメニュー読み取りは**古い値を返すことがある**。
   実際に「AXは英語 / プロセス内部は日本語 / 実画面は日本語」と3者が食い違った。

5. **権限**: Screen Recording と アクセシビリティが両方必要。
   無いと `screencapture` が `could not create image from display`、
   System Events が `-25211` で落ちる。

### 分割線を触る場合の検証の型

線の本数を目視で数えない。次の不変条件を機械的に確認する。

> **画面上の縦線の本数 == ドラッグ可能な splitter の本数、かつ各線が splitter の座標上にある**

AX の splitter 座標（`AXSplitter` の frame）と、スクリーンショットからピクセル検出した
縦線位置を突き合わせる。この型で「ゴースト線ゼロ」を客観的に言える。

回帰テストとして
`Tests/AppServicesTests/V02UXFix001Tests.swift` の
`testMapSplitBoundaryHasASingleNativeOwner` がソースレベルで
「装飾 `Divider()` + 固定幅」の再発を防いでいる。

---

## 4. 設計上の決定（変えるなら理由を持って）

### ネイティブ App メニューはバンドルローカライズが正

実行時に `NSApp.mainMenu` の title を書き換えても効かない。
AppKit は標準メニューを**バンドルの `.lproj` から**描画し、SwiftUI が起動後に作り直す。

- `en.lproj` / `ja.lproj` を同梱する方式に決めた（空の `InfoPlist.strings` だけでよい）
- これで About/Services/Hide/Quit に加えて Edit/View/Window/Help まで一貫する
- アプリ内の言語選択は `AppleLanguages` に書いて次回起動から反映（設定画面が既に再起動要と表示）

**実行時書き換えだけを試すと Services だけ効いて日英混在になる。全部英語より悪い。**
`AppMenuLocalizer` は残してあるが、Services の特別扱いは意図的に外してある。

### ネイティブメニューは日本語か英語の二択

製品UIは9言語のまま。ネイティブメニューだけ en/ja に絞るのは意図的な設計。
`AppMenuTitles.usesJapanese` は **実効ロケール**で判定する
（`.system` でもシステムが日本語なら日本語）。enum の一致比較にしないこと。

### スキャン状態は1状態＝1文

`StorageScanStatusResolver.resolve(stage:coverage:)` が唯一の入口。
バナーに文字列を並べない。**部分的に読めなかった状態を「失敗」と呼ばない。**

---

## 5. 引き継ぎ時点の状態

| 項目 | 値 |
|------|-----|
| テスト | 843 / 0 failures |
| Safetyカウンタ | 全ゼロ |
| 実 storage mutation | 0件 |
| 正規 recovery 合計 | 5,580,814,899 bytes |
| Executor | 3個 |
| v0.1 凍結資産 | 不変（SHA・fingerprint 一致、staple 有効） |
| Git | commit / tag / push なし |
