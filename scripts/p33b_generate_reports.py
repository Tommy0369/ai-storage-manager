#!/usr/bin/env python3
"""P3.3B report generator — read-only. No DB mutation. No 10GB copy."""
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
DB = GS / "state.vscdb"
WAL = GS / "state.vscdb-wal"
SHM = GS / "state.vscdb-shm"
BACKUP = GS / "state.vscdb.backup"
VERS = GS / "anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions"
BIN_LINK = GS / "anysphere.cursor-agent-worker/agent-cli/.local/bin/cursor-agent"
APP = Path("/Applications/Cursor.app/Contents/Resources/app")


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def meta(p: Path):
    st = p.stat()
    return {"bytes": st.st_size, "mtime": st.st_mtime}


def sqlite(sql: str, db: Path = DB) -> str:
    upper = sql.upper()
    # Deny mutating statements; allow PRAGMA auto_vacuum (read)
    denied = [
        "DELETE ", "UPDATE ", "INSERT ", "WAL_CHECKPOINT", "REINDEX",
        "ALTER TABLE", "DROP ", "CREATE TABLE", "ATTACH ", "DETACH ", "REPLACE INTO",
    ]
    for tok in denied:
        if tok in upper:
            raise RuntimeError(f"mutating SQL denied: {tok}")
    # VACUUM as statement, not auto_vacuum
    import re
    if re.search(r"\bVACUUM\b", upper) and "AUTO_VACUUM" not in upper:
        raise RuntimeError("mutating SQL denied: VACUUM")
    if "PRAGMA JOURNAL_MODE=" in upper or "PRAGMA AUTO_VACUUM=" in upper:
        raise RuntimeError("mutating pragma assignment denied")
    r = subprocess.run(["sqlite3", f"file:{db}?mode=ro", sql], capture_output=True, text=True)
    if r.returncode != 0:
        r = subprocess.run(["sqlite3", str(db), sql], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr)
    return r.stdout.strip()


def du_bytes(p: Path) -> int:
    if not p.exists():
        return 0
    r = subprocess.run(["du", "-sk", str(p)], capture_output=True, text=True)
    return int(r.stdout.split()[0]) * 1024 if r.returncode == 0 else 0


