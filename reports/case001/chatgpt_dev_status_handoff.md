# ChatGPT Handoff — AI Storage Manager 開発状況（P1.6→P1.10）
Date: 2026-08-28  
Audience: ChatGPT（設計・実装継続用）  
Repo: `~/Workspace/10_進行中/ai-storage-manager`

---

## 0. 先に貼る指示（ChatGPT用）

```text
あなたは AI Storage Manager の共同開発パートナーです。
このプロジェクトは Mac Cleaner ではありません。
Storage Decision Intelligence です。

現在フェーズ: PROVE（ACT/UI/自動削除は未着手）

絶対NG:
- 破壊的操作（Delete/Trash/prune/evict）
- preview.executable=true / destructiveActionsExecuted=true
- UNKNOWN→GREEN自動昇格 / INFERREDでstrict predicate
- Verification Loop / Detector が Safety Class を決める
- 偽VERIFIED（basename/similarity/adjacency）
- Cursor DB value LIKE全走査
- du timeout→full recursive walk フォールバック
- timeout/budget→0 bytes 扱い（UNMEASURED≠EMPTY）
- per-entity lsof/ps/du（one-shot snapshot 以外禁止）

やってほしいこと:
- 現状理解の確認
- 次フェーズ（P1.11候補: entity_verification_safety_eval 最適化）の設計提案
- 証拠基準を弱めない
- MEASURE / UNDERSTAND / VERIFY / PROVE を分離維持
- 「次に何を証明するか」を backlog 駆動で設計する

次のメッセージに開発状況の正本を貼る。
```

---

## 1. Product definition（FACT）

**Not a Mac Cleaner.** **Storage Decision Intelligence.**

`MEASURE → UNDERSTAND → VERIFY → PROVE → ACT` — 現在 **PROVE**

成功の定義は「消せるGBを増やす」ことではない。  
**未解決Claimを bounded に検証し、Verified Knowledge を積む。**  
証拠不足を確認して `UNKNOWN + exact reason` になることも成功。

---

## 2. 開発の流れ（P1.6→P1.10 ナラティブ）

### Phase arc: 「証明を強くし、計測を正直にし、runtimeを下げ、proofを orchestrate する」

| Phase | テーマ | Runtime | 主な成果 |
|-------|--------|---------|----------|
| P1.6 | Real-Mac Proof Enrichment | ~204s | DerivedData lightweight proof、basename VERIFIED撤廃、strict VerificationChain |
| P1.7 | Explicit Metadata + Runtime | ~166s | workspaceStorage VERIFIED=8、vscdb key-only、du cache |
| P1.8 | Detector Catalog Profiling | ~142s | per-detector計測、正直Cursor関係、MacOS/Git最適化 |
| P1.9 | Scanner I/O + Bounded Measurement | ~101s | ScanSessionContext、SizeMeasurement quality、timeout→UNKNOWN |
| **P1.10** | **Entity Verification Loop** | **~89s** | bounded proof orchestration、backlog/yield、evidence cache |

**Runtime progression:** 204 → 166 → 142 → 101 → **89 sec**

---

## 3. P1.9 まで（要約）

### P1.9 の核心
- **`ScanSessionContext`** — per-scan measurement authority
- **`SizeMeasurement`** — EXACT / UNKNOWN（timeout ≠ 0 bytes）
- bounded du only — unbounded fallback 完全撤廃
- scanner 47→17s、total 142→101s
- 巨大 root（Caches/AppSupport/Containers）→ DU timeout 時 **UNKNOWN** を正直記録

---

## 4. P1.10 — Entity Verification Loop（PARTIAL）

### 問題
P1.9 後、`entity_verification_loop` ~41s が主ボトルネック。  
499 entities に対し per-entity resolver + Safety eval が直列で走っていた。  
「何を証明するか」の優先順位も見えなかった。

### やったこと

**新アーキテクチャ:**
```
DetectedEntity
  ↓
VerificationCandidateBuilder（priority = claim tier × semantic × cost）
  ↓
EntityVerificationLoop（global budget + strategy selection）
  ↓ bounded proof attempt
VerificationStrategies（既存 Resolver/Detector ロジック再利用）
  ↓
VerificationChain / SafetyRuleEngine / GreenCandidateAuditor
```

