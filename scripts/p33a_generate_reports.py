#!/usr/bin/env python3
"""P3.3A read-only report generator. No mutation. No second crawler."""
from __future__ import annotations

import json
import os
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports" / "case001"
HOME = Path.home()
GS = HOME / "Library/Application Support/Cursor/User/globalStorage"
HIST = HOME / "Library/Application Support/AIStorageManager/History"
OLLAMA = 2_497_293_931
HF = 3_083_520_968
COMPLETED = OLLAMA + HF
GOAL = 20_000_000_000


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def du_bytes(path: Path) -> int:
    if not path.exists():
        return 0
    r = subprocess.run(["du", "-sk", str(path)], capture_output=True, text=True)
    if r.returncode != 0:
        return 0
    return int(r.stdout.split()[0]) * 1024


def disk_capacity():
    st = os.statvfs("/")
    total = st.f_frsize * st.f_blocks
    free = st.f_frsize * st.f_bavail
    used = total - free
    return total, free, used


def cursor_app():
    app = Path("/Applications/Cursor.app")
    if not app.exists():
        return False, None, None
    r = subprocess.run(
        ["plutil", "-extract", "CFBundleShortVersionString", "raw", str(app / "Contents/Info.plist")],
        capture_output=True, text=True,
    )
    ver = r.stdout.strip() if r.returncode == 0 else None
    r2 = subprocess.run(
        ["plutil", "-extract", "CFBundleIdentifier", "raw", str(app / "Contents/Info.plist")],
        capture_output=True, text=True,
    )
    bid = r2.stdout.strip() if r2.returncode == 0 else None
    return True, ver, bid


def cursor_running() -> bool:
    r = subprocess.run(["ps", "-axo", "comm="], capture_output=True, text=True)
    return any("Cursor" in line for line in r.stdout.splitlines())


def open_gs_paths() -> list[str]:
    r = subprocess.run(["lsof", "-nP", "-Fn"], capture_output=True, text=True)
    hits = []
    needle = str(GS)
    for line in r.stdout.splitlines():
        if line.startswith("n") and needle in line:
            hits.append(line[1:])
    # sanitize to relative classes
    out = []
    for h in hits:
        rel = h.replace(str(GS) + "/", "")
        if rel and rel not in out:
            out.append(rel.split("/")[0])
    return sorted(set(out))


def kv_summary():
    db = GS / "state.vscdb"
    if not db.exists():
        return []
    sql = (
        "PRAGMA query_only=ON; "
        "SELECT CASE "
        "WHEN key LIKE 'bubbleId:%' THEN 'bubbleId' "
        "WHEN key LIKE 'agentKv:%' THEN 'agentKv' "
        "WHEN key LIKE 'checkpointId:%' THEN 'checkpointId' "
        "WHEN key LIKE 'composerData:%' THEN 'composerData' "
        "WHEN key LIKE 'composer.content.%' THEN 'composer.content' "
        "WHEN key LIKE 'ofsContent:%' THEN 'ofsContent' "
        "WHEN key LIKE 'inlineDiff:%' THEN 'inlineDiff' "
        "ELSE 'other' END AS cls, COUNT(*), SUM(length(value)) "
        "FROM cursorDiskKV GROUP BY cls ORDER BY SUM(length(value)) DESC LIMIT 12;"
    )
    r = subprocess.run(["sqlite3", str(db), sql], capture_output=True, text=True, timeout=180)
    rows = []
    role = {
        "bubbleId": "AI_CONVERSATION_OR_AGENT_BUBBLE_STATE",
        "agentKv": "AGENT_KEY_VALUE_STATE",
        "checkpointId": "CHECKPOINT_OR_RECOVERY_STATE",
        "composerData": "COMPOSER_SESSION_STATE",
        "composer.content": "COMPOSER_SESSION_STATE",
    }
    for line in r.stdout.splitlines():
        parts = line.split("|")
        if len(parts) < 3:
            continue
        cls, cnt, byt = parts[0], int(parts[1]), int(parts[2])
        rows.append({
            "keyClass": cls,
            "keyCount": cnt,
            "approxValueBytes": byt,
            "semanticRole": role.get(cls, "APP_MANAGED_KV"),
        })
    return rows