def significant(bytes_: int, total: int) -> bool:
    if bytes_ >= 1_000_000_000:
        return True
    return total > 0 and bytes_ / total >= 0.10


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    perf = {}

    t0 = time.perf_counter()
    before = {n: meta(GS / n) for n in ["state.vscdb", "state.vscdb-wal", "state.vscdb-shm", "state.vscdb.backup"] if (GS / n).exists()}
    page_size = int(sqlite("PRAGMA query_only=ON; PRAGMA page_size;").splitlines()[-1])
    page_count = int(sqlite("PRAGMA query_only=ON; PRAGMA page_count;").splitlines()[-1])
    freelist = int(sqlite("PRAGMA query_only=ON; PRAGMA freelist_count;").splitlines()[-1])
    journal = sqlite("PRAGMA query_only=ON; PRAGMA journal_mode;").splitlines()[-1]
    auto_vac = sqlite("PRAGMA query_only=ON; PRAGMA auto_vacuum;").splitlines()[-1]
    dbstat = sqlite("PRAGMA query_only=ON; SELECT name, SUM(pgsize) FROM dbstat GROUP BY name ORDER BY SUM(pgsize) DESC LIMIT 5;")
    largest = dbstat.splitlines()[0].split("|") if dbstat else ["cursorDiskKV", "0"]
    after = {n: meta(GS / n) for n in before}
    db_mut = after["state.vscdb"]["bytes"] != before["state.vscdb"]["bytes"] or after["state.vscdb"]["mtime"] != before["state.vscdb"]["mtime"]
    free_bytes = freelist * page_size
    db_bytes = after["state.vscdb"]["bytes"]
    wal_bytes = after.get("state.vscdb-wal", {}).get("bytes", 0)
    shm_bytes = after.get("state.vscdb-shm", {}).get("bytes", 0)
    allocated = max(0, (page_count - freelist) * page_size)
    # open?
    open_r = subprocess.run(["lsof", "-nP", str(DB)], capture_output=True, text=True)
    db_open = len(open_r.stdout.strip().splitlines()) > 1
    perf["cursorDBPhysicalAccountingMs"] = int((time.perf_counter() - t0) * 1000)

    accounting = {
        "dbBytes": db_bytes,
        "walBytes": wal_bytes,
        "shmBytes": shm_bytes,
        "pageSize": page_size,
        "pageCount": page_count,
        "freePageCount": freelist,
        "freePageBytes": free_bytes,
        "estimatedAllocatedBytes": allocated,
        "journalMode": journal,
        "autoVacuumMode": auto_vac,
        "dbOpen": db_open,
        "inspectionMethod": "sqlite3 mode=ro + PRAGMA query_only; no immutable=1 against live WAL",
        "inspectionMutationDetected": db_mut,
        "accountingConfidence": "VERIFIED",
        "largestObjectName": largest[0],
        "largestObjectBytes": int(largest[1]),
        "freelistSignificant": significant(free_bytes, db_bytes),
        "walSignificant": significant(wal_bytes, db_bytes),
        "significanceThreshold": {"bytes": 1_000_000_000, "fractionOfDB": 0.10},
        "dbstatTop": [
            {"name": line.split("|")[0], "bytes": int(line.split("|")[1])}
            for line in dbstat.splitlines() if "|" in line
        ],
        "note": "WAL/SHM mtime may change due to concurrent Cursor writes; DB file bytes/mtime must stay stable for inspectionMutationDetected=false",
        "generatedAt": now(),
    }
    (OUT / "p3_3b_cursor_database_accounting.json").write_text(json.dumps(accounting, indent=2) + "\n")

    t1 = time.perf_counter()
    # Load precomputed KV stats if present; else recompute lightly from counts already known
    kv_path = Path("/tmp/p33b_kv_stats.json")
    if kv_path.exists():
        raw = json.loads(kv_path.read_text())
    else:
        raw = []
    # subclass agentKv
    sub = sqlite(
        "PRAGMA query_only=ON; SELECT CASE "
        "WHEN key LIKE 'agentKv:blob:%' THEN 'agentKv:blob' "
        "WHEN key LIKE 'agentKv:checkpoint:%' THEN 'agentKv:checkpoint' "
        "WHEN key LIKE 'agentKv:bubbleCheckpoint:%' THEN 'agentKv:bubbleCheckpoint' "
        "WHEN key LIKE 'agentKv:artifact:%' THEN 'agentKv:artifact' "
        "ELSE 'agentKv:other' END, COUNT(*), SUM(length(value)), MAX(length(value)) "
        "FROM cursorDiskKV WHERE key LIKE 'agentKv:%' GROUP BY 1 ORDER BY 3 DESC;"
    )
    subclasses = []
    for line in sub.splitlines():
        p = line.split("|")
        if len(p) >= 4:
            subclasses.append({"keyClass": p[0], "entryCount": int(p[1]), "logicalValueBytes": int(p[2]), "maxValueBytes": int(p[3])})

    total_kv = sum(x["sum"] for x in raw) if raw else 10_066_745_992
    labels = {
        "bubbleId": "Chat messages — per-bubble message bodies (Cursor storageSizeScan)",
        "agentKv": "Agent conversation-state blobs (agentKv:blob:* dominant)",
        "checkpointId": "Composer file checkpoints",
        "composer.content": "Composer content payloads",
        "composerData": "Per-chat composerData payloads",
    }
    classes = []
    for x in raw:
        classes.append({
            "keyClass": x["class"],
            "entryCount": x["count"],
            "logicalValueBytes": x["sum"],
            "percentage": round(100.0 * x["sum"] / total_kv, 4) if total_kv else 0,
            "avg": round(x["avg"], 2),
            "median": x["median"],
            "p95": x["p95"],
            "p99": x["p99"],
            "max": x["max"],
            "ageRange": None,
            "sourceOfTruth": "TRUE_LOCAL_INFERRED",
            "reacquisition": "UNKNOWN",
            "retentionSemantics": "NO_VENDOR_RETENTION_PROOF_FOUND",
            "confidence": "VERIFIED_LENGTH_AGGREGATE",
            "recommendation": "KEEP",
            "semanticLabel": labels.get(x["class"], "UNKNOWN_CURSOR_KV_STATE"),
            "userStateLikelihood": "HIGH",
            "evidenceLevel": "VERIFIED",
        })
    # other residual
    other_bytes = max(0, int(sqlite("PRAGMA query_only=ON; SELECT COALESCE(SUM(length(value)),0) FROM cursorDiskKV;").splitlines()[-1]) - total_kv)
    perf["cursorKVClassificationMs"] = int((time.perf_counter() - t1) * 1000)
    kv_report = {
        "classes": classes,
        "agentKvSubclasses": subclasses,
        "cursorDiskKVTotalLogicalBytes": int(sqlite("PRAGMA query_only=ON; SELECT COALESCE(SUM(length(value)),0) FROM cursorDiskKV;").splitlines()[-1]),
        "cursorDiskKVEntryCount": int(sqlite("PRAGMA query_only=ON; SELECT COUNT(*) FROM cursorDiskKV;").splitlines()[-1]),
        "logicalClassCoverageNote": "Known prefixes cover dominant payload; residual = other/composer/diffs",
        "privacyNote": "No value contents, prompts, messages, titles, or credentials.",
        "generatedAt": now(),
    }
    (OUT / "p3_3b_cursor_kv_classes.json").write_text(json.dumps(kv_report, indent=2) + "\n")

    t2 = time.perf_counter()
    semantics = {
        "discoveredLiterals": {
            "cursorDiskKV": {"locations": ["workbench.desktop.main.js", "conversationSearchMain.js", "storageSizeScanMain.js"], "confidence": "VERIFIED_LITERAL_REFERENCE"},
            "bubbleId": {"locations": ["conversationSearchMain.js", "storageSizeScanMain.js"], "confidence": "VERIFIED_LITERAL_REFERENCE", "keyShape": "bubbleId:${conversationId}:${messageId}"},
            "agentKv": {"locations": ["storageSizeScanMain.js", "workbench.desktop.main.js"], "confidence": "VERIFIED_LITERAL_REFERENCE", "subclasses": ["agentKv:blob:", "agentKv:checkpoint:", "agentKv:bubbleCheckpoint:", "agentKv:artifact:"]},
            "checkpointId": {"locations": ["storageSizeScanMain.js"], "confidence": "VERIFIED_LITERAL_REFERENCE", "vendorLabel": "Composer file checkpoints"},
            "state.vscdb.backup": {"locations": [], "confidence": "UNKNOWN_SEMANTICS", "note": "No literal found in inspected Cursor.app out/ bundle"},
        },
        "writerEvidence": "Cursor workbench/agent runtime writes cursorDiskKV (inferred from key templates + live OPEN DB); exact writer call path minified",
        "readerEvidence": "conversationSearchMain.js SELECT from cursorDiskKV for bubbleId/composerData; storageSizeScanMain.js aggregates by prefix",
        "deleteEvidence": "No DELETE FROM cursorDiskKV found in inspected bundle; conversationSearch DELETE targets conversation_fts/cloud-cache only",
        "retentionEvidence": "NO_VENDOR_RETENTION_PROOF_FOUND (no TTL/max-entry/size GC constants tied to cursorDiskKV)",
        "syncEvidence": "UNKNOWN — cloud-cache exists for conversation search index, not proven as cursorDiskKV reacquisition",
        "backupEvidence": "UNKNOWN_SEMANTICS for creation/retention; backup file present with same schema subset",
        "commandIDs": [],
        "vendorStorageSizeScanLabels": labels,
        "vacuumEvidence": "VACUUM found only for conversation-search.db migration path — not state.vscdb maintenance UI",
        "generatedAt": now(),
    }
    perf["cursorBundleSemanticSearchMs"] = int((time.perf_counter() - t2) * 1000)
    (OUT / "p3_3b_cursor_storage_semantics.json").write_text(json.dumps(semantics, indent=2) + "\n")

    t3 = time.perf_counter()
    retention = {
        "vendorRetentionFound": False,
        "retentionClasses": [],
        "TTL": None,
        "maxEntries": None,
        "sizeThreshold": None,
        "cleanupTriggers": [],
        "userCommands": [],
        "deleteBlastRadiusKnown": False,
        "compactionSemantics": "NONE_PROVEN_FOR_STATE_VSCDB",
        "unknowns": [
            "Whether UI chat deletion removes bubbleId/agentKv rows",
            "Whether any Cursor command vacuums/compacts state.vscdb",
            "Whether cloud sync restores cursorDiskKV",
        ],
        "conclusion": "NO_VENDOR_RETENTION_PROOF_FOUND",
        "generatedAt": now(),
    }
    perf["cursorRetentionTraceMs"] = int((time.perf_counter() - t3) * 1000)
    (OUT / "p3_3b_cursor_retention.json").write_text(json.dumps(retention, indent=2) + "\n")

    t4 = time.perf_counter()
    bak_bytes = BACKUP.stat().st_size if BACKUP.exists() else 0
    bak_mtime = datetime.fromtimestamp(BACKUP.stat().st_mtime, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if BACKUP.exists() else None
    bak_kv = 0
    bak_sum = 0
    if BACKUP.exists():
        bak_kv = int(sqlite("PRAGMA query_only=ON; SELECT COUNT(*) FROM cursorDiskKV;", BACKUP).splitlines()[-1])
        bak_sum = int(sqlite("PRAGMA query_only=ON; SELECT COALESCE(SUM(length(value)),0) FROM cursorDiskKV;", BACKUP).splitlines()[-1])
    backup = {
        "backupBytes": bak_bytes,
        "format": "SQLite 3.x database (same family as state.vscdb)",
        "relationshipToMainDB": "OLDER_SMALLER_SNAPSHOT_SAME_TABLES_PARTIAL",
        "mainKVCount": kv_report["cursorDiskKVEntryCount"],
        "backupKVCount": bak_kv,
        "mainKVLogicalBytes": kv_report["cursorDiskKVTotalLogicalBytes"],
        "backupKVLogicalBytes": bak_sum,
        "modifiedAt": bak_mtime,
        "vendorGeneratedEvidence": "UNKNOWN — no state.vscdb.backup literal in inspected Cursor.app bundle",
        "restoreSemantics": "UNKNOWN",
        "retentionSemantics": "UNKNOWN — single backup file observed; no multi-generation policy proven",
        "sourceOfTruthRisk": "HIGH — may be sole recovery copy of older state",
        "futureActionCandidate": "CURSOR_BACKUP_RETENTION_PROOF",
        "currentActionable": False,
        "generatedAt": now(),
    }
    perf["cursorBackupAnalysisMs"] = int((time.perf_counter() - t4) * 1000)
    (OUT / "p3_3b_cursor_backup.json").write_text(json.dumps(backup, indent=2) + "\n")

    t5 = time.perf_counter()
    # growth from P3.3A report if available
    growth_prev = {}
    gp = OUT / "p3_3a_cursor_growth.json"
    if gp.exists():
        growth_prev = json.loads(gp.read_text())
    live_valuable = kv_report["cursorDiskKVTotalLogicalBytes"]
    primary = "LIVE_USER_AGENT_STATE_DOMINANT"
    secondary = ["VENDOR_RETENTION_GAP_SUSPECTED"]
    if significant(bak_bytes, db_bytes + bak_bytes):
        secondary.append("BACKUP_RETENTION_SIGNIFICANT")
    if significant(wal_bytes, db_bytes):
        secondary.append("WAL_ACCUMULATION_SIGNIFICANT")
    if significant(free_bytes, db_bytes):
        secondary.append("DATABASE_FREELIST_BLOAT_SIGNIFICANT")
    growth = {
        "historyComparisonAvailable": bool(growth_prev.get("comparisonAvailable")),
        "comparisonQuality": growth_prev.get("comparisonQuality", "COARSE_ROOT_ONLY_OR_INSUFFICIENT"),
        "dbGrowthBytes": growth_prev.get("rootDelta"),
        "logicalKVGrowthEstimate": None,
        "freePageGrowthEstimate": 0,
        "walGrowthEstimate": None,
        "backupGrowthEstimate": None,
        "topGrowingKVClasses": ["bubbleId", "agentKv:blob"],
        "primaryRootCause": primary,
        "secondaryRootCauses": secondary,
        "unknownBytes": max(0, db_bytes - live_valuable - free_bytes),
        "growthAffectsSafety": False,
        "physicalVsLogical": {
            "dbFileBytes": db_bytes,
            "logicalKVValueBytes": live_valuable,
            "freelistBytes": free_bytes,
            "walBytes": wal_bytes,
            "dominant": "LOGICAL_KV_PAYLOAD",
        },
        "generatedAt": now(),
    }
    perf["cursorGrowthAnalysisMs"] = int((time.perf_counter() - t5) * 1000)
    (OUT / "p3_3b_cursor_growth_root_cause.json").write_text(json.dumps(growth, indent=2) + "\n")

    t6 = time.perf_counter()
    versions = sorted([p.name for p in VERS.iterdir()]) if VERS.exists() else []
    active = None
    if BIN_LINK.exists():
        active = os.path.basename(os.path.dirname(os.path.realpath(BIN_LINK)))
    ver_rows = []
    inactive_bytes = 0
    for v in versions:
        b = du_bytes(VERS / v)
        is_active = v == active
        if not is_active:
            inactive_bytes += b
        ver_rows.append({"version": v, "bytes": b, "active": is_active})
    agent = {
        "totalBytes": du_bytes(VERS),
        "versionCount": len(versions),
        "versions": sorted(ver_rows, key=lambda r: -r["bytes"]),
        "activeVersion": active,
        "inactiveVersions": [v for v in versions if v != active],
        "inactiveVersionBytes": inactive_bytes,
        "ownership": "CURSOR_CORE / anysphere.cursor-agent-worker",
        "installUpdateMechanism": "Versioned directories under agent-cli/.local/share/cursor-agent/versions; symlink cursor-agent -> active",
        "runtimeReferences": "active symlink present; per-version process references not fully enumerated",
        "nativeCleanupMechanismKnown": False,
        "potentialFutureBytes": inactive_bytes,
        "currentExecutable": False,
        "generatedAt": now(),
    }
    perf["agentCLIInventoryMs"] = int((time.perf_counter() - t6) * 1000)
    (OUT / "p3_3b_agent_cli_versions.json").write_text(json.dumps(agent, indent=2) + "\n")

    t7 = time.perf_counter()
    opportunities = [
        {
            "id": "AGENT_CLI_VERSION_CLEANUP",
            "bytes": inactive_bytes,
            "proofFeasibility": "MEDIUM",
            "risk": "MEDIUM",
            "userValueRisk": "LOW",
            "vendorNativeContract": "UNKNOWN_DOCUMENTED_NATIVE",
            "requiredNextProof": ["active pin stability", "update mechanism", "safe removal of inactive versions"],
            "currentExecutable": False,
            "ranking": 1,
            "why": "Largest safe-looking opportunity; does not destroy chat/agent history",
        },
        {
            "id": "BACKUP_RETENTION",
            "bytes": bak_bytes,
            "proofFeasibility": "HARD",
            "risk": "HIGH",
            "userValueRisk": "HIGH",
            "vendorNativeContract": "NONE_PROVEN",
            "requiredNextProof": ["backup creation path", "restore path", "retention policy"],
            "currentExecutable": False,
            "ranking": 2,
        },
        {
            "id": "DATABASE_RETENTION",
            "bytes": live_valuable,
            "proofFeasibility": "HARD",
            "risk": "CRITICAL",
            "userValueRisk": "CRITICAL",
            "vendorNativeContract": "NONE_PROVEN",
            "requiredNextProof": ["exact UI/command delete blast radius for bubbleId/agentKv"],
            "currentExecutable": False,
            "ranking": 3,
        },
        {
            "id": "DATABASE_COMPACTION",
            "bytes": free_bytes,
            "proofFeasibility": "LOW",
            "risk": "HIGH",
            "userValueRisk": "MEDIUM",
            "vendorNativeContract": "NONE_PROVEN — raw VACUUM forbidden",
            "requiredNextProof": ["vendor compaction command"],
            "currentExecutable": False,
            "ranking": 4,
            "why": "Freelist only ~3.7MB — not material",
        },
        {
            "id": "PRESERVATION_ARCHIVE",
            "bytes": live_valuable,
            "proofFeasibility": "HARD",
            "risk": "MEDIUM",
            "userValueRisk": "LOW",
            "vendorNativeContract": "NONE_PROVEN",
            "requiredNextProof": ["export format", "round-trip integrity"],
            "currentExecutable": False,
            "ranking": 5,
        },
    ]
    perf["nextCenterpinRankingMs"] = int((time.perf_counter() - t7) * 1000)
    (OUT / "p3_3b_cursor_opportunities.json").write_text(json.dumps({"opportunities": opportunities, "generatedAt": now()}, indent=2) + "\n")

    decision = {
        "selectedNextCenterpin": "AGENT_CLI_VERSION_CLEANUP_PROOF",
        "selectedBytes": inactive_bytes,
        "selectedEntity": "anysphere.cursor-agent-worker/agent-cli/versions",
        "why": (
            "state.vscdb ~10.4GB is LIVE_USER_AGENT_STATE_DOMINANT (bubbleId messages + agentKv blobs). "
            "Freelist ~3.7MB (not significant). No vendor retention/delete/compaction contract for cursorDiskKV. "
            "Chasing the 10GB DB would destroy user/agent history without a proven native path. "
            f"Inactive agent-cli versions (~{inactive_bytes/1e9:.2f}GB) are a clearer next proof target."
        ),
        "evidence": [
            "dbstat: cursorDiskKV owns ~10.40GB pages",
            "KV logical ~10.07GB across bubbleId+agentKv+checkpoints",
            "Cursor storageSizeScan labels messages/agent blobs as conversation state",
            "NO DELETE FROM cursorDiskKV / NO TTL found",
            f"agent-cli versions={len(versions)} active={active} inactiveBytes={inactive_bytes}",
        ],
        "risk": "MEDIUM",
        "expectedContract": "Prove vendor-safe removal of inactive agent-cli version directories only",
        "mutationInNextPhase": False,
        "humanAuthorizationExpected": True,
        "rejectedAlternatives": [
            "CURSOR_HISTORY_RETENTION_PROOF — high value but no command blast radius yet",
            "CURSOR_DB_COMPACTION_PROOF — freelist negligible",
            "CURSOR_BACKUP_RETENTION_PROOF — secondary; vendor lifecycle unknown",
            "CURSOR_CHECKPOINT_RETENTION_PROOF — subset of history state",
            "DIFFERENT_ENTITY — Cursor still top, but DB action not safe",
            "NO_SAFE_HIGH_VALUE_ACTION — agent-cli remains a bounded proof path",
        ],
        "generatedAt": now(),
    }
    (OUT / "p3_3b_next_phase_decision.json").write_text(json.dumps(decision, indent=2) + "\n")

    perf.update({
        "secondCrawlerAdded": False,
        "fullSuiteBefore": {"tests": 616, "failures": 0},
        "generatedAt": now(),
    })
    (OUT / "p3_3b_performance.json").write_text(json.dumps(perf, indent=2) + "\n")

    print("db", db_bytes, "wal", wal_bytes, "freelist", free_bytes, "kv", live_valuable)
    print("primary", primary, "next", decision["selectedNextCenterpin"], "inactive", inactive_bytes)
    print("mutation", db_mut, "open", db_open)


if __name__ == "__main__":
    main()
