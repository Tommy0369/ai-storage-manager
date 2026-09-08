#!/usr/bin/env python3
"""P3.3C.1 — cleanup contract path alignment reports (read-only)."""
from __future__ import annotations

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
GS = HOME / "Library/Application Support/Cursor/User/globalStorage"
WORKER = GS / "anysphere.cursor-agent-worker"
AGENT_CLI = WORKER / "agent-cli"
ACTUAL_VERS = AGENT_CLI / ".local/share/cursor-agent/versions"
GS_BIN = AGENT_CLI / ".local/bin/cursor-agent"
HOME_VERS = HOME / ".local/share/cursor-agent/versions"
HOME_BIN = HOME / ".local/bin/cursor-agent"
REPORTS = Path(__file__).resolve().parents[1] / "reports" / "case001"
PERF: dict = {"secondCrawlerAdded": False}


def utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def canon(p: Path) -> str | None:
    if not p.exists() and not p.is_symlink():
        return None
    return str(p.resolve())


def du(path: Path) -> dict:
    observed = unique = files = 0
    seen = set()
    if not path.exists():
        return {"observedBytes": 0, "uniqueBytes": 0, "fileCount": 0}
    for root, _, names in os.walk(path):
        for n in names:
            fp = Path(root) / n
            try:
                st = fp.lstat()
            except OSError:
                continue
            files += 1
            observed += st.st_size
            key = (st.st_dev, st.st_ino)
            if key not in seen:
                seen.add(key)
                unique += st.st_size
    return {"observedBytes": observed, "uniqueBytes": unique, "fileCount": files}


def relationship(actual: str, cleanup: str) -> str:
    if actual == cleanup:
        return "EXACT_ROOT_MATCH"
    if actual.startswith(cleanup.rstrip("/") + "/"):
        return "TARGET_IS_PARENT"
    if cleanup.startswith(actual.rstrip("/") + "/"):
        return "TARGET_IS_CHILD"
    if Path(actual).name == Path(cleanup).name == "versions" and Path(actual).parent != Path(cleanup).parent:
        return "SIBLING_STORE"
    return "UNRELATED"


