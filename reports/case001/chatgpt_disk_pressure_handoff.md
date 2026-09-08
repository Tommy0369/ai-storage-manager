# ChatGPT Handoff — Mac Disk Pressure Decision Pack
Date: 2026-08-27  
Source: AI Storage Manager Case Study #001 (P1.6)  
Machine: tomitakatsuhiro Mac (Data volume)

---

## 0. Paste this into ChatGPT first (system / first message)

以下をそのままコピペして使ってください。

```text
あなたは Mac の容量判断アドバイザーです。
ただし Mac Cleaner ではありません。

役割:
- Storage Decision Intelligence（何が何か／消してよいか／根拠は何か）を整理する
- 削除の実行コマンドを勝手に出さない
- 「証明済み」と「未証明」を絶対に混ぜない
- 容量がギリギリでも、RED / 原本 / 不明を安易に消す提案をしない

絶対ルール:
1. UNKNOWN を GREEN扱いしない
2. 古い = 不要、ではない
3. キャッシュ名 = 安全、ではない
4. regenerable = 今消してよい、ではない
5. 実行中/開いている可能性のあるデータは止め
6. ユーザー原本（写真・ボイスメモ・iOSバックアップ・Documents・設定）は保護
7. 提案は「確認手順 → 期待回収 → 失敗時の影響」の順
8. 自動削除スクリプトは出さない（手動確認前提）
9. 根拠が薄い候補は「保留」と明記する

私の目的:
PCの空き容量が約11GBしかなく、使用率98%。安全に空きを増やしたい。
大きく空く候補と、小さくても証明済みの候補を分けて優先順位をつけてほしい。

次のメッセージにスキャン結果を貼る。
```

---

## 1. Current machine pressure (FACT)

| Item | Value |
|------|-------|
| Data volume size | 460 GiB |
| Data volume used | ~394 GiB |
| Free now | **~11 GiB** |
| Capacity | **~98%** |
| Status | 緊急（新規ビルド・大型DL・VM起動で詰まりやすい） |

これは Finder の「システムデータ」そのものではない。  
AI Storage Manager の **unique accounting（二重計上除去後）** ベース。

---

## 2. What this product is (FACT)

Product: **Storage Decision Intelligence**  
Phase: **PROVE**（まだ ACT ではない）

Progression:
UNDERSTAND → VERIFY → PROVE → ACT

Current scan:
- read-only only
- `destructiveActionsExecuted = false`
- `preview.executable = false`
- False GREEN = 0

KPI priority (high → low):
False GREEN回避 > unique会計 > 証明正しさ > 関係証明 > 意味理解 > GREEN/回収GB

---

## 3. Case Study #001 snapshot (FACT)

Scan date context: 2026-08-27 / P1.6  
Runtime: ~203.7 sec  
Entities: 507  
Unique bytes: **154.02 GiB**（165,382,750,208 bytes）

Safety class unique:
| Class | GiB | Meaning |
|-------|-----|---------|
| RED | 142.56 | 保護・原本・高リスク |
| YELLOW | 7.30 | 要レビュー |
| UNKNOWN | 4.13 | 証拠不足 |
| GREEN | 0.04 | 証明済み候補（極小） |

Domain unique (top):
| Domain | GiB |
|--------|-----|
| macOS | 104.48 |
| AI Tools | 42.15 |
| Node | 5.32 |
| Xcode | 1.13 |
| Homebrew | 0.49 |
| Python | 0.43 |

Semantic:
- L3+: 64.6%
- L4+: 54.1%
- L5: 0%
- Semantic Debt: ~65.9 GiB

Proof enrichment:
- Cursor VERIFIED workspace links: **0**（basename類似は VERIFIED にしない）
- Claude exact ACTIVE VERIFIED: **0**
- DerivedData regenerable TRUE VERIFIED: **2**
- DerivedData SOT FALSE VERIFIED: **2**
- Verification chains: 243（strict VERIFIED 239）