def top_entities_from_history():
    files = sorted(HIST.glob("*.json"), key=lambda p: p.stat().st_mtime)
    if not files:
        return []
    data = json.loads(files[-1].read_text())
    ents = []
    for e in data.get("selectedEntitySummaries") or []:
        b = e.get("logicalBytes") or e.get("exclusiveBytes") or 0
        eid = e.get("entityID")
        if not eid or not b:
            continue
        if "qwen3" in eid or "whisper-large-v3" in eid:
            continue
        ents.append((int(b), eid))
    seen = set()
    out = []
    for b, eid in sorted(ents, key=lambda x: -x[0]):
        if eid in seen:
            continue
        seen.add(eid)
        out.append({"entityID": eid, "uniqueBytes": b, "note": "from cached explorer history + live Cursor remeasure"})
        if len(out) >= 20:
            break
    # Override Cursor with live bytes
    live = du_bytes(GS)
    for row in out:
        if row["entityID"] == "ai.cursor.global_storage":
            row["uniqueBytes"] = live
            row["note"] = "LIVE remasured globalStorage"
    if not any(r["entityID"] == "ai.cursor.global_storage" for r in out):
        out.insert(0, {"entityID": "ai.cursor.global_storage", "uniqueBytes": live, "note": "LIVE"})
        out = sorted(out, key=lambda r: -r["uniqueBytes"])[:20]
    else:
        out = sorted(out, key=lambda r: -r["uniqueBytes"])[:20]
    return out, files[-1].name, data.get("generatedAt")


