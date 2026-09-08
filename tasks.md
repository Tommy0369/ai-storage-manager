# AI Storage Manager — tasks

Status: DONE | PARTIAL | BLOCKED | NOT STARTED

| ID | Item | Status | Note |
|----|------|--------|------|
| P0 | Safety Core Foundation | DONE | |
| P0.5 | Knowledge Base integration | DONE | 178 reconstructed canonical. Original Deep Research artifact unavailable. Provenance retained. |
| P1.1 | Unique Byte Accounting & Semantic Decomposition | PARTIAL | unique/exclusive 実装。L3+ は約27%。System Data 203GB の完全分解ではない |
| P1.2 | Deep Semantic Decomposition & Evidence Resolution | PARTIAL | L3+ 43% / L4+ 17%。False GREEN=0 |
| P1.3 | Lifecycle & Provenance Resolution | PARTIAL | Cursor snapshots / Claude VM / iOS Backup detectors。Safety Class は Detector が決めない |
| P1.4 | Evidence Verification & Source-of-Truth Resolution | PARTIAL | SOT/Regen/Active + Cursor/Claude/Cloud/Voice。VERIFIED-only Safety gate。SOT/Regen known ~25.6%。False GREEN=0。Cursor workspace metadata VERIFIED は薄い。Claude active は UNKNOWN。REAL_MAC_VERIFIED=0 |
| P1.5 | Verified Relationship & Regenerability Proof | PARTIAL | Cursor root↔workspace VERIFIED=3（metadata）。VerificationChain + VerifiedRelationshipCoverage。regenerable TRUE / SOT FALSE の実Macは 0（契約は単体で証明）。Claude ACTIVE exact は未達。Case Studyから巨大 walk detector は除外。False GREEN=0。109 tests |
| P1.6 | Targeted Real-Mac Proof Enrichment | PARTIAL | Cursor: basename VERIFIED撤廃→実Mac VERIFIED workspace links=0（明示metadata不足は正直UNKNOWN/INFERRED）。Claude exact ACTIVE VERIFIED=0。DerivedData lightweight: 実Mac regen TRUE VERIFIED=2 / SOT FALSE VERIFIED=2（info.plist）。node_modules は `--proof node-modules` のみ。VerificationChain strict。False GREEN=0。GREEN=2は SafetyRuleEngine（DerivedData証明後）。runtime ~204s（soft 150超過・du）。127 tests |
| P1.7 | Explicit Metadata Proof & Runtime Stabilization | PARTIAL | workspaceStorage VERIFIED=8。snapshot UUID bridge=0。runtime ~166s。141 tests |
| P1.8 | Detector Catalog Profiling & Honest Relationship Modeling | PARTIAL | detector_catalog 87→45s。total 166→142s。ASSOCIATED_WITH_CURSOR_STORE。152 tests |
| P1.9 | Scanner I/O Accounting & Bounded Measurement | PARTIAL | ScanSessionContext + SizeMeasurement quality。scanner 47→17s。total 142→101s（stretch 120達成）。timeout→UNKNOWN（≠0扱い）。measurement coverage修正。163 tests。False GREEN=0 |
| P1.10 | Entity Verification Loop | PARTIAL | VerificationCandidate + bounded EntityVerificationLoop。evidence cache。total 101→89s。loop 40→31s。yield 18.6%。179 tests。False GREEN=0 |
| P1.11 | Safety Eval Acceleration & Proof Backlog Precision | PARTIAL | SafetyRuleIndex（1.4 rules/entity）。SafetyEvalSession。proof feasibility（Cursor 126→0 attempts）。safety_eval 26→25.5s（stretch未達）。total 89→87s。211 tests |
| P1.12 | Entity Safety Snapshot & Resolver Memoization | PARTIAL | EntitySafetySnapshot + finalizeSnapshot + evaluateActions。total 87→81.6s。safety_eval 25.5→26.2s（stretch未達、active_state resolver が主因）。218 tests / 0 failures |
| P1.13 | Runtime Activity Batch Resolution & ACT Readiness | DONE | RuntimeObservationIndex + RuntimeStateBatchResolver + safe defer planner + ActionReadiness。active 11.3s→1.4s。safety_eval 26.2s→11.3s。total 81.6→70.5s。232 tests / 0 failures / False GREEN=0 |
| P2.0 | Mutation Gate & Execution Contract Hardening | DONE | MutationGate + TransactionContract + ActionBindingFingerprint + DryRun + surface audit。read-only。248 tests / actualMutationImplementations=0 |
| P2.0.1 | Real Mutation Candidate Closure & Action Pipeline De-duplication | DONE | ActionDecisionSet canonical。duplicateEvaluations=0。254 tests。P2.1 gate=BLOCKED_BY_REAL_EVIDENCE |
| P2.0.2 | DerivedData Proof Surface Recovery & Root-Cause Closure | DONE | REAL_STATE_CHANGED。DerivedData空。detector正常 |
| P2.0.3 | First Real Mutation Candidate Selection | DONE | FIRST_REAL_MUTATION_GATE。inventory+ranking。NO_SAFE_REAL_MUTATION_CANDIDATE。270 tests |
| P2.0.4 | Controlled Real Candidate Revalidation | DONE | RealCandidateRevalidationAnalyzer。humanSetupExpected=true。Outcome D=TEST_SETUP_INCOMPLETE（DerivedData空）。277 tests |
| P2.0.5 | DerivedData Strict Proof Chain Closure | DONE | StrictProofChainAnalyzer。EXPECTED_AGGREGATION。child SOT/regen VERIFIED。runtime block。283 tests |
| P2.0.6 | Real Read-Only Preflight Closure | DONE | non-fgy×MOVE_TO_TRASH→APPROVAL_REQUIRED。293 tests |
| P2.1 | First Mutating Executor | DONE | FirstMutatingExecutor MOVE_TO_TRASH only。**first mutation executed** 2026-09-02 |
| P2.2 | Post-Mutation Verification Scan Integration | DONE | PostMutationVerifier + registry + scan reconcile。real DerivedData case POST_VERIFIED。312 tests |
| P2.3 | Human Approval & Action Surface | DONE | macOS SwiftUI app + StorageActionCoordinator。MOVE_TO_TRASH UI only。324 tests |
| P3.0 | Storage Intelligence Experience | DONE | Overview + Sunburst map + presentation layer + product sidebar。336 tests。`p3_0_storage_experience.json` |
| P3.0.1 | Dual-Lens / Decision-Lens Storage Explorer | DONE | Physical multi-ring map + Structure/Meaning/Decision lenses + progressive scan UX。**Accounting recovery (2026-09-03):** UNKNOWN≠0 / known-children lower bound / center mapped。**Hardening:** deterministic deep timeout fixture + Partial map UI。356→(+P302) tests。`p3_0_1_storage_explorer.json` + `chatgpt_p301_accounting_fix_handoff.md` |
| P3.0.2 | Storage Change Intelligence | DONE | History snapshot from existing explorer (no second crawler) + DiffEngine + explanation + Overview change panel + detail。App Support history store (retention 30)。`p3_0_2_storage_change.json` / `p3_0_2_history_status.json`。Growth ≠ actionable。MOVE_TO_TRASH only |
| P3.0.3 | Goal-Based Optimization Plan | DONE | Deterministic plan from ActionDecision only。PLAN≠Safety/Approval/Permit/Execution。MOVE_TO_TRASH executor only。no bulk run。`p3_0_3_optimization_plan.json` + `p3_0_3_candidate_funnel.json` |
| P3.0.4 | Time-to-First-Map & Progressive Scan | DONE | Root du no longer blocks first useful map。direct-child-first + coalesce + bounded concurrency。MapReadiness + progressive snapshots。`p3_0_4_scan_performance.json` |
| P3.1 | High-Value Proof Coverage (Ollama + HF) | DONE | Exact vendor proof providers。shared/unique bytes。reverse refs。no GREEN expansion。Ready Now=0。`p3_1_*.json`。409 tests / False GREEN=0 |
| P3.1.1 | Bounded Remote Reacquisition (HF + Ollama) | DONE | Exact revision/manifest remote proof。freshness-bound。Ready Now=0。Verified Future ~5.685 GB (vendor-native ~5.581 GB)。Executor unchanged。421 tests / False GREEN=0。`p3_1_1_*.json` + `chatgpt_p311_remote_reacquisition_handoff.md` |
| P3.2A | Ollama Native Cleanup Executor | DONE | Scoped Ollama MODEL × VENDOR_NATIVE_CLEANUP。direct argv `ollama rm`。HF/raw blob not executable。Fake-runner tests。Real read-only preflight only — **no real ollama rm**。445 tests / False GREEN=0 |
| P3.2A.1 | Ollama Native Interface Resolution & Runtime Proof Closure | DONE | STALE_MODEL_DATA_ONLY → VERIFY_MORE。CLI/API/App 無し。認可未到達。**468 tests** / False GREEN=0 |
| P3.2A.2 | Vendor-Absent Managed Data Recovery Path | DONE | `VENDOR_ABSENT_MANAGED_DATA_REMAINS` → **READY_FOR_OLLAMA_INSTALL_AUTHORIZATION**。raw delete 禁止。install≠cleanup。**481 tests** / False GREEN=0 |
| P3.2A.3 | Restore Ollama Native Management & Post-Install Reverification | DONE | Official app install → native VERIFIED → qwen3 recognized → INACTIVE VERIFIED → Fresh Preflight **APPROVAL_REQUIRED**。**MODEL REMOVAL NOT EXECUTED**。**499 tests** / False GREEN=0 |
| P3.2A.4 | Canonical Action-Safety Alignment at Real Mutation Boundary | DONE | Entity×Action×State 明確化。generic RED≠vendor-native。strictUnknown=0 / USER_APPROVAL only。Plan=APPROVAL_REQUIRED / 2.49GB。**507 tests** / False GREEN=0 |
| P3.2A.5 | Real Ollama Native Removal & PostVerify | DONE | `library/qwen3:4b` 製品経路で削除検証。verifiedRecoveredBytes=2,497,293,931。shell/rawなし。**514 tests** / False GREEN=0 |
| P3.2A.6 | Real Action & Recovery UX Hardening | DONE | Binding≠freshness。PRE_EXECUTION_REJECTED分類。VerifiedActionResult。**528 tests** / False GREEN=0。新削除なし |
| P3.2B | Hugging Face Exact Revision Native Cleanup | DONE | HF SNAPSHOT×VENDOR_NATIVE_CLEANUP IMPLEMENTED。`hf cache rm` revision-only。CLI unresolved → **VERIFY_MORE**。NO real rm / approval / permit。**542 tests** / False GREEN=0 |
| P3.2B.1 | HF CLI Resolution & Install Authorization Boundary | DONE | CLI genuinely absent。HOMEBREW `hf` 公式選定。**READY_FOR_HF_CLI_INSTALL_AUTHORIZATION**。NO install。**555 tests** / 0 |
| P3.2B.1-exec | HF CLI Homebrew install (authorized) | DONE | `/usr/local` brew FAIL → `/opt/homebrew` SUCCESS。`hf` 1.29.0 @ `/opt/homebrew/bin/hf`。cache unchanged。NO real rm |
| P3.2B.2 | Native Architecture Correction & HF Fresh Preflight Closure | DONE | Host-native brew selection。strictUnknown=0 → **READY_FOR_HF_REMOVAL_AUTHORIZATION**。NO real rm / approval / permit。**572 tests** / 0 |
| P3.2B.3 | Real HF Local Revision Removal & PostVerify | DONE | Human auth → product `execute-hf` → **SNAPSHOT_REMOVED_STORAGE_RECOVERED**。verifiedRecoveredBytes=3,083,520,968。Hub intact。NO shell/raw/prune |
| P3.2B.4 | HF Real Action Closure & Recovery UX | DONE | VerifiedActionResult HF・CLI `--confirm` consent・history correlation・plan progress・phantom candidate除去。**NO new mutation / NO redownload** |
| P3.3A | Current Inventory Re-baseline & Cursor Global Storage Intelligence | DONE | 現行ディスク再ランキング。Cursor globalStorage ~14GB 分解。state.vscdb≈10GB bubbleId+agentKv。**NO mutation / NO delete** |
| P3.3B | Cursor Database Growth Root Cause & Retention Semantics | DONE | state.vscdb ~10.4GB = LIVE_USER_AGENT_STATE。freelist微小。NO vendor retention。次=agent-cli。**NO DB mutation** |
| P3.3C | Cursor Agent CLI Version Retention & Native Cleanup Proof | DONE | 13版・現行symlink証明。cleanup-install-versions=current+2。GS適用未証明。次=NATIVE_CLEANUP_CONTRACT。**NO mutation** |
| P3.3C.1 | Vendor Cleanup Contract Gate & Cursor Agent CLI Alignment | DONE | グローバル契約ゲート。Cursor=STORE_MISMATCH。potential=0。次=LEGACY_STORE_REMEDIATION。**NO mutation** |
| P3.3C.2 | Cursor Agent CLI Legacy Store Remediation Proof | DONE | GS=CURRENT_PRIMARY（worker）。LEGACY未証明。remediationなし。potential=0。次=NO_SAFE_CURSOR_AGENT_CLI_ACTION。**NO mutation** |
| P3.3D | Cursor state.vscdb.backup Retention & Recovery Contract Proof | DONE | RECOVERY_SOURCE / KEEP。restore LIVE。unique keys。cleanupなし。potential=0。次=CURSOR_RECOVERY_BACKUP_KEEP。**NO mutation** |
| P3.4A | Current Inventory Re-baseline & Preservation-First Opportunity Selection | DONE | Cursor閉じる。Voice Memos次。preservation-first。sync証明が先。**NO mutation** |
| P3.4B | Voice Memos Preservation Contract & Local Residency Proof | DONE | CloudKit同期あり。local-only eviction契約なし。KEEP。potential=0。次=NO_NATIVE_LOCAL_EVICTION。**NO mutation** |
| P3.5 | Foundation Research Completion Sprint (Chrome + Claude + Graduation) | DONE | MIXED_APP + VM_RUNTIME 代表完了。graduation=COMPLETE / 100%。次=P4.0。**NO mutation** |
| P4.0 | Productization Freeze & Core Experience Integration | DONE | Research freeze。SEE→VERIFY 製品ループ。ナビ簡素化。executor不変。**NO mutation** |
| P4.1 | Consumer UX Polish & Live Visual Validation | DONE | 文言・インスペクタ・スクショ目視。RC blockerなし。次=P5.0。**NO mutation** |
| P5.0 | Release Candidate Gate | DONE | `RC_PASS_LOCAL_BETA_READY`。Release .app+ZIP。ad-hoc署名。公証は MANUAL。**NO mutation**。次=P5.1_SIGN_NOTARIZE_PACKAGE |
| P5.1 | Sign / Notarize / Package | DONE | `EXTERNAL_DISTRIBUTION_READY`。Developer ID署名+Hardened Runtime、公証Accepted、staple、Gatekeeper accepted、ZIP再展開4検証PASS。**NO mutation**。次=P5.2_RELEASE_FREEZE_AND_V0_1 |
| P5.3 | Global Localization Foundation | DONE | 9 locales + L10n catalog + Settings language。Safety不変。**NO mutation**。次=P5.4_LOCALIZATION_RELEASE_QA |
| P5.4 | Localization Release QA | DONE | `LOCALIZATION_RELEASE_READY`。subtype回収・優先スクショ目視・store native polish・814/0。**NO mutation**。次=P5.5_GLOBAL_RELEASE_FREEZE |
| P5.5 | Global Release Freeze | DONE | `GLOBAL_RELEASE_READY`。L10n bundle検証→Developer ID→公証Accepted→staple→spctl→ZIP再展開。**NO mutation**。次=P5.6_V0_1_GLOBAL_RELEASE_FINALIZATION |
| P5.6 | v0.1 Global Release Finalization | DONE | `V0_1_GLOBAL_RELEASE_FROZEN`。成果物不変のまま checksum/trust/L10n/docs 凍結。**NO mutation / NO rebuild / NO re-notarize**。次=人間による配布境界 |
| v0.2 UX FIX 001 | Split Divider / Top Bar Copy / App Menu L10n | DONE | 分割線の所有権を`HSplitView`へ一本化。lensラベル・スキャン状態コピー・ネイティブAppメニューを日本語化。v0.1は凍結のまま不変。**NO mutation / NO commit** |
| v0.2 scope | Ship as v0.2 (not v0.1.1) | DONE | 設定空白修正・英語回収・ContentView削除を含む一式を **v0.2** で出す |
| v0.2 settings blank | Settings pane layout | DONE | Form崩壊→ScrollView。`ASM_START_SECTION=settings` |
| v0.2 English recovery | Remaining UI hardcodes → L10n | DONE | catalog 283×9。UIリテラルgrepクリーン。**844/0** |
| v0.2 ContentView | Unused shell removed | DONE | 削除。`CandidateRow`/`RecentActionRow` を Lists へ抽出 |
| v0.2 packaging | version bump + dist-0.2 sign/notarize | DONE | **0.2.0 / 51** · `V0_2_EXTERNAL_DISTRIBUTION_READY` · ZIP SHA `a5eb688a…` · notary `9698df53-…` · `dist/` 未改変 |