**新規コンポーネント:**
- `VerificationCandidate` — unresolvedClaims, strategiesAvailable, priority, blockingReasons
- `VerificationClaimType` — SOT/Regen/Active/BELONGS_TO_WORKSPACE 等（tier 1/2/3）
- `VerificationStrategies` — CursorMetadata, ClaudeVMActive, DerivedData, FileProvider, Resolver系
- `EvidenceResolutionCache` — canonical path 単位で evidence + open handle キャッシュ
- `EntityVerificationLoop` — loop は Safety Class を決めない（evidence/claims のみ）

**制約（維持）:**
- UNKNOWN NEVER AUTO-PROMOTES TO GREEN
- INFERRED / UNKNOWN / CONFLICTED は strict chain を満たさない
- recoverable bytes / GREEN 確率で priority を決めない
- node_modules proof は `--proof node-modules` opt-in のまま
- one-shot ps/lsof snapshot のみ（per-entity spawn 禁止）

**新レポート:**
- `entity_verification_backlog.json`
- `entity_verification_loop.json`
- `verification_strategy_runtime.json`
- `verification_loop_coverage.json`
- `p1_10_runtime_comparison.json`
- `green_audit_p1_10.json`
- `evidence_conflicts.json`

### 結果

| Metric | P1.9 | P1.10 |
|--------|------|-------|
| **Total runtime** | 100.8s | **89.3s** |
| `entity_verification_loop` | 40.1s | **31.5s** |
| └ `entity_verification_proof_execution` | — | **5.3s** |
| └ `entity_verification_safety_eval` | — | **26.1s** ← **新ボトルネック** |
| `scanner_filesystem_walk` | 17.0s | 17.0s |
| `detector_catalog` | 36.0s | 36.0s |
| Tests | 163 | **179** |
| False GREEN | 0 | **0** |

**Loop KPI:**
| KPI | Value |
|-----|-------|
| Candidates discovered | 494 |
| Attempted | 93 |
| Skipped (already verified) | 16 |
| Blocked | 401 |
| VERIFIED claims | 43 |
| INFERRED | 56 |
| UNKNOWN | 131 |
| CONFLICTED | 0 |
| Budget exhausted | false |
| **Verification Yield** | **18.6%** |

**Strategy breakdown（proof phase）:**
| Strategy | Attempts | Verified | Unknown |
|----------|----------|----------|---------|
| ActiveStateResolver | 91 | 42 | 0 |
| CursorMetadataProofStrategy | 126 | 0 | 126 |
| ClaudeVMActiveProofStrategy | 7 | 0 | 7 |
| SourceOfTruthResolver | 5 | 1 | 4 |
| FileProviderProofStrategy | 2 | 0 | 1 |

---

## 5. 現在ベースライン（FACT, P1.10 scan）

| Metric | Value |
|--------|-------|
| Runtime | **89.4 sec** |
| Entities | 499 |
| Unique bytes | **~119.0 GiB** |
| L3+ / L4+ / L5 | 89.2% / ~74.5% / 0% |
| GREEN | **1**（DerivedData Runner-ckovnoskqurramhgydmrtirfscgd） |
| False GREEN | **0** |
| Tests | **179** / 0 failures |
| preview.executable | **false** |
| destructiveActionsExecuted | **false** |

**Slowest stages（P1.10）:**
1. `detector_catalog` ~36s
2. `entity_verification_loop` ~31s（内訳: safety_eval ~26s）
3. `scanner_filesystem_walk` ~17s

**Proof KPIs（維持）:**
- Cursor VERIFIED workspace links: **8**
- Claude exact ACTIVE VERIFIED: **0**（契約維持）
- DerivedData regen TRUE VERIFIED: **1**
- DerivedData SOT FALSE VERIFIED: **1**
- Verification chains: **256 (252 strict)**

**Verification Coverage（分離維持）:**
| 次元 | Coverage |
|------|----------|
| Byte Measurement | 100%（accounted unique に対して EXACT） |
| Provenance Verified | 34.3% |
| Verified Relationship | 26.1% |
| SOT Known | 35.2% |
| Regenerability Known | 35.2% |
| Runtime State Known | 33.1% |
| Verification Loop Coverage | 18.6% |

**Measurement honesty（P1.9 継続）:**
- `unknownMeasurementEntities`: **11**
- `accountingCompletenessPercent`: ~40.2%
- timeout → UNKNOWN（0 bytes として会計に混ぜない）

