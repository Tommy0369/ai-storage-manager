#!/usr/bin/env python3
"""Build PROVISIONAL reconstructed canonical KB. Does not claim to be Deep Research original."""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPILED = ROOT / "knowledge" / "compiled" / "compiled_rules_v0.1.json"
BOOTSTRAP = ROOT / "knowledge" / "source" / "bootstrap_rules_v0.1.json"
OUT_SRC = ROOT / "knowledge" / "source"
OUT_MANIFEST = ROOT / "knowledge" / "manifests"
OUT_REPORTS = ROOT / "knowledge" / "reports"
OUT_SCHEMA = ROOT / "knowledge" / "schema"
SWIFT_ROOT = ROOT / "Sources" / "SafetyCore" / "Resources" / "knowledge"


def canonical_rule(r: dict) -> dict:
    return {
        "id": r["id"],
        "canonical_name": r.get("entity", r["id"]),
        "category": r.get("category"),
        "subcategory": r.get("subcategory"),
        "path_pattern": r.get("match", {}).get("path"),
        "detection_patterns": [r.get("match", {}).get("path")] if r.get("match", {}).get("path") else [],
        "owning_app_or_system": r.get("subcategory"),
        "purpose": r.get("explanation_ja"),
        "growth_root_causes": r.get("growth_causes", []),
        "default_class": r.get("default_class"),
        "base_score_hint": r.get("base_score"),
        "action_mode": r.get("action_mode"),
        "source_of_truth": r.get("source_of_truth"),
        "regenerable": r.get("regenerable"),
        "required_predicates": r.get("required_predicates", []),
        "green_if": r.get("required_predicates", []) if r.get("default_class") == "GREEN" else [],
        "yellow_if": r.get("demote_to_yellow_if", []),
        "red_if": r.get("demote_to_red_if", []),
        "hard_block_if": r.get("hard_block_if", []),
        "deletion_preconditions": r.get("required_predicates", []),
        "deletion_effects": r.get("effects", []),
        "regeneration_behavior": "regenerable" if r.get("regenerable") else "not_regenerable",
        "user_data_loss_risk": "high" if r.get("source_of_truth") or r.get("default_class") in ("RED",) else "low",
        "active_use_detection": [
            p for p in r.get("required_predicates", [])
            if "process" in p or "handle" in p or "open" in p
        ],
        "age_signals": [],
        "recovery_estimation": r.get("recovery_estimate_hint"),
        "native_cleanup_method": r.get("native_cleanup"),
        "explanation_ja": r.get("explanation_ja"),
        "technical_rationale": r.get("reason_codes", []),
        "verify_after": r.get("verification", []),
        "source_codes": ["compiled_rules_v0.1", "spec_expansion_and_bootstrap"],
        "source_quality": "PROVISIONAL_RECONSTRUCTION",
        "edge_cases": [],
        "confidence": "low" if r.get("default_class") == "UNKNOWN" else "medium",
        "rule_version": r.get("rule_version") or "0.1",
        "verification_status": "RESEARCH_SUPPORTED",
        "engine_dsl": {
            "match": r.get("match"),
            "evaluation_layer": r.get("evaluation_layer"),
            "network_required": r.get("network_required"),
        },
        "tested_on": [],
    }


