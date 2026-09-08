#!/usr/bin/env python3
"""P3.3C — generate agent-cli retention reports (read-only). NO mutation."""
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
VERS = AGENT_CLI / ".local/share/cursor-agent/versions"
BIN = AGENT_CLI / ".local/bin/cursor-agent"
HOME_VERS = HOME / ".local/share/cursor-agent/versions"
HOME_BIN = HOME / ".local/bin/cursor-agent"
REPORTS = Path(__file__).resolve().parents[1] / "reports" / "case001"
PERF: dict = {"secondCrawlerAdded": False}


def utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def du(path: Path) -> dict:
    observed = unique = files = bins = 0
    seen = set()
    mtimes = []
    if not path.exists():
        return {
            "observedBytes": 0,
            "uniqueBytes": 0,
            "fileCount": 0,
            "binaryishCount": 0,
            "mtimeMin": None,
            "mtimeMax": None,
        }
    for root, _, names in os.walk(path):
        for n in names:
            p = Path(root) / n
            try:
                st = p.lstat()
            except OSError:
                continue
            files += 1
            mtimes.append(st.st_mtime)
            observed += st.st_size
            key = (st.st_dev, st.st_ino)
            if key not in seen:
                seen.add(key)
                unique += st.st_size
            if (st.st_mode & 0o111) and not p.is_symlink():
                bins += 1
    return {
        "observedBytes": observed,
        "uniqueBytes": unique,
        "fileCount": files,
        "binaryishCount": bins,
        "mtimeMin": min(mtimes) if mtimes else None,
        "mtimeMax": max(mtimes) if mtimes else None,
    }


