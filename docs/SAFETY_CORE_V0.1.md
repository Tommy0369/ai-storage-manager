# Safety Core v0.1 — Architecture

製品: **AI Storage Manager**  
役割: Mac Storage **Decision Intelligence**（削除ツールではない）

## 1. Current architecture analysis

作業開始時点の Cursor ワークスペースは `ai-assessment-session`（Next.js 診断アプリ）だった。  
Swift / Storage 設計は存在しない。既存診断アプリは破壊していない。

本リポジトリは Safety Core 専用。UI は未実装。依存方向は一方通行:

```
Safety Core → Semantic Result → AI Explanation Layer
```

AI から Safety Class を書き戻す経路はない。

## 2. Gap analysis

| 要求 | 現状 | v0.1 |
|------|------|------|
| 178 rule KB JSON | 添付ファイル未着 | schema + 初期 45 rules。原本到着後は source artifact として保持 |
| Evidence Resolver 全項目 | なし | 拡張可能な Evidence モデル + 一部解決 |
| Native macOS scan | なし | Path matcher + 合成 Evidence（実スキャンは P1） |
| SwiftUI | なし | 分離維持。Core に UI 依存なし |
| Permanent delete | — | 実装しない |

## 3. Proposed Safety Core architecture

```
StorageScanner (P1)
  → EntityResolver
  → EvidenceResolver
  → SafetyRuleEngine
  → SafetyDecision
  → RecommendationEngine (P2)
  → ActionPlanner
  → ActionExecutor (P2, approval required)
  → ResultVerifier
```

評価優先順位（固定）:

1. HARD BLOCK  
2. USER PROTECTION  
3. SOURCE OF TRUTH  
4. ACTIVE USE  
5. SYNC / BLAST RADIUS  
6. EXACT VENDOR RULE  
7. RUNTIME PREDICATES  
8. GENERIC CACHE / TEMP  
9. UNKNOWN FALLBACK  

`UNKNOWN → GREEN` は禁止。Score による Class 昇格も禁止。

## 4. Directory / file structure

```
Sources/SafetyCore/
  Models/
  Knowledge/
  Engine/
  Evidence/
  Protection/
  Action/
  Verification/
  LLMBoundary/
  Resources/knowledge/
Tests/SafetyCoreTests/
docs/
```

## 5. Data models

- `SafetyClass`: GREEN / YELLOW / RED / UNKNOWN  
- `SafetyScore`: class 内ランキングのみ  
- `StorageEntity` × `ActionMode` × `RuntimeState`  
- `EvidenceBundle` + confidence  
- `SafetyDecision` + reason codes（LLM 入力はこの snapshot のみ）  
- `UserProtectionRule`  
- `AuditEvent`（パスは正規化、本文は保存しない）  
- `VerificationReport`（logical vs physical bytes を分離）

## 6. Rule DSL

JSON primary。フィールド:

- match（path glob, owner, no symlink follow）  
- default_class / base_score  
- evaluation_layer  
- required_predicates（未充足なら GREEN 不可）  
- demote_to_yellow_if / demote_to_red_if / hard_block_if  
- action_mode（entity と action の組で class が変わる）  
- growth_causes  
- explanation_ja  
- verification  
- effects  

Class はゲート。Score はランキング。

## 7. Initial rules

`compiled_rules_v0.1.json` に Tier1–3 の 45 件。  
False GREEN 防止のため、GREEN 候補は required_predicates 必須。

## 8. Test architecture

最重要 KPI: **False GREEN = 0**

Golden set: hard block, user originals, cloud delete vs evict, Docker volume, Git source, node_modules, Xcode split, symlink, active process, UNKNOWN fallback, score non-promotion, LLM cannot override, no permanent delete.

## 9. Implementation phases

- **P0 (本コミット)**: models, loader, engine, gates, UNKNOWN, planner skeleton, tests  
- **P1**: real evidence (lsof, process, File Provider), scanners, detectors  
- **P2**: explanation polish, cleanup planning, UI（Direct Distribution 前提）