def main() -> None:
    compiled = json.loads(COMPILED.read_text())
    rules = compiled["rules"]
    assert len(rules) == 178, len(rules)
    ids = [r["id"] for r in rules]
    assert len(ids) == len(set(ids))

    dist = Counter(r["default_class"] for r in rules)
    bootstrap_ids = {r["id"] for r in json.loads(BOOTSTRAP.read_text())["rules"]} if BOOTSTRAP.exists() else set()

    doc = {
        "knowledge_base": {
            "name": "AI Storage Manager Storage Safety Knowledge Base",
            "version": "0.1-reconstructed",
            "record_count": 178,
            "provenance": "reconstructed_from_compiled_rules_and_deep_research_report",
            "original_source_artifact_available": False,
            "canonical_status": "PROVISIONAL",
            "requires_rule_verification": True,
            "not_the_deep_research_original": True,
        },
        "class_distribution": dict(dist),
        "rules": [canonical_rule(r) for r in rules],
    }

    OUT_SRC.mkdir(parents=True, exist_ok=True)
    OUT_MANIFEST.mkdir(parents=True, exist_ok=True)
    OUT_REPORTS.mkdir(parents=True, exist_ok=True)
    OUT_SCHEMA.mkdir(parents=True, exist_ok=True)

    recon_path = OUT_SRC / "storage_safety_knowledge_base_v0.1-reconstructed.json"
    recon_path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")

    manifest = {
        "original_deep_research_kb": {
            "known_to_have_existed": True,
            "available": False,
            "record_count": 178,
            "class_distribution": {"GREEN": 47, "YELLOW": 58, "RED": 61, "UNKNOWN": 12},
            "artifact_filename": "storage_safety_knowledge_base_v0.1.json",
        },
        "current_kb": {
            "type": "RECONSTRUCTED",
            "canonical_status": "PROVISIONAL",
            "record_count": 178,
            "class_distribution": dict(dist),
            "path": str(recon_path.relative_to(ROOT)),
            "compiled_path": "knowledge/compiled/compiled_rules_v0.1.json",
            "bootstrap_rule_count": len(bootstrap_ids),
        },
        "distribution_delta_vs_original_report": {
            "GREEN": dist["GREEN"] - 47,
            "YELLOW": dist["YELLOW"] - 58,
            "RED": dist["RED"] - 61,
            "UNKNOWN": dist["UNKNOWN"] - 12,
            "note": "Reconstructed from compiled+spec expansion. Do not treat as original Deep Research JSON.",
        },
    }
    (OUT_MANIFEST / "knowledge_base_v0.1_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")

    (OUT_REPORTS / "reconstruction_diff_report.md").write_text(
        "\n".join([
            "# Reconstruction diff",
            "",
            "Original Deep Research artifact: **unavailable**.",
            "This file is **not** a substitute original.",
            "",
            f"Compiled/reconstructed count: {len(rules)}",
            f"Class distribution reconstructed: {dict(dist)}",
            "Original reported distribution: GREEN 47, YELLOW 58, RED 61, UNKNOWN 12",
            "",
            f"Bootstrap ids preserved: {len(bootstrap_ids)}",
            "Compiled rules were not deleted.",
            "",
        ])
    )
    (OUT_REPORTS / "verification_status.md").write_text(
        "\n".join([
            "# Verification status",
            "",
            "All 178 reconstructed rules: `RESEARCH_SUPPORTED`.",
            "None are `REAL_MAC_VERIFIED` until Case Study #001 predicate-complete evidence exists.",
            "One machine PASS does not generalize.",
            "",
        ])
    )
    (OUT_SCHEMA / "safety_knowledge_base.schema.json").write_text(json.dumps({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "Reconstructed Safety Knowledge Base",
        "type": "object",
        "required": ["knowledge_base", "rules"],
        "properties": {
            "knowledge_base": {
                "type": "object",
                "required": ["original_source_artifact_available", "canonical_status", "record_count"],
            },
            "rules": {"type": "array", "minItems": 178, "maxItems": 178},
        },
    }, indent=2) + "\n")

    # Mirror under Swift resources without removing existing compiled_rules_v0.1.json
    for rel, src in [
        ("source/storage_safety_knowledge_base_v0.1-reconstructed.json", recon_path),
        ("manifests/knowledge_base_v0.1_manifest.json", OUT_MANIFEST / "knowledge_base_v0.1_manifest.json"),
        ("reports/reconstruction_diff_report.md", OUT_REPORTS / "reconstruction_diff_report.md"),
        ("reports/verification_status.md", OUT_REPORTS / "verification_status.md"),
        ("schema/safety_knowledge_base.schema.json", OUT_SCHEMA / "safety_knowledge_base.schema.json"),
        ("compiled/compiled_rules_v0.1.json", COMPILED),
    ]:
        dest = SWIFT_ROOT / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(src.read_bytes())

    print(json.dumps({"reconstructed": 178, "distribution": dict(dist), "original_available": False}, indent=2))


if __name__ == "__main__":
    main()