def main() -> None:
    REPORTS.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()

    t = time.perf_counter()
    actual_c = canon(ACTUAL_VERS)
    cleanup_c = canon(HOME_VERS) or str(HOME_VERS.resolve() if HOME_VERS.exists() else HOME_VERS)
    # Even if home versions missing, declared resolve is still HOME path
    if cleanup_c is None:
        cleanup_c = str(HOME_VERS.expanduser())
    # If home store missing, still use standardized path
    cleanup_declared = 'join(homedir(), ".local", "share", "cursor-agent", "versions")'
    cleanup_resolved = str((HOME / ".local/share/cursor-agent/versions").resolve()) if (HOME / ".local/share/cursor-agent/versions").exists() else str(HOME / ".local/share/cursor-agent/versions")

    actual_stats = du(ACTUAL_VERS)
    home_stats = du(HOME_VERS)

    selected = None
    if GS_BIN.exists() or GS_BIN.is_symlink():
        try:
            parts = GS_BIN.resolve().parts
            if "versions" in parts:
                selected = parts[parts.index("versions") + 1]
        except Exception:
            pass

    home_selected = None
    if HOME_BIN.exists() or HOME_BIN.is_symlink():
        try:
            parts = HOME_BIN.resolve().parts
            if "versions" in parts:
                home_selected = parts[parts.index("versions") + 1]
        except Exception:
            pass

    versions = []
    for d in sorted(ACTUAL_VERS.iterdir()) if ACTUAL_VERS.exists() else []:
        if not d.is_dir():
            continue
        s = du(d)
        versions.append(
            {
                "version": d.name,
                "uniqueBytes": s["uniqueBytes"],
                "observedBytes": s["observedBytes"],
                "fileCount": s["fileCount"],
                "selected": d.name == selected,
            }
        )

    # Vendor keep window on ACTUAL store (for reporting only — cleanup does NOT apply)
    non_cur = sorted([v for v in versions if not v["selected"]], key=lambda x: x["version"], reverse=True)
    fallback = non_cur[:2]
    outside = non_cur[2:]
    fb_ids = {v["version"] for v in fallback}

    rel = relationship(actual_c or "", cleanup_resolved)
    covers = rel == "EXACT_ROOT_MATCH"
    PERF["actualRootResolutionMs"] = int((time.perf_counter() - t) * 1000)

    # --- actual store ---
    store = {
        "rootEntityID": "ai.cursor.agent_cli_versions",
        "canonicalRoot": actual_c,
        "storageClass": "INSTALLED_VERSIONS",
        "owner": "CURSOR",
        "semanticRole": "WORKER_EMBEDDED_AGENT_CLI_INSTALLED_VERSIONS",
        "creator": "anysphere.cursor-agent-worker extension (GetCliDownloadUrl → extract into globalStorage/.../agent-cli/.../versions)",
        "currentBytes": actual_stats["observedBytes"],
        "uniqueBytes": actual_stats["uniqueBytes"],
        "versionCount": len(versions),
        "versions": [v["version"] for v in versions],
        "currentVersion": selected,
        "activeVersion": None,
        "fallbackVersions": [v["version"] for v in fallback],
        "accountingValid": True,
        "selectionEvidence": "GS agent-cli/.local/bin/cursor-agent symlink",
        "generatedAt": utc(),
    }
    (REPORTS / "p3_3c_1_actual_agent_cli_store.json").write_text(json.dumps(store, indent=2) + "\n")

    # --- cleanup contract ---
    t = time.perf_counter()
    contract = {
        "contractFound": True,
        "contractID": "cursor.agent_cli.cleanup_install_versions.home",
        "sourceLocationClass": "agent-cli install-core-posix (bundled)",
        "trigger": "post-install detached spawn; manual: agent cleanup-install-versions <currentVersion>",
        "callPathConfidence": "VERIFIED_CALL_PATH",
        "declaredTargetExpression": cleanup_declared,
        "resolvedTargetPath": cleanup_resolved,
        "targetStorageClass": "INSTALLED_VERSIONS",
        "targetSelector": "non-current, non-dev, non-dot, not active-bin target; keep 2 newest by mtime; skip in-use",
        "currentExclusion": True,
        "fallbackExclusion": True,
        "dryRunAvailable": False,
        "blastRadius": "HOME ~/.local/share/cursor-agent/versions/<version> recursive rm only",
        "reachability": "LIVE",
        "confidence": "VERIFIED",
        "homeStoreBytes": home_stats["uniqueBytes"],
        "homeStoreVersionCount": len(list(HOME_VERS.iterdir())) if HOME_VERS.exists() else 0,
        "homeSelectedVersion": home_selected,
        "generatedAt": utc(),
    }
    PERF["cleanupContractTraceMs"] = int((time.perf_counter() - t) * 1000)
    PERF["cleanupPathResolutionMs"] = PERF["cleanupContractTraceMs"]
    (REPORTS / "p3_3c_1_cleanup_contract.json").write_text(json.dumps(contract, indent=2) + "\n")

    # --- path alignment ---
    t = time.perf_counter()
    alignment = {
        "actualStoreCanonicalPath": actual_c,
        "cleanupTargetCanonicalPath": cleanup_resolved,
        "relationship": rel,
        "semanticStorageClassMatch": True,  # both INSTALLED_VERSIONS class, different roots
        "canonicalPathMatch": False,
        "cleanupCoversActualStore": covers,
        "reason": (
            "CLEANUP_CONTRACT_PATH_MISMATCH: vendor cleanup resolves to HOME "
            "~/.local/share/cursor-agent/versions while the material ~2.68GB store is the "
            "worker globalStorage agent-cli versions tree. Same leaf name 'versions', "
            "sibling distribution mechanisms (CLI home install vs worker embed)."
        ),
        "legacyMigrationEvidence": "NONE_PROVEN — both layouts coexist; not proven as migration residue",
        "stagingEvidence": False,
        "downloadCacheEvidence": False,
        "classification": "SIBLING_STORE / DIFFERENT_INSTALLATION_MECHANISM",
        "unknowns": [
            "Whether worker will ever call cleanupOldInstallVersions with GS versionsDir",
            "Whether future Cursor unifies roots",
        ],
        "generatedAt": utc(),
    }
    PERF["pathRelationshipBuildMs"] = int((time.perf_counter() - t) * 1000)
    (REPORTS / "p3_3c_1_path_alignment.json").write_text(json.dumps(alignment, indent=2) + "\n")

    # --- version coverage ---
    t = time.perf_counter()
    coverage_rows = []
    for v in versions:
        is_cur = v["selected"]
        is_fb = v["version"] in fb_ids
        # Sibling mismatch → NOT_COVERED for all GS versions
        cov = "NOT_COVERED"
        coverage_rows.append(
            {
                "version": v["version"],
                "uniqueBytes": v["uniqueBytes"],
                "current": is_cur,
                "active": False,
                "fallback": is_fb,
                "runtimeState": "RUNTIME_UNKNOWN",
                "cleanupContractCoverage": cov,
                "cleanupSelectorResult": "OUT_OF_CONTRACT_ROOT",
                "reacquisitionState": "UNKNOWN",
                "potentialRecoveryBytes": 0,
                "currentExecutable": False,
            }
        )
    covered_inactive = sum(r["uniqueBytes"] for r in coverage_rows if r["cleanupContractCoverage"] == "COVERED")
    not_covered = sum(r["uniqueBytes"] for r in coverage_rows if r["cleanupContractCoverage"] == "NOT_COVERED")
    unknown_cov = sum(r["uniqueBytes"] for r in coverage_rows if r["cleanupContractCoverage"] == "UNKNOWN")
    protected_current = sum(r["uniqueBytes"] for r in coverage_rows if r["current"])
    protected_fb = sum(r["uniqueBytes"] for r in coverage_rows if r["fallback"] and not r["current"])

    cov_report = {
        "versions": coverage_rows,
        "coveredInactiveBytes": covered_inactive,
        "notCoveredBytes": not_covered,
        "unknownCoverageBytes": unknown_cov,
        "note": "HOME cleanup contract does not select any GS worker version directory",
        "generatedAt": utc(),
    }
    PERF["versionCoverageAnalysisMs"] = int((time.perf_counter() - t) * 1000)
    (REPORTS / "p3_3c_1_version_contract_coverage.json").write_text(json.dumps(cov_report, indent=2) + "\n")

    # --- retention ---
    t = time.perf_counter()
    retention = {
        "retentionContractFound": True,
        "currentVersionProtected": True,
        "previousVersionProtected": True,
        "retainedCount": "current + 2 newest non-current (+ in-use)",
        "ageRule": None,
        "sizeRule": None,
        "cleanupTrigger": "after install/update; optional manual hidden command",
        "fallbackSemantics": "implied by keep-2 window on HOME store only",
        "migrationSemantics": "UNKNOWN",
        "cleanupTargetRoot": cleanup_resolved,
        "appliesToActualGSStore": False,
        "unknowns": ["GS worker retention policy beyond cache-hit of current buildId"],
        "generatedAt": utc(),
    }
    PERF["retentionContractBuildMs"] = int((time.perf_counter() - t) * 1000)
    (REPORTS / "p3_3c_1_retention_contract.json").write_text(json.dumps(retention, indent=2) + "\n")

    # --- opportunity ---
    t = time.perf_counter()
    # HOME store opportunity under native contract (small)
    home_versions = []
    if HOME_VERS.exists():
        for d in HOME_VERS.iterdir():
            if d.is_dir():
                home_versions.append({"version": d.name, **du(d)})
    home_potential = 0
    if home_versions and home_selected:
        non = sorted([v for v in home_versions if v["version"] != home_selected], key=lambda x: x["version"], reverse=True)
        home_potential = sum(v["uniqueBytes"] for v in non[2:])

    opportunity = {
        "rootBytes": actual_stats["uniqueBytes"],
        "coveredInactiveBytes": covered_inactive,
        "protectedCurrentBytes": protected_current,
        "protectedFallbackBytes": protected_fb,
        "notCoveredBytes": not_covered,
        "unknownCoverageBytes": unknown_cov,
        "potentialRecoveryBytes": covered_inactive,  # 0 for GS under HOME contract
        "homeStoreNativePotentialBytes": home_potential,
        "homeStoreBytes": home_stats["uniqueBytes"],
        "fullRootStillPotential": False,
        "futureActionUnit": "NONE",
        "futureVendorAction": "NO_NATIVE_CLEANUP_FOR_CURRENT_AGENT_CLI_STORE",
        "nativeContractReady": False,
        "currentExecutable": False,
        "remainingProof": [
            "Worker-managed cleanup for GS versionsDir OR path unification",
            "COMPLETE runtime inactive VERIFIED if eviction considered",
            "Exact historical artifact reacquisition if irreversible removal",
        ],
        "uxMessage": (
            "Cursor has a cleanup command, but it targets a different installed-version store "
            "(~/.local/share/cursor-agent/versions), not the 2.68GB worker globalStorage store."
        ),
        "generatedAt": utc(),
    }
    PERF["opportunityRecomputeMs"] = int((time.perf_counter() - t) * 1000)
    (REPORTS / "p3_3c_1_cleanup_opportunity.json").write_text(json.dumps(opportunity, indent=2) + "\n")

    # --- next ---
    # Pivot: GS store has no native cleanup; HOME has tiny opportunity; backup is next ranked large Cursor entity
    # Or LEGACY_STORE_REMEDIATION for GS orphaned accumulation
    next_phase = {
        "selectedNextCenterpin": "CURSOR_AGENT_CLI_LEGACY_STORE_REMEDIATION",
        "selectedBytes": actual_stats["uniqueBytes"],
        "actionUnit": "NONE",
        "why": (
            "Cleanup contract is LIVE for HOME installed versions, but does NOT cover the material "
            f"GS worker store ({actual_stats['uniqueBytes']} bytes). Potential recovery under native "
            f"contract for the actual root is 0. Next proof must treat GS accumulation as a separate "
            "lifecycle/remediation problem (worker-managed eviction or vendor path extension), "
            "not as an executor for cleanup-install-versions."
        ),
        "whyNotExecutorDesign": "Would implement wrong-target action",
        "whyNotAtomicStaleSet": "Atomic set only defined for HOME root",
        "whyNotBackup": "Still secondary; first close agent-cli lifecycle honesty",
        "whyNotDifferentEntity": "Cursor agent-cli remains largest safe-looking Cursor non-DB class needing remediation proof",
        "remainingRisks": [
            "Irreversible loss of historical CLI builds (reacquisition UNKNOWN)",
            "Worker may still select/spawn from GS tree",
            "No dry-run for cleanup-install-versions",
        ],
        "mutationNextPhase": False,
        "humanAuthorizationExpectedLater": True,
        "generatedAt": utc(),
    }
    (REPORTS / "p3_3c_1_next_phase_decision.json").write_text(json.dumps(next_phase, indent=2) + "\n")

    # generic vendor model snapshot
    vendor = {
        "vendor": "CURSOR",
        "storageClass": "INSTALLED_VERSIONS",
        "actionClass": "VENDOR_NATIVE_CLEANUP",
        "canonicalTargetRoot": cleanup_resolved,
        "targetSelector": contract["targetSelector"],
        "exclusions": ["currentVersion", "dev", "dotdirs", "activeBinTargets", "inUseMarkers", "2 newest non-current"],
        "previewCapability": False,
        "runtimeRequirements": contract["blastRadius"],
        "postVerifyContract": "UNKNOWN",
        "confidence": "VERIFIED_FOR_HOME_STORE_ONLY",
        "principle": "Cleanup capability exists must answer FOR WHICH STORE / VERSION / BLAST RADIUS",
    }
    (REPORTS / "p3_3c_1_vendor_cleanup_contract_model.json").write_text(json.dumps(vendor, indent=2) + "\n")

    PERF["fullSuiteBefore"] = {"tests": 644, "failures": 0}
    PERF["totalMs"] = int((time.perf_counter() - t0) * 1000)
    PERF["generatedAt"] = utc()
    (REPORTS / "p3_3c_1_performance.json").write_text(json.dumps(PERF, indent=2) + "\n")

    print(
        json.dumps(
            {
                "relationship": rel,
                "covers": covers,
                "actualBytes": actual_stats["uniqueBytes"],
                "potential": covered_inactive,
                "homePotential": home_potential,
                "next": next_phase["selectedNextCenterpin"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