## V0.2 — Product line (after freeze)

**Status: `V0_2_EXTERNAL_DISTRIBUTION_READY`** (2026-09-08)

| Subtask | Status |
|---------|--------|
| scope decision | DONE — ship as v0.2 |
| UX FIX 001 | DONE |
| settings blank | DONE |
| English recovery | DONE |
| ContentView removal | DONE |
| version 0.2.0 / build 51 | DONE |
| package `dist-0.2` | DONE |
| Developer ID + notarize + staple | DONE — Accepted |
| Gatekeeper | DONE — accepted |
| ZIP re-extract | DONE |
| docs (README/INSTALL/RELEASE_NOTES) | DONE |
| v0.1 freeze intact | DONE |

Artifact: `dist-0.2/AIStorageManager-0.2.0-rc51-arm64.zip`  
SHA-256: `a5eb688a77084555af880f7c9bd2be54ff8d1fd4954efc7fb3d530be667c89b1`

次: 公開ホスティング / commit・tag は人間判断。

## P5.6 — v0.1 Global Release Finalization

**Status: `V0_1_GLOBAL_RELEASE_FROZEN`** (2026-09-08)

| Subtask | Status |
|---------|--------|
| P5.5 evidence confirmation | DONE — GLOBAL_RELEASE_READY |
| release identity freeze | DONE — 0.1.0 / 50 / arm64 / 9 locales |
| checksum confirmation | DONE — SHA-256 match |
| ZIP byte confirmation | DONE — 5,551,800 |
| codesign reconfirm | DONE — strict PASS |
| staple reconfirm | DONE — validate PASS |
| Gatekeeper reconfirm | DONE — accepted / Notarized Developer ID |
| localization resource reconfirm | DONE — 9/9 |
| ZIP re-extraction | DONE — trust + L10n PASS |
| priority locale spot check | DONE — en / ja / zh-Hans / de |
| release fingerprint | DONE — `p5_6_release_fingerprint.json` |
| final manifest | DONE — `dist/release-manifest.json` frozen |
| release evidence archive | DONE — `reports/release/v0.1.0/` |
| README audit | DONE |
| INSTALL audit | DONE |
| SAFETY audit | DONE |
| PRIVACY audit | DONE |
| Known Limitations audit | DONE |
| Release Notes freeze | DONE |
| store metadata freeze | DONE — 9 locales |
| claim audit | DONE — unsupported=0 |
| final regression | DONE — **819 / 0** |
| safety freeze | DONE |
| localization freeze | DONE |
| release status | DONE — V0_1_GLOBAL_RELEASE_FROZEN |