---

## 4. Hard DO-NOT-DELETE (unless explicit user intent)

これらは今の証拠では「空きのため即削除」対象にしない。

### 4.1 User originals / recovery
| Path / entity | ~GiB | Why protected |
|---------------|------|---------------|
| iOS Backup `.../MobileSync/Backup/00008110-...` | 24.83 | 端末バックアップ原本。消すと復元不能リスク |
| Voice Memos recordings | 13.04 | ユーザー録音原本 |
| Documents / Desktop 系プロジェクト | — | ソース・原本 |

### 4.2 Active / mixed / unverified AI state
| Path / entity | ~GiB | Why stop |
|---------------|------|----------|
| Cursor `User/globalStorage` | 11.94 | エディタ状態・索引。丸ごと削除禁止 |
| Claude `rootfs.img` | 10.00 | ACTIVE exact未証明。消すと再構築コスト大。今は RED |
| Cursor snapshot store objects `81a50d8e-...` | 4.80 | workspace関係が VERIFIED でない |
| Ollama blobs | 2.33 | モデル本体。消すと再DL |
| Codex sessions/config | ~3.5 | 履歴・設定混在 |

### 4.3 Large unresolved / mixed buckets
| Path | ~GiB | Note |
|------|------|------|
| Application Support (residual) | ~17 | 未分解が大きい |
| Library/Caches (residual) | ~9.9 | 名前だけで消さない |
| Chrome App Support | ~9.6 | 混合（履歴/拡張/状態） |
| Group Containers | ~7.5 | アプリ共有データ |
| Containers | ~7.4 | サンドボックス本体 |
| TomyLocal | ~6.7 | 中身未証明。要分解 |

---

## 5. Decision tiers for “disk is almost full”

### Tier A — Proven small (safe to discuss as first win)
証拠: regenerable TRUE VERIFIED + SOT FALSE VERIFIED + no open handle + process not running

| Target | Path | Bytes | Recoverable? |
|--------|------|-------|--------------|
| Xcode DerivedData Runner (iOS) | `~/Library/Developer/Xcode/DerivedData/Runner-ecnbmvkdltyrtnevcspalufxjhdq` | ~36 MB | 再ビルドで戻る（和牛アプリ iOS） |
| Xcode DerivedData Runner (macOS) | `~/Library/Developer/Xcode/DerivedData/Runner-ckovnoskqurramhgydmrtirfscgd` | ~0.1 MB | 同上（macOS） |

合計回収見込み: **約 36 MB**  
緊急度に対するインパクト: **小さい**（でも「証明済みの型」）

手動確認:
1. Xcode を閉じる
2. 上記2フォルダのみ確認
3. 必要なら Xcode > Settings > Locations > DerivedData から該当を削除、または Finder で該当フォルダのみ削除
4. 次回ビルドが遅くなるのは想定内

### Tier B — Human review, high leverage, NOT proven GREEN
「空きを作りたいならここを見る」だが、**自動削除推奨ではない**。

| Priority | Target | ~GiB | Class | Evidence status | Review question |
|----------|--------|------|-------|-----------------|-----------------|
| B1 | `~/.Trash` | 0.58 | — | 実測 | 中身確認後に空にできるか |
| B2 | `~/Downloads` | 1.05 | YELLOW | 要目視 | 残すZIP/動画/インストーラは？ |
| B3 | `~/.npm/_cacache` | 5.32 | YELLOW | 再取得可能なことが多いが未厳密証明 | 直近で npm/pnpm を多用するか |
| B4 | `~/.cache/huggingface/hub` | 2.87 | UNKNOWN | モデル再DL前提 | 今使うモデルはどれか |
| B5 | Claude Cache | 0.77 | RED | cache名でも丸ごと安全ではない | Claude終了後にキャッシュ限定か |
| B6 | Cursor CachedData / logs | ~1.0 | RED | 状態損失リスク | キャッシュ限定か |
| B7 | CoreSimulator Devices | 0.92 | YELLOW | シミュレータ再作成可のことが多い | 今使う端末だけ残すか |