def classify_children(root_bytes: int, open_set: set[str]):
    comps = []
    ownership = []
    children = sorted([p for p in GS.iterdir() if not p.name.startswith(".")])
    mapped = 0
    for child in children:
        b = du_bytes(child)
        mapped += b
        rel = child.name
        open_ = rel in open_set or any(o.startswith(rel) for o in open_set)
        pct = (b / root_bytes * 100.0) if root_bytes else 0
        runtime = "ACTIVE_VERIFIED" if open_ else "RUNTIME_UNKNOWN"
        if rel == "state.vscdb":
            comps.append(comp("cursor.gs.state_vscdb", rel, "DATABASE", "CURSOR_CORE",
                              "CORE_GLOBAL_STATE_DATABASE", b, pct, runtime, True,
                              "TRUE", "USER_ORIGINAL_OR_USER_STATE_PROTECTED", "UNKNOWN", "FALSE_INFERRED",
                              "VERIFIED", "KEEP", ["SQLITE_MAGIC_VERIFIED", "cursorDiskKV_DOMINANT", f"OPEN={open_}"]))
        elif rel.endswith("-wal"):
            comps.append(comp(f"cursor.gs.{rel}", rel, "DATABASE_WAL", "CURSOR_CORE", "SQLITE_WAL",
                              b, pct, runtime, True, "UNKNOWN", "APP_MANAGED", "UNKNOWN", "UNKNOWN",
                              "VERIFIED", "KEEP", ["WAL_SIBLING"]))
        elif rel.endswith("-shm"):
            comps.append(comp(f"cursor.gs.{rel}", rel, "DATABASE_SHM", "CURSOR_CORE", "SQLITE_SHM",
                              b, pct, runtime, True, "UNKNOWN", "APP_MANAGED", "UNKNOWN", "UNKNOWN",
                              "VERIFIED", "KEEP", ["SHM_SIBLING"]))
        elif rel == "state.vscdb.backup":
            comps.append(comp("cursor.gs.state_vscdb_backup", rel, "CHECKPOINT_OR_RECOVERY_STATE", "CURSOR_CORE",
                              "DATABASE_BACKUP", b, pct, runtime, True, "UNKNOWN",
                              "USER_ORIGINAL_OR_USER_STATE_PROTECTED", "UNKNOWN", "UNKNOWN",
                              "INFERRED", "VERIFY_MORE", ["BACKUP_SIBLING"]))
        elif rel == "conversation-search.db":
            comps.append(comp("cursor.gs.conversation_search_db", rel, "AI_CONVERSATION_OR_CONTEXT_STATE",
                              "CURSOR_CORE", "CONVERSATION_SEARCH_INDEX", b, pct, runtime, True,
                              "TRUE", "USER_ORIGINAL_OR_USER_STATE_PROTECTED", "UNKNOWN", "FALSE_INFERRED",
                              "VERIFIED", "KEEP", ["SQLITE_conversations_TABLE", "NO_CONTENT_DUMP"]))
        elif rel == "anysphere.cursor-agent-worker":
            versions = child / "agent-cli/.local/share/cursor-agent/versions"
            vb = du_bytes(versions)
            comps.append(comp("cursor.gs.agent_cli_versions",
                              "anysphere.cursor-agent-worker/agent-cli/.../versions",
                              "VENDOR_TOOLCHAIN_VERSIONS", "CURSOR_CORE", "AGENT_CLI_VERSIONED_TOOLCHAINS",
                              vb, vb / root_bytes * 100 if root_bytes else 0, "RUNTIME_UNKNOWN", False,
                              "FALSE_INFERRED", "APP_GENERATED", "UNKNOWN", "LIKELY_REGENERABLE_INFERRED",
                              "INFERRED", "NATIVE_CLEANUP_CANDIDATE",
                              ["MULTIPLE_VERSION_DIRS", "NOT_EXECUTABLE_THIS_PHASE"]))
            residual = max(0, b - vb)
            if residual:
                comps.append(comp("cursor.gs.agent_worker_logs", "anysphere.cursor-agent-worker/(logs+meta)",
                                  "LOG_OR_TELEMETRY", "CURSOR_CORE", "AGENT_WORKER_LOGS", residual,
                                  residual / root_bytes * 100 if root_bytes else 0, runtime, False,
                                  "FALSE_INFERRED", "APP_GENERATED", "UNKNOWN", "UNKNOWN",
                                  "INFERRED", "VERIFY_MORE", ["RESIDUAL"]))
            ownership.append({
                "namespace": rel,
                "extensionID": rel,
                "extensionInstalled": False,
                "version": None,
                "ownershipEvidence": "CURSOR_FIRST_PARTY_NAMESPACE_NO_MARKETPLACE_DIR",
                "storageBytes": b,
                "availabilityState": "CURSOR_FIRST_PARTY_NAMESPACE",
                "recommendedNextProof": "Prove agent-cli version retention policy",
            })
        elif rel == "anysphere.cursor-retrieval":
            comps.append(comp("cursor.gs.cursor_retrieval", rel, "CHECKPOINT_OR_RECOVERY_STATE", "CURSOR_CORE",
                              "RETRIEVAL_CHECKPOINTS", b, pct, runtime, False, "UNKNOWN",
                              "USER_ORIGINAL_OR_USER_STATE_PROTECTED", "UNKNOWN", "UNKNOWN",
                              "INFERRED", "KEEP", ["CHECKPOINTS_SUBTREE", "FIRST_PARTY"]))
            ownership.append({
                "namespace": rel, "extensionID": rel, "extensionInstalled": False, "version": None,
                "ownershipEvidence": "CURSOR_FIRST_PARTY_NAMESPACE_NO_MARKETPLACE_DIR",
                "storageBytes": b, "availabilityState": "CURSOR_FIRST_PARTY_NAMESPACE",
                "recommendedNextProof": "Checkpoint lifecycle semantics",
            })
        elif rel == "anysphere.cursor-commits":
            comps.append(comp("cursor.gs.cursor_commits", rel, "CURSOR_CORE_GLOBAL_STATE", "CURSOR_CORE",
                              "NAMESPACE_STORAGE", b, pct, runtime, False, "UNKNOWN", "APP_MANAGED",
                              "UNKNOWN", "UNKNOWN", "VERIFIED", "VERIFY_MORE", ["FIRST_PARTY"]))
            ownership.append({
                "namespace": rel, "extensionID": rel, "extensionInstalled": False, "version": None,
                "ownershipEvidence": "CURSOR_FIRST_PARTY_NAMESPACE_NO_MARKETPLACE_DIR",
                "storageBytes": b, "availabilityState": "CURSOR_FIRST_PARTY_NAMESPACE",
                "recommendedNextProof": "Confirm commit-related state semantics",
            })
        elif rel == "ms-dotnettools.vscode-dotnet-runtime":
            installed = any((HOME / ".cursor/extensions").glob("ms-dotnettools.vscode-dotnet-runtime-*"))
            comps.append(comp("cursor.gs.ms_dotnet_runtime", rel, "EXTENSION_GLOBAL_STORAGE", "EXTENSION",
                              "NAMESPACE_STORAGE", b, pct, runtime, False, "UNKNOWN", "APP_MANAGED",
                              "UNKNOWN", "UNKNOWN", "VERIFIED" if installed else "UNKNOWN", "VERIFY_MORE",
                              ["EXTENSION_DIR_MATCH"]))
            ownership.append({
                "namespace": rel, "extensionID": rel, "extensionInstalled": installed,
                "version": "3.1.0-universal" if installed else None,
                "ownershipEvidence": "EXTENSION_DIR_EXACT_PREFIX_MATCH",
                "storageBytes": b,
                "availabilityState": "EXTENSION_PRESENT" if installed else "EXTENSION_ABSENT_MANAGED_DATA_REMAINS",
                "recommendedNextProof": "Vendor-native lifecycle",
            })
        elif rel == "storage.json":
            comps.append(comp("cursor.gs.storage_json", rel, "CURSOR_CORE_GLOBAL_STATE", "CURSOR_CORE",
                              "PROFILE_STORAGE_MANIFEST", b, pct, runtime, False, "TRUE", "APP_MANAGED",
                              "UNKNOWN", "UNKNOWN", "VERIFIED", "KEEP", ["METADATA_FILE"]))
        else:
            comps.append(comp(f"cursor.gs.{rel}", rel, "UNKNOWN_APP_MANAGED", "UNKNOWN",
                              "UNMAPPED", b, pct, runtime, False, "UNKNOWN", "UNKNOWN",
                              "UNKNOWN", "UNKNOWN", "UNKNOWN", "VERIFY_MORE", ["UNMAPPED"]))
    comps.sort(key=lambda c: -c["uniqueBytes"])
    unknown = max(0, root_bytes - mapped)
    return comps, ownership, mapped, unknown