## P5.5 — Global Release Freeze

**Status: `GLOBAL_RELEASE_READY`** (2026-09-08)

| Subtask | Status |
|---------|--------|
| baseline regression | DONE — 814/0 |
| P5.4 freeze | DONE |
| localization package regression | DONE — validate-localization-bundle.sh |
| actual app resource validation | DONE |
| 9-locale packaged audit | DONE |
| real app localization smoke | DONE |
| bundle cleanup | DONE — strip knowledge/reports+source |
| bundle freeze | DONE — pre-sign; no post-sign patch |
| Developer ID discovery | DONE |
| notary profile verification | DONE |
| Developer ID signing | DONE |
| hardened runtime | DONE |
| codesign | DONE — strict PASS |
| entitlements | DONE — empty/minimal |
| signed localization smoke | DONE |
| fresh notarization | DONE — 2775478b-4a61-4338-8938-db5bc90b6e40 |
| Accepted | DONE |
| staple | DONE |
| staple validate | DONE |
| spctl | DONE — Notarized Developer ID |
| final global ZIP | DONE |
| ZIP re-extraction | DONE |
| extracted localization validation | DONE |
| SHA-256 | DONE — 3f9983dbcc705e99cf252ab6e1750ae854b7881271d3a23b452ec2a0ef2e2819 |
| release manifest | DONE |
| localization freeze | DONE |
| metadata freeze | DONE |
| claim audit | DONE |
| reports | DONE — p5_5_*.json + 総合レポート |
| final regression | DONE — **819 / 0** |
| global release decision | DONE — GLOBAL_RELEASE_READY |

## P5.4 — Localization Release QA

**Status: `LOCALIZATION_RELEASE_READY`** (2026-09-08)

| Subtask | Status |
|---------|--------|
| baseline regression | DONE — 797/0 before |
| leftover string audit | DONE |
| subtype localization | DONE |
| 100% coverage | DONE — 222 keys × 9 |
| en screenshot matrix | DONE — 15 |
| ja screenshot matrix | DONE — 15 |
| zh-Hans screenshot matrix | DONE — 15 |
| de screenshot matrix | DONE — 15 |
| screenshot visual review | DONE |
| zh-Hant smoke | DONE |
| ko smoke | DONE |
| es smoke | DONE |
| fr smoke | DONE |
| pt-BR smoke | DONE |
| language switching | DONE |
| restart persistence | DONE — LanguageStore defaults injection |
| Safety semantic QA | DONE — drift=0 |
| cloud/delete QA | DONE |
| Trash QA | DONE |
| representative entity QA | DONE |
| number QA | DONE |
| byte QA | DONE |
| date QA | DONE |
| plural QA | DONE |
| accessibility QA | DONE |
| store metadata native polish | DONE — 9 locales |
| claim audit | DONE — unsupported=0 |
| Release bundle resource QA | DONE |
| offline QA | DONE |
| performance | DONE — no material first-map regression |
| locale invariant matrix | DONE — diffs=0 |
| reports | DONE — p5_4_*.json + 総合レポート |
| final regression | DONE — **814 / 0** |
| release decision | DONE — LOCALIZATION_RELEASE_READY |

## P5.3 — Global Localization Foundation

