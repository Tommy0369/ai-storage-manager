# Case Study #001 — P1.1 unique accounting

Read-only. executable=false. GREEN unique = 0.

## Accounting

- scanned roots ≈ 169.8 GiB
- unique classified ≈ 165.5 GiB
- duplicate bytes removed ≈ 132.1 GiB（parent+child の inclusive 二重加算を除去）
- Identified coverage of roots ≈ 97.4%（folder 名の Identified とは別物として Semantic KPI を見る）

## Semantic

- L3+ ≈ 27.3%
- L4+ ≈ 4.0%
- L5 = 0%（GREEN かつ predicate 充足のみ。今は GREEN 0）

## Unique class

- GREEN 0
- YELLOW ≈ 7.3 GiB
- RED ≈ 152.8 GiB
- UNKNOWN ≈ 5.3 GiB
- 合計 = uniqueTotal（root を超えない）

## Docker

この Mac に Docker.app / docker CLI なし。`docker_detection.json` に記録。0 byte は「未使用」ではなく **未インストール**。