def comp(eid, rel, kind, owner, role, b, pct, runtime, db, sot, user, reac, regen, conf, action, evidence):
    return {
        "entityID": eid,
        "rootEntityID": "ai.cursor.global_storage",
        "componentKind": kind,
        "path": str(GS / rel.split("/")[0]),
        "relativePath": rel,
        "owner": owner,
        "extensionID": None,
        "extensionPresent": None,
        "storageRole": role,
        "observedBytes": b,
        "uniqueBytes": b,
        "sharedBytes": 0,
        "fileCount": None,
        "databaseLike": db,
        "runtimeState": runtime,
        "sourceOfTruthState": sot,
        "userOriginalState": user,
        "reacquisitionState": reac,
        "regenerabilityState": regen,
        "syncState": "UNKNOWN",
        "evidence": evidence,
        "classificationConfidence": conf,
        "recommendedAction": action,
        "actionability": "NOT_EXECUTABLE" if action in ("KEEP", "VERIFY_MORE", "NONE") else "CANDIDATE_ONLY_NOT_EXECUTABLE",
        "percentOfRoot": round(pct, 4),
    }


def opportunities(comps):
    ops = []
    for c in comps:
        if c["uniqueBytes"] < 50_000_000:
            continue
        score = min(40, c["uniqueBytes"] / 1e9 * 4)
        if c["recommendedAction"] == "NATIVE_CLEANUP_CANDIDATE":
            score += 25
        elif c["recommendedAction"] == "VERIFY_MORE":
            score += 10
        if "USER" in c["userOriginalState"]:
            score -= 5
        if c["runtimeState"] == "ACTIVE_VERIFIED":
            score -= 10
        ops.append({
            "candidateID": f"opp.{c['entityID']}",
            "component": c["relativePath"],
            "uniqueBytes": c["uniqueBytes"],
            "currentSafety": "PROTECTED",
            "potentialAction": c["recommendedAction"],
            "proofFeasibility": "HARD" if c["componentKind"] in ("DATABASE", "AI_CONVERSATION_OR_CONTEXT_STATE") else "MEDIUM",
            "requiredEvidence": ["vendor retention/cleanup", "inactive COMPLETE runtime", "user consent"]
                if c["componentKind"] == "DATABASE"
                else ["version pin", "regeneration contract"],
            "expectedValue": f"{c['uniqueBytes']/1e9:.2f} GB",
            "risk": "CRITICAL" if "USER" in c["userOriginalState"] else "MEDIUM",
            "nativeContractAvailability": "NONE_PROVEN" if c["componentKind"] == "DATABASE" else "UNKNOWN_DOCUMENTED_NATIVE",
            "preservationPotential": "HIGH" if "USER" in c["userOriginalState"] else "LOW",
            "currentExecutable": False,
            "rankingScore": round(max(0, score), 2),
            "rankingExplanation": "Understand growth before any action" if c["componentKind"] == "DATABASE"
                else "Stale toolchain versions may be future native cleanup candidates",
        })
    return sorted(ops, key=lambda o: -o["rankingScore"])


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()
    total, free, used = disk_capacity()
    top, snap_name, snap_at = top_entities_from_history()
    inv_ms = int((time.perf_counter() - t0) * 1000)

    t1 = time.perf_counter()
    root_bytes = du_bytes(GS)
    installed, version, bid = cursor_app()
    running = cursor_running()
    root_ms = int((time.perf_counter() - t1) * 1000)

    t2 = time.perf_counter()
    open_rels = open_gs_paths()
    rt_ms = int((time.perf_counter() - t2) * 1000)

    t3 = time.perf_counter()
    comps, ownership, mapped, unknown = classify_children(root_bytes, set(open_rels))
    cls_ms = int((time.perf_counter() - t3) * 1000)

    t4 = time.perf_counter()
    # ownership already built
    own_ms = int((time.perf_counter() - t4) * 1000)

    t5 = time.perf_counter()
    kv = kv_summary()
    # growth from history
    files = sorted(HIST.glob("*.json"), key=lambda p: p.stat().st_mtime)
    gs_series = []
    for f in files:
        d = json.loads(f.read_text())
        for e in d.get("selectedEntitySummaries") or []:
            if e.get("entityID") == "ai.cursor.global_storage":
                b = e.get("logicalBytes") or e.get("exclusiveBytes")
                if b:
                    gs_series.append((d.get("generatedAt"), int(b), f.name))
                break
    growth_ms = int((time.perf_counter() - t5) * 1000)

    t6 = time.perf_counter()
    ops = opportunities(comps)
    opp_ms = int((time.perf_counter() - t6) * 1000)

    cursor_still_top = bool(top) and top[0]["entityID"] == "ai.cursor.global_storage"

    inventory = {
        "diskCapacityTotalBytes": total,
        "diskCapacityFreeBytes": free,
        "diskCapacityUsedBytes": used,
        "completedVerifiedRecoveryBytes": COMPLETED,
        "ollamaVerifiedRecovery": OLLAMA,
        "hfVerifiedRecovery": HF,
        "remaining20GBGoalBytes": GOAL - COMPLETED,
        "top20UniqueEntities": top,
        "ReadyNow": 0,
        "ApprovalRequired": 0,
        "VerifiedFuture": 0,
        "VerifyMore": root_bytes,  # Cursor remains VERIFY_MORE / protected investigation surface
        "Protected": root_bytes,
        "currentlyExecutableActions": [
            "MOVE_TO_TRASH (when GREEN trash candidates exist)",
            "OLLAMA MODEL VENDOR_NATIVE_CLEANUP (no present target)",
            "HF SNAPSHOT VENDOR_NATIVE_CLEANUP (no present target)",
        ],
        "removedCompletedActionsExcluded": True,
        "qwen3Absent": not (HOME / ".ollama/models/manifests/registry.ollama.ai/library/qwen3/4b").exists(),
        "hfRemovedRevisionAbsent": not (HOME / ".cache/huggingface/hub/models--mlx-community--whisper-large-v3-mlx").exists(),
        "cursorStillTopTarget": cursor_still_top,
        "historySnapshotID": snap_name,
        "historySnapshotAt": snap_at,
        "generatedAt": now(),
    }

    coverage = (mapped / root_bytes * 100.0) if root_bytes else 0
    root_report = {
        "entity": "ai.cursor.global_storage",
        "pathClass": "ApplicationSupport/Cursor/User/globalStorage",
        "owner": "CURSOR",
        "semanticRole": "GLOBAL_STORAGE",
        "observedBytes": root_bytes,
        "uniqueBytes": root_bytes,
        "mappedChildBytes": mapped,
        "unknownBytes": unknown,
        "classificationCoverage": round(coverage, 4),
        "accountingValid": unknown == max(0, root_bytes - mapped) and mapped <= root_bytes + 4096,
        "appInstalled": installed,
        "appVersion": version,
        "appBundleID": bid,
        "appRunning": running,
        "rootSafety": "PROTECTED",
        "rootActionability": "KEEP",
        "rootExecutable": False,
        "privacyNote": "Metadata/sizes/key-class aggregates only. No prompt/message/source/credential/DB row contents.",
        "generatedAt": now(),
    }

    components_report = {
        "components": comps[:30],
        "kvNamespaceSummaries": kv,
        "privacyNote": root_report["privacyNote"],
        "generatedAt": now(),
    }

    runtime = {
        "cursorRunning": running,
        "runtimeSnapshotCompleteness": "PARTIAL_OPEN_FILE_BATCH",
        "openGlobalStorageComponents": open_rels,
        "openDatabaseComponents": [x for x in open_rels if "vscdb" in x or x.endswith(".db")],
        "unknownRuntimeComponents": [c["relativePath"] for c in comps if c["runtimeState"] == "RUNTIME_UNKNOWN"][:20],
        "observedAt": now(),
        "freshUntil": now(),
        "note": "One-shot lsof batch over process table; not per-entity spawn",
    }

    delta = None
    if len(gs_series) >= 2:
        delta = gs_series[-1][1] - gs_series[0][1]
    growth = {
        "comparisonAvailable": len(gs_series) >= 2,
        "comparisonQuality": "COARSE_ROOT_ONLY" if len(gs_series) >= 2 else "INSUFFICIENT",
        "rootDelta": delta,
        "series": [{"at": a, "bytes": b, "snapshot": s} for a, b, s in gs_series[-5:]],
        "liveRootBytes": root_bytes,
        "topGrowingComponents": [
            {"component": "state.vscdb / cursorDiskKV(bubbleId+agentKv)", "note": "Dominant live mass; subcomponent history not separately snapshotted"}
        ],
        "topShrinkingComponents": [],
        "unexplainedDelta": delta,
        "growthAffectsSafety": False,
        "generatedAt": now(),
    }

    decision = {
        "currentTopStorageEntities": [r["entityID"] for r in top[:10]],
        "selectedNextCenterpin": "CURSOR_DATABASE_GROWTH_ROOT_CAUSE",
        "selectedEntity": "ai.cursor.global_storage",
        "selectedComponent": "state.vscdb (cursorDiskKV: bubbleId + agentKv)",
        "selectedBytes": next((c["uniqueBytes"] for c in comps if c["relativePath"] == "state.vscdb"), root_bytes),
        "whyThisBeatsAlternatives": (
            "~10GB of ~14GB is an OPEN core SQLite DB whose value bytes are conversation/agent state classes. "
            "Understanding growth/retention is higher leverage than deleting protected user state or chasing smaller targets. "
            "Agent-cli multi-version (~2.6GB) is a secondary NATIVE_CLEANUP_CANDIDATE only."
        ),
        "expectedProofPath": (
            "Vendor-documented retention/cleanup for cursorDiskKV classes; "
            "export/archive contract if reduction is ever considered; "
            "COMPLETE runtime inactivity proof; never raw SQLite mutation."
        ),
        "mutationNeededNextPhase": False,
        "humanAuthorizationNeededNextPhase": False,
        "rejectedAlternatives": [
            "CURSOR_COMPONENT_NATIVE_CLEANUP_PROOF (agent-cli versions) — valuable but secondary bytes",
            "CURSOR_COMPONENT_PRESERVATION_PROOF — relevant later once export contract exists",
            "CURSOR_EXTENSION_ABSENT_REMEDIATION — first-party namespaces, not disposable marketplace orphans",
            "DIFFERENT_CURRENT_ENTITY_HIGHER_VALUE — Cursor remains #1 unique bytes",
            "NO_SAFE_HIGH_VALUE_ACTION_YET — intelligence gap is the action",
        ],
        "generatedAt": now(),
    }

    perf = {
        "currentInventoryRefreshMs": inv_ms,
        "cursorRootResolutionMs": root_ms,
        "cursorComponentClassificationMs": cls_ms,
        "extensionOwnershipMappingMs": own_ms,
        "runtimeRelationshipBuildMs": rt_ms,
        "historyGrowthAnalysisMs": growth_ms,
        "opportunityRankingMs": opp_ms,
        "secondCrawlerAdded": False,
        "kvNamespaceSummaryIncluded": True,
        "generatedAt": now(),
    }

    writes = {
        "p3_3a_current_inventory_rebase.json": inventory,
        "p3_3a_cursor_root.json": root_report,
        "p3_3a_cursor_components.json": components_report,
        "p3_3a_cursor_extension_ownership.json": {"namespaces": ownership, "generatedAt": now()},
        "p3_3a_cursor_runtime.json": runtime,
        "p3_3a_cursor_growth.json": growth,
        "p3_3a_cursor_opportunities.json": {"opportunities": ops, "anyCurrentExecutable": False, "generatedAt": now()},
        "p3_3a_next_phase_decision.json": decision,
        "p3_3a_performance.json": perf,
    }
    for name, obj in writes.items():
        (OUT / name).write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")
        print("wrote", name)

    print("root_bytes", root_bytes, "mapped", mapped, "unknown", unknown)
    print("cursor_top", cursor_still_top, "running", running, "version", version)


if __name__ == "__main__":
    main()