| Subtask | Status |
|---------|--------|
| string inventory | DONE |
| String Catalog / JSON catalog | DONE |
| semantic localization keys | DONE |
| AppLanguage + SYSTEM default | DONE |
| in-app language setting | DONE |
| presentation resolver / L10n | DONE |
| Safety copy glossary | DONE |
| 9 locales | DONE |
| number/byte/date formatting | DONE |
| pluralization placeholder | DONE |
| accessibility keys | DONE |
| permission/error/scan copy | DONE |
| representative entity copy | DONE (core) |
| all-locale smoke (tests) | DONE |
| priority screenshot QA | PARTIAL — deferred visual matrix to P5.4 |
| locale invariants | DONE — differences=0 |
| docs + reports | DONE |
| final regression | DONE — **797 / 0** |

## v0.2 UX FIX 001 — Split Divider + Top Bar Copy + App Menu L10n

**基準: v0.1 は `V0_1_GLOBAL_RELEASE_FROZEN` のまま不変**（ZIP SHA-256 / bundle fingerprint 変化なし）

| Subtask | Status |
|---------|--------|
| v0.2 開発用出力の分離 (`dist-dev/`) | DONE — `scripts/package-dev-app.sh` 新設 |
| 凍結ガード | DONE — `dist/` への再ビルドを構造的に拒否 |
| 分割線バグの再現 | DONE — AX計測＋ピクセル計測で確定 |
| 分割線の根本原因 | DONE — `mapSplit` が装飾`Divider()`＋固定320pt幅で境界を二重所有 |
| 分割線の修正 | DONE — `HSplitView` で境界の所有者を1つに |
| フルスクリーン ドラッグ検証 | DONE — 可視線2本＝splitter2本、各線がsplitter上 |
| ゴースト線 | DONE — 0本 |
| lensラベル（日本語） | DONE — どこにある？／これは何？／どうする？ |
| lensラベル（英語） | DONE — Where? / What is it? / What can I do? |
| lens内部識別子 | 不変 — STRUCTURE / MEANING / DECISION |
| トップバー英語混入 | DONE — `story.largestFolder` / `map.inThisFolder` を9ロケール化 |
| スキャン状態の正規化 | DONE — `StorageScanStatus` に一本化 |
| 「失敗」と「スキャン中」の同時表示 | DONE — 解消 |
| ネイティブAppメニュー（日本語） | DONE — バンドルに `ja.lproj` 同梱 + `AppleLanguages` 同期 |
| ネイティブAppメニュー（英語/その他） | DONE — 日本語以外は英語。日英の混在なし |
| メニューのaction/ショートカット | 不変 — selector一致で特定、titleのみ変更 |
| 9ロケールUI | 不変 — カバレッジ100%維持 |
| 回帰テスト | DONE — 843/0（819+新規24） |
| Safety / ActionDecision | 不変 |
| 実 storage mutation | 0 |
| 既存不具合の発見 | 設定画面が空白（凍結v0.1でも再現。今回の範囲外） |

## P5.1 — Sign / Notarize / Package

**Status: `EXTERNAL_DISTRIBUTION_READY`** (2026-09-08)

| Subtask | Status |
|---------|--------|
| CSR 生成（秘密鍵はローカル保持） | DONE — RSA 2048 / SHA-256 |
| Developer ID 証明書発行 | DONE — Apple発行を検証のうえ導入 |
| 秘密鍵ペアリング検証 | DONE — SPKI ハッシュ一致 |
| 中間CA (Developer ID CA G2) | DONE — Xcode同梱を導入（`errSecInternalComponent` の原因） |
| Developer ID discovery | DONE — `Developer ID Application: Katsuhiro Tomita (2MK7L9N4N7)` |
| notarization credential | DONE — keychain profile `AIStorageManagerNotary` |
| clean Release build | DONE — 0.1.0 / build 50 / arm64 |
| nested code audit | DONE — nested code 0件、inside-out不要 |
| pre-sign bundle audit | DONE — fixture/reports/.git/秘密情報なし |
| Developer ID signing | DONE — `--options runtime --timestamp` |
| hardened runtime | DONE — `flags=0x10000(runtime)` |
| codesign verify | DONE — `--verify --strict` PASS |
| entitlements verify | DONE — 空（inflation なし） |
| signed launch smoke | DONE — 起動・生存・クリーン終了 |
| notarization ZIP | DONE — `ditto -c -k --keepParent` |
| notarytool submission | DONE — `6af1017a-bc67-425d-badc-59c20c95c30f` |
| notarization result | DONE — **Accepted** |
| staple / validate | DONE — 両方 PASS |
| spctl | DONE — **accepted** / `source=Notarized Developer ID` |
| final ZIP (external) | DONE — staple済みappから生成 |
| re-extraction validation | DONE — codesign / staple / spctl / launch すべて PASS |
| quarantine 付与での spctl | DONE — accepted（実ダウンロード相当） |
| SHA-256 | DONE — `436757806cec2c589f3e99de7ae0dd5a3dc2688ac76ccbb74acb7f0fb9b746bd` |
| release manifest | DONE — `dist/release-manifest.json` |
| docs/claim update | DONE — README / INSTALL / RELEASE_NOTES を実態に更新 |
| reports | DONE — `p5_1_*.json` + 総合レポート |
| final regression | DONE — **780 / 0** |
| real storage mutation | 0 — 発生なし |
| next-phase decision | P5.2_RELEASE_FREEZE_AND_V0_1 |

## P5.0 — Release Candidate Gate

