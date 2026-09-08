# P2.0.3 Handoff — First Real Mutation Candidate Selection

Phase: **ACT READINESS**  
ACT Executor: **NOT STARTED**  
Mutation: **STRICTLY FORBIDDEN**

---

## Outcome: **C — NO_SAFE_REAL_MUTATION_CANDIDATE**

No current exact-bounded entity reaches `APPROVAL_REQUIRED` or `CONTRACT_SATISFIED_READ_ONLY`.

This is **honest and correct**. Do not implement Executor.

---

## Selection Summary

| Field | Value |
|-------|-------|
| outcome | `NO_SAFE_REAL_MUTATION_CANDIDATE` |
| FIRST_REAL_MUTATION_GATE status | `NO_SAFE_REAL_MUTATION_CANDIDATE` |
| selectedEntityID | **null** |
| rankingEligibleCount | **0** |
| approvalRequired | **0** |

---

## Inventory (real Mac)

| Metric | Count |
|--------|-------|
| entities in inventory | 467 |
| MOVE_TO_TRASH candidates | 503 entries |
| MOVE_TO_ICLOUD candidates | 503 entries |
| REMOVE_LOCAL_DOWNLOAD candidates | (in inventory) |
| broad root entities rejected | **44** |
| PREFLIGHT_REQUIRED | **2** |
| APPROVAL_REQUIRED | **0** |
| ranking eligible | **0** |

---

## user.downloads × MOVE_TO_ICLOUD audit

| Check | Result |
|-------|--------|
| isRootBucket | **true** |
| entityGranularityBlocker | **ENTITY_GRANULARITY_TOO_BROAD** |
| fitnessTier | **TOO_BROAD_FOR_FIRST_MUTATION** |
| mutationReadiness | PREFLIGHT_REQUIRED |
| safetyClass | GREEN |
| recommendation | MOVE_TO_ICLOUD (actionable) |
| exact_bounded_entity | **false** |

**Not promoted** despite GREEN + PREFLIGHT. Downloads **root** ≠ first mutation target.

Missing dynamic preflight (expected):
- iCloud availability (unknown at scan time)
- destination known
- quota known
- conflict state known
- fresh runtime/cloud preflight

Static contracts: transaction/post-verify/audit **available**.

---

## Why no candidate

1. **DerivedData empty** (REAL_STATE_CHANGED, P2.0.2) — no generated-artifact trash candidate
2. **No entity at APPROVAL_REQUIRED**
3. **Downloads root** rejected by granularity gate
4. **No ranking-eligible** entries (blocked / too broad / too complex dominate)
5. File-level user content entities not surfaced in current architecture (limitation)

---

## FirstMutationFitness model

Tiers applied read-only (never overrides Safety):

- `IDEAL_FIRST_MUTATION` — LOW blast + SIMPLE + gate ready
- `ACCEPTABLE_FIRST_MUTATION` — eligible but not ideal
- `TOO_COMPLEX_FOR_FIRST_MUTATION` — e.g. MOVE_TO_ICLOUD complexity
- `TOO_BROAD_FOR_FIRST_MUTATION` — aggregate roots (Downloads, Documents, DerivedData root)
- `BLOCKED_BY_EVIDENCE` / `BLOCKED_BY_PRODUCT_POLICY`

Preference order honored: MOVE_TO_TRASH > REMOVE_LOCAL_DOWNLOAD > MOVE_TO_ICLOUD — but **proof quality** controls outcome.

---

## Safety locks

| Lock | Value |
|------|-------|
| Tests | **270 / 0 failures** (was 263) |
| duplicateEvaluations | **0** |
| False GREEN | **0** |
| preview.executable | **false** |
| destructiveActionsExecuted | **false** |
| actualMutationImplementations | **0** |
| ExecutionPermit | generation **disabled** |

Protection corpus preserved (Voice Memo, iOS Backup, Git, Claude, Cursor, SOT=true, evict≠delete).

---

## New reports

- `first_mutation_candidate_inventory.json`
- `first_mutation_candidate_ranking.json`
- `first_mutation_candidate_selection.json`
- `downloads_move_to_icloud_audit.json`
- `p2_1_gate_status.json` (now `FIRST_REAL_MUTATION_GATE`)

---

## Recommended next step

**Do not implement Executor.**

Options when ready to proceed:

1. **Wait for real generated artifact** — Xcode rebuild → DerivedData child with strict proof → re-scan
2. **Surface individual user files** — future phase; not scope-creeped here
3. **Human decision** — if a specific bounded file/folder should be modeled, define it explicitly before P2.1

Gate stays strict. Smallest blast radius wins — not largest GB.