---

## 6. 四つの独立した問い

| 問い | レポート | 意味 |
|------|----------|------|
| A. どれくらい大きい？ | Byte Measurement Coverage | EXACT / UNKNOWN |
| B. 何か？ | Semantic Coverage | L3+/L4+/L5 |
| C. 関係は証明できる？ | Verified Relationship Coverage | VERIFIED links |
| D. Claim は検証済み？ | Verification Loop Coverage / Yield | bounded proof 結果 |

**混ぜない。** semantic=VERIFIED + size=UNKNOWN は許容。

---

## 7. Non-negotiable safety rules（FACT）

```
UNKNOWN NEVER AUTO-PROMOTES TO GREEN
EVIDENCE FAILURE != FALSE
PATH ALONE IS NOT SAFETY
TIMEOUT != ZERO BYTES
UNMEASURED != EMPTY
PARTIAL != COMPLETE
CONFLICTED != VERIFIED
Detector MUST NOT decide Safety Class
Verification Loop MUST NOT decide Safety Class
Only VERIFIED evidence may satisfy strict Safety predicates
GREEN count is NOT a KPI
False GREEN = CRITICAL BUG (currently 0)
```

---

## 8. Architecture（FACT, P1.10）

```
ScanSessionContext → SizeMeasurement (EXACT/UNKNOWN)
  ↓
StorageScanner.scanRoots → bounded du → ScannedNodeCache
  ↓
DetectorCatalog → consumes Scanner measurements
  ↓
VerificationCandidateBuilder → priority queue
  ↓
EntityVerificationLoop
  ├─ VerificationStrategies (bounded, existing resolvers)
  ├─ EvidenceResolutionCache (per canonical path)
  └─ SafetyRuleEngine + GreenCandidateAuditor（loop 外）
  ↓
VerificationChain → strict claim traceability
  ↓
CleanupPreview (executable=false)
```

Process/lsof: one-shot snapshots only.  
Proof tiers: CORE / BOUNDED_DEFAULT_PROOF / OPT_IN_PROOF

---

## 9. Known limitations（FACT）

1. snapshot store → workspace の明示 bridge は実Macにほぼ無い（CursorMetadata 126 unknown）
2. Claude exact ACTIVE VERIFIED = 0（契約維持、process-only 禁止）
3. **`entity_verification_safety_eval` ~26s** が新主ボトルネック（499×SafetyRuleEngine+Auditor）
4. 巨大 root の EXACT 計測は budget 内困難 → UNKNOWN は意図的
5. APFS clone/hardlink 物理一意バイトは未解決
6. KB PROVISIONAL（178 rules）/ REAL_MAC_VERIFIED rules = 0
7. L5 = 0%
8. Verification Yield 18.6% — 低くても安全上重要な proof は継続必要

---

## 10. Top verification backlog（FACT）

優先度高だが未解決が多い領域:

1. **CursorMetadataProofStrategy** — workspaceStorage 以外の snapshot/store（explicit metadata path 不足 → UNKNOWN）
2. **SourceOfTruthResolver** — DerivedData 親 aggregate の SOT（子は verified でも親 inclusive UNKNOWN）
3. **ClaudeVMActiveProofStrategy** — exact handle/cmdline 未達
4. **FileProviderProofStrategy** — cloud provider metadata 不足 → UNKNOWN_NO_PROVIDER_EVIDENCE

recoverable bytes 順では並べていない（設計上 intentional）。

---

## 11. Recommended P1.11（OPINION）

1. **`entity_verification_safety_eval` 最適化** — rule lookup cache、predicate memoization、batch audit
2. **Cursor snapshot UUID↔workspace** — explicit metadata path が存在する候補のみ loop に載せる（basename fallback 禁止）
3. **Claude ACTIVE** — bounded dual-snapshot 維持、exact handle contract 継続
4. **Backlog-driven opt-in proof** — node_modules / deep DB crawl は opt-in のまま
5. **まだ ACT に進まない**

---

## 11b. P1.11 — Safety Eval Acceleration（2026-08-29, PARTIAL）

- SafetyRuleIndex → averageRulesPerEntity **1.4**
- ProofFeasibility → CursorMetadata attempts **126→0**
- safety_eval **26.1→25.5s**, total **89→87s**
- **211 tests** / False GREEN=0
- 詳細: **`chatgpt_p111_handoff.md`**