| Subtask | Status |
|---------|--------|
| baseline regression | DONE — 769/0 before |
| release configuration | DONE — DEBUG vs RELEASE (fixture DEBUG-only preview) |
| version identity | DONE — 0.1.0 / build 50 / `com.tomystudio.aistoragemanager` |
| release build | DONE |
| bundle audit | DONE — no reports/fixtures shipped |
| architecture | DONE — arm64 only (honest) |
| minimum macOS | DONE — 13.0 |
| signing | DONE — ad-hoc; Developer ID absent |
| hardened runtime | MANUAL_REQUIRED — with Developer ID |
| entitlements | DONE — empty (no inflation) |
| notarization readiness | MANUAL_REQUIRED — credentials |
| permission audit | DONE — FDA optional |
| first launch | DONE |
| fresh state | DONE |
| restart | DONE |
| interruption | DONE — no auto-retry |
| history/schema | DONE — atomic + schemaVersion |
| settings | DONE — no Safety bypass toggles |
| filesystem edge cases | DONE — failure matrix |
| offline | DONE |
| vendor absence | DONE |
| action-flow release regression | DONE — fixture/historical |
| preflight / permit / postverify | DONE |
| privacy / secret / network audit | DONE |
| performance | DONE — no material blocker |
| documentation | DONE — README + docs/* + RELEASE_NOTES |
| packaging | DONE — APP+ZIP |
| Gatekeeper assessment | DONE — rejected until notarized |
| release gate | DONE — `p5_0_release_candidate_gate.json` |
| Japanese report | DONE — `p5_0_総合レポート.md` |
| full regression | DONE — **780 / 0** |

## P4.1 — Consumer UX Polish & Live Visual Validation

| Subtask | Status |
|---------|--------|
| live launch | DONE — read-only disk + screenshot export |
| overview polish | DONE — verified recovered hint |
| Sunburst polish | DONE — Keep/Protected chrome |
| lens polish | DONE — Structure/Meaning/Decision |
| inspector hierarchy | DONE — product order |
| copy rewrite | DONE — `ConsumerPresentationCopy` |
| protected UX | DONE — positive Keep language |
| plan polish | DONE — Goal/Verified/Remaining; Ready=0 soft |
| history polish | DONE — screenshot |
| action review polish | DONE — fixture |
| verification receipt polish | DONE — HF + Trash pending |
| macOS-native interaction | DONE |
| responsive layouts | DONE — existing split |
| accessibility baseline | DONE — labels / non-color icons |
| async correctness | DONE — binding regression |
| performance | DONE — no first-map regression |
| live screenshots | DONE — 7 |
| fixture screenshots | DONE — 4 |
| visual self-review | DONE |
| reports | DONE — `p4_1_*.json` + 総合レポート |
| full regression | DONE — **769 / 0** |
| release readiness decision | DONE — P5.0_RELEASE_CANDIDATE_GATE |

## P4.0 — Productization Freeze & Core Experience Integration

| Subtask | Status |
|---------|--------|
| research freeze | DONE — `FoundationResearchFreeze` |
| application shell | DONE — Storage / Plan / History / Settings |
| storage overview | DONE — Sunburst hero + disk capacity + verified recovered |
| Sunburst refinement | DONE — existing multi-ring + lenses |
| Structure lens | DONE |
| Meaning lens | DONE |
| Decision lens | DONE |
| presentation resolver | DONE — Cursor/Voice/Chrome/Claude titles |
| entity inspector | DONE — What / Why / Do I need it / Why can't I |
| why-large explanation | DONE |
| why-keep explanation | DONE |
| action block explanation | DONE |
| goal plan UX | DONE — Plan nav |
| history UX | DONE — History nav |
| action review | DONE — CandidateDetail + Approval |
| fresh-preflight UX | DONE |
| approval surface | DONE |
| execution state machine | DONE — `ProductActionFlowPhase` |
| verification receipt | DONE — ExecutionResultView |
| protected/actionable presentation | DONE |
| async state hardening | DONE — `PresentationSelectionBinding` |
| performance | DONE — report (no first-map regression introduced) |
| accessibility | DONE — labels retained / contrast via system styles |
| debug UI separation | DONE — Settings gated |
| reports | DONE — `p4_0_*.json` |
| screenshots | DONE — fixture `p40_*` |
| full regression | DONE — **760 / 0** |

## P3.5 — Foundation Research Completion Sprint

| Subtask | Status |
|---------|--------|
| Chrome fresh inventory | DONE — App Support + Library/Caches |
| Chrome mixed-state semantic decomposition | DONE — site state ≠ cache |
| Chrome runtime proof | DONE — Chrome running |
| Chrome vendor clear-data contract | DONE — blast-radius model; not ALIGNED for action |
| Chrome blast-radius model | DONE |
| Claude fresh inventory | DONE — ~12.6GB App Support |
| Claude VM/runtime decomposition | DONE — rootfs base / sessiondata overlay |
| Claude runtime proof | DONE — Claude + Virtualization active → KEEP |
| Claude base/mutable/snapshot separation | DONE |
| Claude vendor lifecycle semantics | DONE — reset destructive until proven |
| representative family coverage matrix | DONE — 8/8 mandatory |
| Safety primitive audit | DONE — 24/24 no architectural gap |
| Action family audit | DONE — semantics ready; executors unchanged |
| ResearchGraduationGate | DONE — COMPLETE 100% |
| research completion report | DONE — `p3_5_*.json` |
| performance | DONE |
| screenshots | DONE — fixture `p35_*` |
| full regression | DONE — **747 / 0** |
| P4 recommendation | DONE — PRODUCTIZATION_FREEZE_AND_UX_INTEGRATION |

## P3.4B — Voice Memos Preservation Contract & Local Residency Proof

| Subtask | Status |
|---------|--------|
| fresh Voice Memos storage accounting | DONE — ~14.09GB unique |
| recording-media classification | DONE — ~14.02GB media |
| privacy guard | DONE — no audio/titles |
| iCloud setting evidence | DONE — ENABLED_INFERRED |
| sync architecture | DONE — CloudKit Core Data mirroring |
| recording-level remote identity | DONE — NOT available |
| remote currentness | DONE — 0 verified bytes |
| local residency model | DONE — RESIDENT |
| vendor delete semantics | DONE — propagates |
| bounded app implementation search | DONE — app/daemon/loctable |
| native local-eviction discovery | DONE — NONE_PROVEN |
| FileProvider/CloudKit distinction | DONE — CloudKit; not FP |
| deletion-propagation proof | DONE — DELETE=SYNC_PROPAGATES |
| reacquisition proof | DONE — UNKNOWN / not for eviction |
| PreservationContract | DONE — not found / not ready |
| candidate-byte calculation | DONE — 0 |
| plan integration | DONE — PROTECTED |
| UX | DONE — fixture `voice_memos_p34b_*` |
| reports | DONE — `p3_4b_*.json` |
| performance | DONE |
| tests | DONE — P34B suite |
| next-centerpin decision | DONE — `VOICE_MEMOS_NO_NATIVE_LOCAL_EVICTION` |
| final full regression | DONE — **729 / 0** |

## P3.4A — Current Inventory Re-baseline & Preservation-First Opportunity Selection

| Subtask | Status |
|---------|--------|
| Cursor closure | DONE — DB/agent-cli/backup KEEP; actionable=0 |
| bounded semantic search principle | DONE — `BoundedSemanticInspection` |
| fresh disk inventory | DONE — path measurements + ranking |
| post-recovery ranking | DONE — preservation-first scores |
| preservation opportunity model | DONE — `PreservationOpportunity` / `PreservationContract` |
| next-target scoring | DONE — Voice Memos wins next proof |
| conditional Voice Memos intelligence | DONE — ~14GB decomposed; no audio |
| cloud/source-of-truth proof | DONE — CloudKit PARTIAL; remote UNKNOWN |
| local-vs-remote action distinction | DONE — DELETE≠EVICT≠SYNC |
| plan refresh | DONE — potential=0; recovered 5.58GB tracked |
| UX | DONE — fixture `storage_p34a_*` / `voice_memos_p34a_*` |
| reports | DONE — `p3_4a_*.json` |
| performance | DONE |
| tests | DONE — P34A suite |
| next-centerpin selection | DONE — `VOICE_MEMOS_SYNC_SEMANTICS_PROOF` |
| final full regression | DONE — **716 / 0** |

## P3.3D — Cursor state.vscdb.backup Retention & Recovery Contract Proof

| Subtask | Status |
|---------|--------|
| fresh backup identity | DONE — 1,278,717,952 bytes SQLite |
| file type | DONE — RECOVERY_BACKUP |
| source relationship | DONE — partial older snapshot of state.vscdb |
| privacy-safe structural comparison | DONE — key-class aggregates only |
| unique recovery-state analysis | DONE — backup-only keys present |
| creation trace | DONE — close-time copy(path, path.backup) |
| restore trace | DONE — open failure rename backup→main |
| migration role | DONE — NOT_SPECIFIC |
| rollback role | DONE — implicit last-good snapshot |
| runtime proof | DONE — main open; backup closed |
| retention semantics | DONE — single generation overwrite; no delete |
| cleanup/remediation contract | DONE — NONE |
| potential-byte calculation | DONE — 0 |
| plan | DONE — KEEP |
| UX | DONE — fixture `cursor_p33d_*.png` |
| reports | DONE — `p3_3d_*.json` |
| performance | DONE |
| tests | DONE — P33D suite |
| next-centerpin decision | DONE — `CURSOR_RECOVERY_BACKUP_KEEP` |
| final full regression | DONE — **704 / 0** |

## P3.3C.2 — Cursor Agent CLI Legacy Store Remediation Proof

| Subtask | Status |
|---------|--------|
| dual-store inventory | DONE — HOME + GS separate |
| HOME lifecycle | DONE — CURRENT_PRIMARY / install-core |
| GS lifecycle | DONE — CURRENT_PRIMARY / worker |
| version-set comparison | DONE — 1 overlap SAME_LABEL_DIFFERENT_ARTIFACT; 12 GS-only |
| artifact identity | DONE — bounded; no full 2.68GB hash |
| selection graph | DONE — GS→2026.08.31; HOME→2026.08.11 |
| runtime graph | DONE — COMPLETE_ENOUGH; none on either store |
| fallback graph | DONE — HOME keep+2; GS UNKNOWN |
| migration trace | DONE — none found |
| legacy-store proof | DONE — LEGACY_STORE_VERIFIED=false |
| unreferenced proof | DONE — unreferencedVerifiedBytes=0 (cache path) |
| user-state exclusion | DONE — no userish in GS |
| exact reacquisition | DONE — historical UNKNOWN; local not exact dup |
| remediation contract | DONE — NONE / not READY |
| potential-byte calculation | DONE — potential=0 |
| plan integration | DONE — KEEP / VERIFY insight |
| UX | DONE — fixture `cursor_p33c2_*.png` |
| reports | DONE — `p3_3c_2_*.json` |
| performance | DONE |
| tests | DONE — P33C2 suite |
| next-centerpin selection | DONE — `NO_SAFE_CURSOR_AGENT_CLI_ACTION` |
| final full regression | DONE — **692 / 0** |

## P3.3C.1 — Vendor Cleanup Contract Gate & Cursor Agent CLI Alignment

| Subtask | Status |
|---------|--------|
| global vendor cleanup principle | DONE — `NO_VENDOR_CLEANUP_ACTION_WITHOUT_ALIGNED_CONTRACT` |
| generic contract model | DONE — `VendorCleanupContractSpec` |
| generic alignment gate | DONE — `VendorCleanupContractGate.evaluate` |
| storage-class matching | DONE |
| exact target matching | DONE |
| blast-radius model | DONE |
| Cursor actual store refresh | DONE — GS ~2.68GB |
| Cursor cleanup call trace | DONE — HOME LIVE |
| path resolution | DONE — SIBLING_STORE |
| call reachability | DONE — LIVE (HOME) |
| version selector | DONE — stale-set keep+2 |
| current/active/fallback exclusions | DONE |
| version coverage | DONE — GS all NOT_COVERED |
| potential byte correction | DONE — 0 |
| Ollama regression | DONE — fixture ALIGNED |
| HF regression | DONE — fixture ALIGNED + last-revision nuance |
| UX | DONE — gate screenshots |
| reports | DONE — principle / alignment / regression |
| performance | DONE |
| tests | DONE — P33C1 path + gate suites |
| next-phase decision | DONE — `CURSOR_AGENT_CLI_LEGACY_STORE_REMEDIATION` |
| final full regression | DONE — **676 / 0** |

## P3.3C — Cursor Agent CLI Version Retention & Native Cleanup Proof

| Subtask | Status |
|---------|--------|
| fresh agent-cli root verification | DONE — GS worker store ~2.68GB |
| version inventory | DONE — 13 versions |
| unique-byte reconciliation | DONE — hardlink shared=0 |
| current version proof | DONE — symlink → 2026.08.31-4057e58 |
| runtime mapping | DONE — PARTIAL; agent not running |
| fallback/rollback proof | DONE — vendor keep +2 inferred |
| installed Cursor implementation tracing | DONE — worker + install-core-posix |
| retention semantics | DONE — current + 2 non-current |
| cleanup semantics | DONE — hidden CLI; HOME default |
| artifact source/reacquisition | DONE — latest channel only; old UNKNOWN |
| architecture metadata | DONE — arm64 node |
| user-original protection | DONE — no userish dirs; package @anysphere/agent-cli-runtime |
| history/change analysis | DONE — dual store noted |
| opportunity ranking | DONE — ~1.98GB if GS contract applies |
| UX | DONE — fixture `cursor_p33c_*.png` |
| performance | DONE |
| reports | DONE — `p3_3c_*.json` |
| tests | DONE — P33C suite |
| next centerpin | DONE — `CURSOR_AGENT_CLI_NATIVE_CLEANUP_CONTRACT` |
| final full regression | DONE — **644 / 0** |

## P3.3B — Cursor Database Growth Root Cause & Retention Semantics

| Subtask | Status |
|---------|--------|
| safe live DB inspection contract | DONE — RO URI + query_only; VACUUM deny ≠ auto_vacuum |
| SQLite physical accounting | DONE — page/freelist/WAL/SHM |
| freelist/WAL accounting | DONE — freelist ~3.7MB; WAL ~186MB (not SIGNIFICANT) |
| cursorDiskKV class statistics | DONE — bubbleId/agentKv/checkpointId + composer |
| privacy guard | DONE — sizes/counts only |
| installed Cursor implementation tracing | DONE — storageSizeScan / conversationSearch |
| writer/read/delete lifecycle | DONE — read VERIFIED; delete path NONE for cursorDiskKV |
| retention discovery | DONE — NO_VENDOR_RETENTION_PROOF_FOUND |
| sync/reacquisition analysis | DONE — UNKNOWN for KV; reinstall ≠ restore |
| backup semantics | DONE — older/smaller snapshot; lifecycle UNKNOWN |
| history growth decomposition | DONE — comparable history INSUFFICIENT |
| logical vs physical growth | DONE — LOGICAL_KV_PAYLOAD dominant |
| agent-cli secondary inventory | DONE — 13 versions; inactive ~2.45GB |
| UX | DONE — fixture `cursor_p33b_*.png` |
| opportunity ranking | DONE — agent-cli #1 |
| next-phase selection | DONE — AGENT_CLI_VERSION_CLEANUP_PROOF |
| performance | DONE — `p3_3b_performance.json` |
| reports | DONE — `p3_3b_*.json` |
| tests | DONE — P33BCursorDatabaseGrowthTests |
| final full regression | DONE — **629 / 0** |

## P3.3A — Current Inventory Re-baseline & Cursor Global Storage Intelligence

| Subtask | Status |
|---------|--------|
| fresh current inventory | DONE |
| post-removal ranking | DONE — Cursor still #1 |
| Cursor root verification | DONE — `ai.cursor.global_storage` |
| component decomposition | DONE |
| unique-byte reconciliation | DONE |
| privacy-safe DB classification | DONE — key-class only |
| extension ownership mapping | DONE — exact match |
| extension-absent state | DONE |
| runtime relationships | DONE — batched lsof |
| source-of-truth classification | DONE |
| reacquisition/regeneration analysis | DONE |
| change/growth intelligence | DONE — coarse root |
| preservation opportunity analysis | DONE |
| future native action candidate analysis | DONE — agent-cli versions |
| UX | DONE — fixture screenshots |
| reports | DONE — `p3_3a_*.json` |
| performance | DONE |
| tests | DONE — P33A suite |
| next-phase decision | DONE — `CURSOR_DATABASE_GROWTH_ROOT_CAUSE` |
| final full regression | DONE — **616 / 0** |

## P3.2B.4 — HF Real Action Closure, Consent Provenance, Recovery UX & History Hardening

| Subtask | Status |
|---------|--------|
| post-B3 full regression | DONE — **572 / 0** (`fullSuiteBeforeB4`) |
| current inventory refresh | DONE — HF/qwen3 ABSENT; no phantom candidates |
| phantom candidate removal | DONE — remote≠local candidate policy |
| VerifiedActionResult HF integration | DONE |
| recovery receipt | DONE — `p3_2b_4_verified_action_receipt.json` |
| vendor/verified/disk delta separation | DONE — 3.1G / 3,083,520,968 / +3,083,640,832 |
| dry-run vs actual comparison | DONE — logicalConsequenceMatched=true |
| completed plan progress | DONE — verified total 5,580,814,899 |
| history event | DONE — entity disappearance safe |
| entity-disappearance correlation | DONE — timestamp-only blocked |
| CLI `--confirm` consent audit | DONE — ack only; not bypass |
| approval provenance | DONE — CLI_EXPLICIT_HUMAN_CONFIRMATION |
| permit bypass tests | DONE — P32B4 suite |
| unknown outcome UX | DONE — Re-check / no Try again |
| remaining inventory ranking | DONE — cached history (no second crawler) |
| performance | DONE — `p3_2b_4_performance.json` |
| reports | DONE — `p3_2b_4_*.json` |
| screenshots | DONE — fixture-labeled `hf_p32b4_*.png` |
| final full regression | DONE — **597 / 0** (`fullSuiteAfterB4`) |

## P3.2B.3 — Real HF Local Revision Removal & PostVerify

| Subtask | Status |
|---------|--------|
| human authorization (exact revision, local only) | DONE |
| Fresh Preflight final | DONE → APPROVAL_REQUIRED |
| UserActionApproval + ExecutionPermit | DONE (single-use consumed) |
| product executor `hf cache rm --yes` | DONE |
| postverify snapshot/repo absent | DONE |
| verifiedRecoveredBytes | DONE — 3,083,520,968 |
| Hub remote intact | DONE — HTTP 200 |
| Hub/prune/raw/other not executed | DONE |
| reports | DONE — `p3_2b_3_*.json` |
| human-boundary | CLOSED |

## P3.2B.2 — Native Architecture Correction & HF Fresh Preflight Closure

| Subtask | Status |
|---------|--------|
| multi-brew architecture detection | DONE |
| host-native package manager selection | DONE |
| actual HF binary binding | DONE — `/opt/homebrew/bin/hf` |
| failed Intel brew audit | DONE — read-only; cleanup=false |
| HF CLI contract | DONE |
| fresh inventory | DONE — revCount=1 |
| vendor verify | DONE — OK |
| vendor dry-run structural capture | DONE — 3.1G sole revision |
| dry-run no-mutation assertion | DONE |
| blast-radius binding | DONE — repo dir removal expected |
| reference graph refresh | DONE |
| runtime product proof | DONE — COMPLETE / INACTIVE_VERIFIED |
| remote proof refresh | DONE — REACQUIRABLE_VERIFIED FRESH |
| Fresh Preflight | DONE → APPROVAL_REQUIRED |
| plan alignment | DONE — HF APPROVAL_REQUIRED ~3.08GB |
| reports | DONE — `p3_2b_2_*.json` |
| tests | DONE **572 / 0** |
| human-boundary stop | DONE — USER_APPROVAL only; NO approval created |

## P3.2B.1-exec — HF CLI install

| Subtask | Status |
|---------|--------|
| human auth (install only) | DONE |
| brew install via /usr/local | FAILED (Intel path / openssl build) |
| brew install via /opt/homebrew | DONE — hf 1.29.0 |
| CLI contract proof | DONE |
| read-only dry-run | DONE — 3.1G sole revision |
| cache unchanged assert | DONE |
| cleanup auth | NOT CREATED |
| real cache rm | NOT EXECUTED |

## P3.2B.1 — HF CLI Resolution & Install Authorization Boundary

| Subtask | Status |
|---------|--------|
| existing CLI rediscovery | DONE — absent |
| Homebrew metadata | DONE — present, formula hf 1.29.0 not installed |
| uv / pipx / python hub | DONE — absent |
| install method selection | DONE — HOMEBREW |
| SoftwareInstallationProposal | DONE |
| curl\|bash policy reject | DONE |
| install≠cleanup separation | DONE |
| resolver trusted paths | DONE (uv tool + brew prefix) |
| reports | DONE |
| full regression | DONE **555 / 0** |
| human install boundary stop | DONE |

## P3.2B — Hugging Face Exact Revision Native Cleanup

| Subtask | Status |
|---------|--------|
| current HF inventory confirmation | DONE |
| HF CLI resolution | DONE (UNRESOLVED on this Mac) |
| CLI contract proof | DONE (probes defined; live absent) |
| revision-only capability scoping | DONE |
| cache root binding | DONE |
| dry-run preview | DONE (incomplete without CLI) |
| preview/semantic graph reconciliation | DONE |
| active-use proof | DONE (lsof empty; product VERIFY_MORE) |
| strict predicates | DONE |
| Fresh Preflight | DONE → VERIFY_MORE |
| executor | DONE |
| postverify | DONE (design + tests) |
| permit binding | DONE |
| plan integration | DONE |
| UX | PARTIAL (copy rules; no live ready UI) |
| reports | DONE |
| screenshots | DONE (fixtures) |
| full regressions | DONE **542 / 0** |
| real read-only validation | DONE |
| human-boundary stop | DONE (not reached) |

## P3.2A.6 — Real Action & Recovery UX Hardening

| Subtask | Status |
|---------|--------|
| full post-P3.2A.5 suite | DONE |
| semantic binding stability | DONE |
| freshness separation | DONE |
| approval lifecycle | DONE |
| execution-attempt lifecycle | DONE |
| retry/reconciliation semantics | DONE |
| verified action result model | DONE |
| recovery receipt UX | DONE |
| potential vs verified recovery | DONE |
| disk delta separation | DONE |
| plan refresh | DONE |
| completed-action history | DONE |
| change-intelligence correlation | DONE |
| current inventory refresh | DONE |
| performance | DONE (no crawl) |
| reports | DONE |
| screenshots | DONE (fixtures) |
| full final regression | DONE **528 / 0** |

**Stop:** Do not auto-start P3.2B.

## P3.2A.5 — Real Ollama Native Removal & PostVerify

| Subtask | Status |
|---------|--------|
| exact approval receipt | DONE |
| fresh final preflight | DONE |
| permit issuance | DONE |
| real product-path executor invocation | DONE |
| native model removal | DONE |
| postverify | DONE |
| recovery verification | DONE (MODEL_REMOVED_STORAGE_RECOVERED) |
| history/action correlation | DONE |
| plan refresh | DONE (post-scan) |
| reports | DONE |
| safety regression | DONE |
| human-boundary audit | DONE |

**Stop:** Do not auto-start next mutation. Recommend P3.2A.6 UX/recovery hardening.

## P3.2A.4 — Canonical Action-Safety Alignment

| Subtask | Status |
|---------|--------|
| action-specific Safety trace | DONE |
| generic/entity vs action decision separation | DONE |
| vendor-native strict predicate catalog | DONE |
| UNKNOWN gate closure | DONE |
| reacquirable/regenerable separation | DONE |
| remote predicate deduplication | DONE |
| MutationGate exact decision binding | DONE |
| ExecutionPermit defense-in-depth | DONE |
| Plan/preflight alignment | DONE |
| read-only live recheck | DONE |
| reports | DONE |
| tests | DONE |

**Stop:** USER_APPROVAL only — do not create approval/permit; do not `ollama rm`.

## P3.2A.3 — Restore Ollama Native Management & Post-Install Reverification

| Subtask | Status |
|---------|--------|
| install authorization scope | DONE |
| trusted install source | DONE (official Ollama-darwin.zip) |
| pre-install receipt | DONE |
| official Ollama restore | DONE |
| post-install app/CLI proof | DONE |
| model recognition | DONE (`ollama list`) |
| manifest rebuild | DONE |
| reference graph rebuild | DONE |
| runtime proof | DONE (INACTIVE VERIFIED) |
| remote refresh | DONE (fresh) |
| Fresh Cleanup Preflight | DONE → APPROVAL_REQUIRED |
| plan refresh | DONE (left REQUIRES_VENDOR_RESTORATION) |
| reports | DONE |
| tests | DONE (499 / 0 failures) |
| human-boundary stop | DONE — no model removal |

**Stop:** READY_FOR_MODEL_REMOVAL_AUTHORIZATION — install auth consumed; do not remove model without new exact authorization.

## P3.2A.2 — Vendor-Absent Managed Data Recovery Path

| Subtask | Status |
|---------|--------|
| vendor-managed data availability model | DONE |
| Ollama absent-data classification | DONE |
| local format compatibility | DONE (LIKELY_COMPATIBLE_INFERRED) |
| remediation state machine | DONE |
| installation proposal model | DONE (no production installer) |
| separate install vs cleanup authorization | DONE |
| explorer explanation | DONE (reasonSummary + CTA label) |
| Optimization Plan integration | DONE (`REQUIRES_VENDOR_RESTORATION` tier) |
| reports | DONE |
| tests | DONE |
| screenshots (fixture) | DONE |
| real read-only classification | DONE |
| Ollama install executed | **NO** |
| Model deletion authorization | **NOT REQUESTED** |

**Stop:** READY_FOR_OLLAMA_INSTALL_AUTHORIZATION — do not install; do not request model deletion.

## P3.2A.1 — Native Interface Resolution & Runtime Proof Closure

| Subtask | Status |
|---------|--------|
| native app resolution (`OllamaApplicationResolver`) | DONE |
| CLI capability proof (read-only version/help) | DONE |
| binary binding / fingerprint | DONE |
| local API read-only runtime fallback | DONE (usable when identity verified; live unreachable) |
| exact model runtime proof | DONE — live UNKNOWN |
| runtime freshness | DONE |
| manifest/reference refresh | DONE |
| coordinator E2E fake wiring | DONE |
| Fresh Read-Only Preflight | DONE — VERIFY_MORE |
| plan refresh | DONE |
| reports | DONE |
| drift tests (binary/manifest/ref/remote/runtime) | DONE |
| screenshots | SKIPPED (live still VERIFY_MORE; no fabrications) |
| Human authorization | NOT REACHED (correct) |

**Live classification:** `STALE_MODEL_DATA_WITH_NO_OLLAMA_INSTALL` / failureReason `STALE_MODEL_DATA_ONLY`  
**Blockers:** `OLLAMA_EXECUTABLE_UNRESOLVED`, `OLLAMA_MODEL_RUNTIME_NOT_INACTIVE_VERIFIED`  
**Next:** restore Ollama CLI/app → re-preflight. Do not authorize deletion.

## P3.2A — Ollama Native Cleanup Executor

| Subtask | Status |
|---------|--------|
| Scoped execution capability | DONE |
| OllamaNativeCleanupExecutor | DONE |
| Direct argv process runner | DONE |
| Runtime exact-model proof (`ollama ps`) | DONE |
| Fresh preflight integration | DONE |
| Remote freshness binding | DONE |
| Reference graph binding | DONE |
| Execution binding fingerprint | DONE |
| Single-use permit ledger | DONE |
| Audit integration | DONE |
| Post-mutation verifier | DONE |
| Storage recovery semantics | DONE |
| Optimization Plan capability integration | DONE |
| HF non-support regression | DONE |
| Raw blob block regression | DONE |
| Fake process tests | DONE |
| Real read-only preflight | DONE |
| Reports p3_2a_* | DONE |
| Screenshots (fixture) | DONE |
| Real ollama rm | NOT STARTED (requires separate human auth) |
| git commit | NOT STARTED (locked) |

## P3.1.1 — Bounded Remote Reacquisition

| Subtask | Status |
|---------|--------|
| RemoteReacquisitionProof + budget/transport | DONE |
| HuggingFaceRemoteVerifier (exact revision) | DONE |
| OllamaRemoteVerifier (exact manifest / tag drift) | DONE |
| Late pipeline stage (not on first-map path) | DONE |
| Freshness / stale rejection | DONE |
| Auth/gating → UNKNOWN (not FALSE) | DONE |
| Plan: Verified Future not Ready Now | DONE |
| Capability registry unchanged | DONE |
| UX evidence (remote / redownload / freshness) | DONE |
| Fixture tests (mock transport) | DONE |
| Real Mac read-only remote proof | DONE |
| 20GB plan rerun | DONE |
| Reports p3_1_1_* | DONE |
| Manual Check-remote button | NOT STARTED (deferred; auto late proof present) |
| git commit | NOT STARTED (locked) |

## P3.1 — Proof Coverage Expansion

| Subtask | Status |
|---------|--------|
| P3.0.4 metric semantics fix | DONE |
| OllamaStorageProofProvider | DONE |
| HuggingFaceStorageProofProvider | DONE |
| reverse references / shared bytes | DONE |
| verification strategy wiring | DONE |
| no MOVE_TO_TRASH for vendor raw blobs | DONE |
| UI explanations | DONE |
| reports + screenshots | DONE |
| fixture tests | DONE |
| real Mac read-only rescan | DONE |
| git commit | NOT STARTED (locked) |

## P3.0.4 — Time-to-First-Map

| Subtask | Status |
|---------|--------|
| baseline profiling | DONE |
| scan performance trace | DONE |
| map readiness model | DONE |
| direct-child-first publication | DONE |
| measurement cache audit | DONE |
| in-flight coalescing | DONE |
| bounded concurrency | DONE |
| progressive immutable snapshots | DONE |
| UI progressive state | DONE |
| partial map UX | DONE |
| main-thread audit | DONE |
| sunburst render profiling | PARTIAL |
| render-node aggregation | DONE (existing Other smaller items) |
| duplicate history identity hardening | DONE |
| performance reports | DONE |
| tests | DONE |
| real benchmark | DONE |
| screenshots | DONE |

## P3.0.3 — Goal-Based Optimization Plan

| Subtask | Status |
|---------|--------|
| OptimizationGoal | DONE |
| OptimizationCandidate | DONE |
| Execution capability registry | DONE |
| Eligibility tiers | DONE |
| Conflict / overlap graph | DONE |
| Planning algorithm | DONE |
| Recovery semantics | DONE |
| Plan model | DONE |
| Staleness | DONE |
| Exclusion explanations | DONE |
| Overview entry | DONE |
| Plan UI | DONE |
| Per-item action integration | DONE |
| P2.2 recovery integration | DONE |
| P3.0.2 context integration | DONE |
| Reports | DONE |
| Performance | DONE |
| Tests | DONE |
| Screenshots | DONE |
| P1-A | Read-only Scanner | PARTIAL | |
| P1-C | Detectors | PARTIAL | AI Tools semantic / Container Data 分解。Docker は fixture test のみ |
| P1-D | Case Study #001 scan | PARTIAL | reports/case001 再生成 |
| P1-E | Semantic classification | PARTIAL | L0–L5 |
| P1-F | Coverage KPI | PARTIAL | Identified + Semantic L3+/L4+/L5 |
| P1-G | Real-Mac False GREEN | PARTIAL | GREEN unique=0 |
| P1-H | Root cause | PARTIAL | |
| P1-I | Cleanup preview | PARTIAL | executable=false |
| P2 | Action / UI / AI polish | PARTIAL | P3.0 product UI 実装済み。P3.1 iCloud or RemoveLocalDownload 未着手 |

## P3.0 — Storage Intelligence Experience

| Subtask | Status |
|---------|--------|
| Disk capacity truth | DONE |
| Presentation resolver | DONE |
| Experience snapshot | DONE |
| Map data model | DONE |
| Sunburst visualization | DONE |
| Category UX | DONE |
| Insights | DONE |
| Recommendations | DONE |
| Needs Review | DONE |
| Protected | DONE |
| Entity detail | DONE |
| Recent actions | DONE |
| Action flow integration | DONE |
| Debug mode | DONE |
| Localization prep | PARTIAL |
| Accessibility | PARTIAL |
| Tests | DONE |
| Case Study | DONE |

## P3.0.1 — Dual-Lens Storage Explorer

| Subtask | Status |
|---------|--------|
| Physical hierarchy (reuse ScanSessionContext) | DONE |
| Multi-ring sunburst | DONE |
| STRUCTURE / MEANING / DECISION lenses | DONE |
| Drill-down + breadcrumbs + back/forward | DONE |
| Child list synchronization | DONE |
| Progressive scan stages | DONE |
| Search + Largest Items | DONE |
| Quick Look + Reveal in Finder | DONE |
| Explorer reports + screenshots | DONE |
| Safety regressions | DONE |
| Separate crawler | NOT ADDED — reuses existing scanner session |

## Blocked

- Deep Research original JSON 未着