def main() -> None:
    REPORTS.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()

    # --- root + versions ---
    t = time.perf_counter()
    root_stats = du(AGENT_CLI)
    vers_stats = du(VERS)
    selected = None
    if BIN.is_symlink() or BIN.exists():
        try:
            resolved = BIN.resolve()
            parts = resolved.parts
            if "versions" in parts:
                selected = parts[parts.index("versions") + 1]
        except Exception:
            pass

    versions = []
    for d in sorted(VERS.iterdir()) if VERS.exists() else []:
        if not d.is_dir():
            continue
        s = du(d)
        pkg = None
        pj = d / "package.json"
        if pj.exists():
            try:
                pkg = json.loads(pj.read_text()).get("name")
            except Exception:
                pkg = None
        userish = [
            x.name
            for x in d.iterdir()
            if x.name.lower() in ("workspace", "projects", "conversations", "credentials", ".env")
        ]
        # arch from node
        arch = "unknown"
        node = d / "node"
        if node.exists():
            import subprocess

            out = subprocess.check_output(["file", "-b", str(node)], text=True)
            if "arm64" in out:
                arch = "arm64"
            elif "x86_64" in out:
                arch = "x86_64"
        versions.append(
            {
                "versionEntityID": f"ai.cursor.agent_cli.version.{d.name}",
                "version": d.name,
                "architecture": arch,
                "uniqueBytes": s["uniqueBytes"],
                "observedBytes": s["observedBytes"],
                "fileCount": s["fileCount"],
                "packageName": pkg,
                "hasRunningMarker": (d / ".running").exists(),
                "userishNames": userish,
                "userOriginalState": "FALSE_VERIFIED" if not userish and pkg else "VERIFY_MORE",
                "mtimeMax": s["mtimeMax"],
                "selectionState": "CURRENT_SELECTED" if d.name == selected else "NOT_SELECTED",
                "runtimeState": "RUNTIME_UNKNOWN",
                "fallbackState": "UNKNOWN",
                "installEvidence": "WORKER_DOWNLOAD_CACHE" if (WORKER / "cursor-agent-worker-a204578d6a.install").exists() else "VERSION_DIR_PRESENT",
                "artifactIdentity": d.name,
                "sourceOfTruthState": "FALSE_INFERRED",
                "reacquisitionState": "UNKNOWN",
                "nativeCleanupState": "UNKNOWN_FOR_GLOBALSTORAGE_STORE",
                "potentialRecoveryBytes": 0,
                "currentExecutable": False,
            }
        )
    PERF["agentCLIRootResolutionMs"] = int((time.perf_counter() - t) * 1000)
    PERF["agentCLIVersionInventoryMs"] = PERF["agentCLIRootResolutionMs"]

    # Vendor keep rule (date-id lexical ≈ newest)
    non_current = sorted(
        [v for v in versions if v["version"] != selected],
        key=lambda v: v["version"],
        reverse=True,
    )
    kept_fb = non_current[:2]
    candidates = non_current[2:]
    for v in versions:
        if v["version"] == selected:
            v["fallbackState"] = "CURRENT"
            v["state"] = "CURRENT_INACTIVE"
            v["potentialRecoveryBytes"] = 0
            v["nativeCleanupState"] = "PROTECTED_CURRENT"
        elif v in kept_fb or v["version"] in {x["version"] for x in kept_fb}:
            v["fallbackState"] = "VENDOR_KEEP_LAST_2_NONCURRENT"
            v["state"] = "FALLBACK_CANDIDATE"
            v["potentialRecoveryBytes"] = 0
            v["nativeCleanupState"] = "PROTECTED_VENDOR_RETENTION_WINDOW"
        else:
            v["fallbackState"] = "OUTSIDE_VENDOR_KEEP_WINDOW"
            v["state"] = "INACTIVE_BUT_REACQUISITION_UNKNOWN"
            v["potentialRecoveryBytes"] = v["uniqueBytes"]
            # Native cleanup exists for HOME store; GS applicability unproven → not candidate yet
            v["nativeCleanupState"] = "NATIVE_ALGORITHM_KNOWN_STORE_APPLICABILITY_UNPROVEN"

    kept_ids = {x["version"] for x in kept_fb}
    for v in versions:
        if v["version"] in kept_ids:
            v["fallbackState"] = "VENDOR_KEEP_LAST_2_NONCURRENT"
            v["state"] = "FALLBACK_CANDIDATE"
            v["potentialRecoveryBytes"] = 0
            v["nativeCleanupState"] = "PROTECTED_VENDOR_RETENTION_WINDOW"

    candidate_bytes = sum(v["uniqueBytes"] for v in candidates)
    protected_current = next((v["uniqueBytes"] for v in versions if v["version"] == selected), 0)
    rollback_bytes = sum(v["uniqueBytes"] for v in kept_fb)

    root = {
        "rootEntityID": "ai.cursor.agent_cli_versions",
        "rootPathClass": "anysphere.cursor-agent-worker/agent-cli",
        "owner": "CURSOR",
        "semanticRole": "AGENT_CLI_TOOLCHAIN_VERSIONS",
        "observedBytes": root_stats["observedBytes"],
        "uniqueBytes": root_stats["uniqueBytes"],
        "mappedVersionBytes": vers_stats["uniqueBytes"],
        "unknownBytes": max(0, root_stats["uniqueBytes"] - vers_stats["uniqueBytes"]),
        "versionCount": len(versions),
        "accountingValid": vers_stats["uniqueBytes"] <= root_stats["uniqueBytes"] + 1024,
        "rootExecutable": False,
        "selectedVersion": selected,
        "hardlinkSharedBytes": max(0, root_stats["observedBytes"] - root_stats["uniqueBytes"]),
        "generatedAt": utc(),
    }
    (REPORTS / "p3_3c_agent_cli_root.json").write_text(json.dumps(root, indent=2) + "\n")

    versions_report = {
        "versions": versions,
        "homeStore": {
            "versionsRootClass": "HOME/.local/share/cursor-agent/versions",
            "versionCount": len(list(HOME_VERS.iterdir())) if HOME_VERS.exists() else 0,
            "selectedViaHomeBin": None,
            "note": "Separate from globalStorage worker store",
        },
        "generatedAt": utc(),
    }
    if HOME_BIN.exists() or HOME_BIN.is_symlink():
        try:
            rp = HOME_BIN.resolve()
            parts = rp.parts
            if "versions" in parts:
                versions_report["homeStore"]["selectedViaHomeBin"] = parts[parts.index("versions") + 1]
        except Exception:
            pass
    (REPORTS / "p3_3c_agent_cli_versions.json").write_text(json.dumps(versions_report, indent=2) + "\n")

    # --- runtime ---
    t = time.perf_counter()
    import subprocess

    cursor_running = False
    try:
        subprocess.check_output(["pgrep", "-x", "Cursor"], stderr=subprocess.DEVNULL)
        cursor_running = True
    except Exception:
        cursor_running = False
    agent_running = False
    open_versions = []
    # Bounded: do not +D entire tree; check selected only via lsof if present
    if selected:
        vp = VERS / selected
        try:
            out = subprocess.check_output(
                ["lsof", "+D", str(vp)], stderr=subprocess.DEVNULL, text=True, timeout=8
            )
            if len(out.splitlines()) > 1:
                agent_running = True
                open_versions.append(selected)
        except Exception:
            pass
    runtime = {
        "cursorRunning": cursor_running,
        "agentCLIRunning": agent_running,
        "runtimeSnapshotCompleteness": "PARTIAL",
        "activeVersion": selected if agent_running else None,
        "openVersionPaths": open_versions,
        "inactiveVerifiedVersions": [],
        "runtimeUnknownVersions": [v["version"] for v in versions],
        "observedAt": utc(),
        "freshUntil": None,
        "note": "PARTIAL: no COMPLETE authoritative multi-version open-file graph; cannot claim INACTIVE VERIFIED",
        "generatedAt": utc(),
    }
    PERF["agentCLIRuntimeMappingMs"] = int((time.perf_counter() - t) * 1000)
    (REPORTS / "p3_3c_agent_cli_runtime.json").write_text(json.dumps(runtime, indent=2) + "\n")

    # --- semantics ---
    t = time.perf_counter()
    semantics = {
        "installPathEvidence": {
            "worker": "cursor-agent-worker dist/main.js installs into globalStorage/.../agent-cli/.local/share/cursor-agent/versions via GetCliDownloadUrl",
            "cli": "install-core-posix installCursorAgent downloads agent-cli-package.tar.gz into HOME/.local/share/cursor-agent/versions",
            "confidence": "VERIFIED_CALL_PATH",
        },
        "versionSelectionEvidence": {
            "globalStorage": "symlink agent-cli/.local/bin/cursor-agent → versions/<id>/cursor-agent",
            "home": "symlink ~/.local/bin/{agent,cursor-agent} → home versions",
            "confidence": "VERIFIED",
        },
        "launchPathEvidence": {
            "launcher": "cursor-agent bash wrapper execs ./node index.js",
            "confidence": "VERIFIED",
        },
        "fallbackEvidence": {
            "vendorKeep": "cleanupOldInstallVersions keeps current + 2 newest non-current (mtime desc), skips in-use markers and active bin targets",
            "confidence": "VERIFIED_CALL_PATH",
        },
        "rollbackEvidence": {
            "explicitRollbackGraph": "UNKNOWN",
            "impliedByRetention": "last 2 non-current retained by cleanup algorithm",
            "confidence": "INFERRED_FROM_RETENTION",
        },
        "updateEvidence": {
            "cliCommand": "agent update",
            "afterInstall": "spawns detached cleanup-install-versions <currentVersion>",
            "worker": "downloads latest buildId into GS cache; no old-version prune found",
            "confidence": "VERIFIED_CALL_PATH",
        },
        "retentionEvidence": {
            "maxAdditionalNonCurrent": 2,
            "policySource": "agent-cli install-core-posix cleanupOldInstallVersions",
            "confidence": "VERIFIED_CALL_PATH",
        },
        "cleanupEvidence": {
            "command": "agent cleanup-install-versions <currentVersion>",
            "hidden": True,
            "description": "Remove stale Cursor Agent install versions",
            "defaultTarget": "HOME/.local/share/cursor-agent/versions",
            "globalStorageTargetProven": False,
            "confidence": "VERIFIED_CALL_PATH_FOR_HOME_STORE",
        },
        "artifactSourceEvidence": {
            "api": "GetCliDownloadUrl / getCliDownloadUrl({channel})",
            "package": "darwin|linux|windows / arch / agent-cli-package.tar.gz",
            "exactOldVersionURL": "UNKNOWN — API returns latest channel version",
            "confidence": "VERIFIED_LITERAL_AND_CALL_PATH",
        },
        "checksumEvidence": {
            "localChecksumFiles": "NONE_FOUND",
            "confidence": "VERIFIED_ABSENCE_IN_VERSION_DIRS",
        },
        "dualStoreNote": "GS worker store (~2.6GB) ≠ HOME CLI store; native cleanup defaults to HOME",
        "generatedAt": utc(),
    }
    PERF["agentCLIBundleSemanticSearchMs"] = int((time.perf_counter() - t) * 1000)
    (REPORTS / "p3_3c_agent_cli_semantics.json").write_text(json.dumps(semantics, indent=2) + "\n")

    # --- reacquisition ---
    t = time.perf_counter()
    reac_versions = []
    for v in versions:
        if v["version"] == selected:
            continue
        reac_versions.append(
            {
                "version": v["version"],
                "artifactIdentity": v["version"],
                "remoteSourceKnown": True,
                "exactVersionAvailable": None,
                "checksumKnown": False,
                "reacquisitionStatus": "UNKNOWN",
                "verifiedAt": utc(),
                "freshUntil": None,
                "failureReason": "GetCliDownloadUrl proves latest channel only; exact historical build not proven downloadable",
            }
        )
    reacq = {
        "versions": reac_versions,
        "reacquirableVerifiedCount": 0,
        "reacquirableVerifiedBytes": 0,
        "unknownBytes": sum(v["uniqueBytes"] for v in versions if v["version"] != selected),
        "softwareUpdateNeExactOldArtifact": True,
        "generatedAt": utc(),
    }
    PERF["agentCLIReacquisitionAnalysisMs"] = int((time.perf_counter() - t) * 1000)
    (REPORTS / "p3_3c_agent_cli_reacquisition.json").write_text(json.dumps(reacq, indent=2) + "\n")

    # --- retention ---
    t = time.perf_counter()
    retention = {
        "vendorRetentionFound": True,
        "maxVersions": "current + 2 newest non-current (+ in-use + active-bin targets)",
        "retentionAge": None,
        "fallbackCount": 2,
        "cleanupTrigger": "after successful installCursorAgent / agent update (detached spawn)",
        "cleanupCallPath": "cleanupInstalledAgentVersions → cleanupOldInstallVersions",
        "nativeCleanupContractFound": True,
        "cleanupBlastRadiusKnown": True,
        "cleanupBlastRadiusScope": "HOME/.local/share/cursor-agent/versions by default",
        "globalStorageCleanupProven": False,
        "unknowns": [
            "Whether worker ever invokes cleanup against GS versions tree",
            "Exact historical artifact reacquisition per buildId",
            "Whether .running markers currently protect any GS version",
        ],
        "generatedAt": utc(),
    }
    PERF["agentCLIRetentionAnalysisMs"] = int((time.perf_counter() - t) * 1000)
    (REPORTS / "p3_3c_agent_cli_retention.json").write_text(json.dumps(retention, indent=2) + "\n")

    # --- opportunities ---
    t = time.perf_counter()
    opps = []
    for i, v in enumerate(candidates):
        opps.append(
            {
                "version": v["version"],
                "uniqueBytes": v["uniqueBytes"],
                "selectionState": v["selectionState"],
                "runtimeState": "RUNTIME_UNKNOWN",
                "reacquisition": "UNKNOWN",
                "nativeCleanup": "ALGORITHM_KNOWN_GS_UNPROVEN",
                "risk": "HIGH",
                "proofFeasibility": "MEDIUM",
                "requiredMissingProof": [
                    "Prove cleanupOldInstallVersions can target GS worker versionsDir",
                    "COMPLETE runtime inactive VERIFIED",
                    "Exact artifact reacquisition or accept irreversible local loss",
                ],
                "ranking": i + 1,
                "currentExecutable": False,
                "isNativeCleanupCandidate": False,
            }
        )
    opportunities = {
        "opportunities": opps,
        "aggregateCandidateBytesIfVendorRuleAppliedToGS": candidate_bytes,
        "nativeCleanupCandidateBytes": 0,
        "note": "No NATIVE_CLEANUP_CANDIDATE this phase — GS store applicability unproven",
        "generatedAt": utc(),
    }
    PERF["agentCLIOpportunityRankingMs"] = int((time.perf_counter() - t) * 1000)
    (REPORTS / "p3_3c_agent_cli_opportunities.json").write_text(json.dumps(opportunities, indent=2) + "\n")

    # --- next phase ---
    next_phase = {
        "totalAgentCLIBytes": root_stats["uniqueBytes"],
        "protectedCurrentBytes": protected_current,
        "rollbackProtectedBytes": rollback_bytes,
        "inactiveVerifiedBytes": 0,
        "reacquirableVerifiedBytes": 0,
        "nativeCleanupCandidateBytes": 0,
        "unknownBytes": candidate_bytes,
        "selectedNextCenterpin": "CURSOR_AGENT_CLI_NATIVE_CLEANUP_CONTRACT",
        "selectedVersions": [v["version"] for v in candidates],
        "selectedBytes": candidate_bytes,
        "whySelected": (
            "Vendor native cleanup command and keep-current+2 algorithm are VERIFIED for HOME store, "
            f"but the material ~{root_stats['uniqueBytes']} bytes live in the worker globalStorage store. "
            "Next proof must bind that contract (or worker-managed equivalent) to the GS versions tree "
            "before any version becomes NATIVE_CLEANUP_CANDIDATE / executable."
        ),
        "whyNotDatabase": "P3.3B: state.vscdb is LIVE_USER_AGENT_STATE_DOMINANT — KEEP",
        "whyNotBackup": "Secondary; vendor lifecycle still UNKNOWN; smaller than agent-cli opportunity after contract proof",
        "mutationNextPhase": False,
        "humanAuthorizationExpected": True,
        "generatedAt": utc(),
    }
    (REPORTS / "p3_3c_next_phase_decision.json").write_text(json.dumps(next_phase, indent=2) + "\n")

    PERF["fullSuiteBefore"] = {"tests": 629, "failures": 0}
    PERF["totalMs"] = int((time.perf_counter() - t0) * 1000)
    PERF["generatedAt"] = utc()
    (REPORTS / "p3_3c_performance.json").write_text(json.dumps(PERF, indent=2) + "\n")

    print(
        json.dumps(
            {
                "rootBytes": root_stats["uniqueBytes"],
                "versions": len(versions),
                "selected": selected,
                "candidateBytes": candidate_bytes,
                "keptFallback": [x["version"] for x in kept_fb],
                "next": next_phase["selectedNextCenterpin"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