B1+B2だけでも **~1.6 GiB**  
B3まで入れると **~7 GiB級**（要確認）

### Tier C — Large but high-risk / incomplete proof
ここを触るなら「空き」より「何を失うか」が先。

| Target | ~GiB | Risk |
|--------|------|------|
| Claude VM rootfs | 10.0 | 再生成未証明 / ACTIVE未証明。消すとClaude DesktopのVM再構築 |
| Cursor globalStorage | 11.9 | 作業状態・索引喪失 |
| Cursor snapshot store | 4.8+ | どのworkspaceか未VERIFIED |
| iOS Backup | 24.8 | 端末復元不能リスク |
| Voice Memos | 13.0 | 原本喪失 |
| TomyLocal | 6.7 | 中身不明のまま消すな |

---

## 6. Recommended conversation outcomes for ChatGPT

ChatGPTへの依頼（2通目以降）例:

```text
上のデータを前提に、次を出して:
1) 今すぐ空きを増やす「確認付き」手順（合計目標 +8GB以上）
2) 触ってよい順（証拠レベル付き）
3) 絶対に今日触らないリスト
4) 各候補の「失うもの / 戻し方 / 所要時間」
5) 11GBしかない状態で危険な操作（大きなコピー、巨大モデルDL、Docker再取得など）の注意

制約:
- 削除コマンドのワンショット提示は禁止
- まず確認チェックリスト
- Tier A/B/C を守れ
```

---

## 7. Practical first 30 minutes (opinion + fact mixed)

FACT:
- 空き ~11 GiB / 98%
- 証明済み回収は ~36 MB のみ

OPINION（優先の提案）:
1. **Trash を目視して空ける**（最短・可逆性が高い）
2. **Downloads を仕分け**（1GB級）
3. **npm cache は「今ビルド中でない」を確認してから検討**（5GB級）
4. HuggingFace hub は「使うモデル名」が言えるまで保留
5. Claude rootfs / Cursor globalStorage / iOS Backup / Voice Memos は触らない
6. DerivedData Runner 2件は証明済みだが、空き貢献は小さい

期待:
- 安全寄りで +2〜7 GiB が見える（B1〜B3次第）
- それ以上は証明不足。無理に掘ると事故る

---

## 8. Key numbers cheat sheet (for ChatGPT)

```text
free ≈ 11 GiB (98% used)
unique analyzed ≈ 154 GiB
RED ≈ 142.6 GiB
YELLOW ≈ 7.3 GiB
UNKNOWN ≈ 4.1 GiB
GREEN proven ≈ 0.04 GiB (DerivedData Runner x2)
False GREEN = 0
preview.executable = false
destructiveActionsExecuted = false

Top heavy:
iOS Backup 24.8
Voice Memos 13.0
Cursor globalStorage 11.9
Claude rootfs 10.0
Library/Caches residual ~9.9
Chrome ~9.6
npm cache 5.3
Cursor snapshot store ~4.8
HF hub 2.9
Ollama 2.3
Downloads 1.1
Trash 0.58
```

---

## 9. Files attached / related in repo

Primary pack: this file  
Raw evidence:
- `reports/case001/storage_summary.json`
- `reports/case001/proof_enrichment_summary.json`
- `reports/case001/deriveddata_proof.json`
- `reports/case001/claude_vm.json`
- `reports/case001/cursor_relationship_graph.json`
- `reports/case001/green_audit_p1_6.json`
- `reports/case001/largest_unresolved_buckets.json`
- `reports/case001/ai_tools_breakdown.json`

---

## 10. One-sentence truth

容量は足りない。  
でも「大きい順に消す」と壊れる。  
今やるのは、**証明済みの小物 + 目視できる回収（Trash/Downloads/npm）**。  
10GB級の AI ランタイムは、証明が来るまで触らない。