---

## 11c. P1.12 — Entity Safety Snapshot（2026-08-29, PARTIAL）

- EntitySafetySnapshot + finalizeSnapshot + evaluateActions
- DerivedData GREEN → **MOVE_TO_TRASH** 推薦整合 **FIXED**
- total **87→82s**, safety_eval **25.5→26.2s**（stretch未達）
- 残ボトルネック: **active_state resolver ~11.3s**
- **218 tests** / False GREEN=0
- 詳細: **`chatgpt_p112_handoff.md`**

---

## 12. One-line status

**P1.12 PARTIAL:** EntitySafetySnapshot 架构完成。total 87→82s。DerivedData→MOVE_TO_TRASH 整合。safety_eval 25.5→26.2s（active_state 11s 残）。218 tests / False GREEN=0。次 P1.13 active batch。ACT 未着手。

---

## 13. ACT / P2.0 フェーズ（2026-08-29）

**P2.0/P2.1/P2.2 実装済み。Executor NOT STARTED。**

First-class actions:

```text
KEEP | MOVE_TO_TRASH | MOVE_TO_ICLOUD | REMOVE_LOCAL_DOWNLOAD | VENDOR_NATIVE_CLEANUP
```

**設計修正:** MOVE_TO_ICLOUD は SOT FALSE 必須ではない（preservation action）。

Case Study #001 action scan（506 entities, 122.5s）:

| recommended | count |
|-------------|------:|
| KEEP | 501 |
| MOVE_TO_ICLOUD | 5 |
| MOVE_TO_TRASH | 0 |

品質課題: git repo → MOVE_TO_ICLOUD 誤候補（**P1.11/P2 fix済**）、GREEN DerivedData → KEEP 乖離（**P1.12 fix済**）。  
ChatGPT 主正本: **`chatgpt_p20_handoff.md`**, **`chatgpt_p112_handoff.md`**

設計正本: **`docs/ACTION_ARCHITECTURE_v0.1.md`**

---

## 14. 関連ファイル

| 用途 | パス |
|------|------|
| PROVE 開発状況 | 本ファイル |
| **P2.0 Mutation Gate** | **`chatgpt_p200_handoff.md`** |
| **P1.13 Runtime Batch + ACT Readiness** | **`chatgpt_p113_handoff.md`** |
| **P1.12 Snapshot + Resolver** | **`chatgpt_p112_handoff.md`** |
| **P1.11 Safety Eval Accel** | **`chatgpt_p111_handoff.md`** |
| **P2.0 Action + 品質レビュー** | **`chatgpt_p20_handoff.md`** |
| ACT / iCloud 設計概要 | `chatgpt_action_architecture_handoff.md` |
| 容量判断用（別物） | `chatgpt_disk_pressure_handoff.md` |
| P1.10 runtime | `p1_10_runtime_comparison.json` |
| Loop KPI | `entity_verification_loop.json` |
| Backlog | `entity_verification_backlog.json` |
| Strategy cost | `verification_strategy_runtime.json` |
| Coverage 分離 | `verification_loop_coverage.json`, `size_measurement_coverage.json` |
| Runtime breakdown | `proof_runtime_breakdown.json` |
| Safety audit | `green_audit_p1_10.json` |
| Proof summary | `proof_enrichment_summary.json` |

---

## 15. 再現コマンド

```bash
cd ~/Workspace/10_進行中/ai-storage-manager
python3 tools/compile_knowledge_base.py
swift test                    # expect 248 tests, 0 failures
swift run storage-intel scan    # read-only, default proof=derived-data
# opt-in: swift run storage-intel scan --proof node-modules
```

---

## 16. ChatGPT への依頼テンプレ

```text
上記 handoff を読んだ上で:

1. P1.10 の設計判断（priority formula / strategy contract / cache）を要約して確認
2. P1.11 で safety_eval 26s をどう削るか、証拠基準を弱めずに提案
3. Cursor backlog のうち「explicit path がある候補」だけを優先する設計案
4. ACT/UI/自動削除に進むべきでない理由を一言で

推測で GREEN を増やす提案は不要。
UNKNOWN + reason を増やす honest 設計を優先。
```
