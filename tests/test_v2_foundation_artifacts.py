import hashlib
import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class V2FoundationArtifactTests(unittest.TestCase):
    def load(self, relative):
        with (ROOT / relative).open(encoding="utf-8") as handle:
            return json.load(handle)

    def test_contract_index_is_complete_and_versioned(self):
        index = self.load("contracts/CONTRACT-INDEX.json")
        names = {row["name"] for row in index["contracts"]}
        self.assertEqual(
            names,
            {
                "immutable_evidence",
                "ai_plan",
                "work_taxonomy",
                "action_request",
                "action_result",
                "authoritative_readback",
                "board_projection",
            },
        )
        self.assertEqual(index["environment"], "staging")
        self.assertIn("every_instruction_one_disposition", index["invariants"])

    def test_json_schemas_are_strict_and_have_no_database_escape_fields(self):
        for path in (
            "contracts/immutable-evidence-v1.schema.json",
            "contracts/ai-plan-v1.schema.json",
            "contracts/supabase-action-request-v1.schema.json",
            "contracts/supabase-action-result-v1.schema.json",
            "contracts/authoritative-readback-v1.schema.json",
            "contracts/board-projection-v1.schema.json",
        ):
            schema = self.load(path)
            self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
            self.assertFalse(schema.get("additionalProperties", True))
            serialized = json.dumps(schema).casefold()
            for forbidden in ("service_role", "rls_bypass"):
                self.assertNotIn(forbidden, serialized)
        request = self.load("contracts/supabase-action-request-v1.schema.json")
        self.assertNotIn("rpc", request["properties"])
        self.assertNotIn("table", request["properties"])
        self.assertNotIn("sql", request["properties"])

    def test_taxonomy_handoff_is_bound_and_critical_rules_are_explicit(self):
        taxonomy = self.load("contracts/work-taxonomy-v2.json")
        rules = {row["rule_id"]: row for row in taxonomy["rules"]}
        self.assertEqual(rules["tax-wheel-nut-indicator-set-v1"]["destination"], "TYRE")
        self.assertEqual(rules["tax-fire-extinguisher-hardware-v1"]["destination"], "FABRICATION")
        self.assertEqual(rules["tax-fire-extinguisher-decal-review-v1"]["disposition"], "review")
        self.assertEqual(rules["tax-fmg-signage-decals-review-v1"]["disposition"], "review")
        self.assertEqual(rules["tax-long-ranger-fuel-tank-v1"]["destination"], "HOIST")
        self.assertFalse(taxonomy["historical_board_state_is_authority"])
        self.assertEqual(taxonomy["source_audit"]["coverage"]["operation_occurrences"], 482)

    def test_scenario_catalog_contains_all_owner_scenarios_and_hostile_negatives(self):
        catalog = self.load("fixtures/v2-scenario-catalog-v1.json")
        self.assertEqual(len(catalog["owner_scenarios"]), 14)
        self.assertEqual(len(catalog["hostile_negatives"]), 10)
        self.assertEqual([row["scenario_id"] for row in catalog["owner_scenarios"]], [f"S{i:02d}" for i in range(1, 15)])
        self.assertEqual([row["negative_id"] for row in catalog["hostile_negatives"]], [f"N{i:02d}" for i in range(1, 11)])
        gvm = next(row for row in catalog["owner_scenarios"] if row["scenario_id"] == "S12")
        self.assertIn("workgroup_requirement_set", gvm["expected_action_types"])
        self.assertTrue(all(row["shadow_zero_operational_writes"] for row in catalog["owner_scenarios"]))

    def test_legacy_freeze_hashes_match_frozen_git_bytes(self):
        freeze = self.load("foundation/legacy-freeze-inventory.json")
        self.assertEqual(freeze["freeze_status"], "immutable_rollback_and_evidence_only")
        for relative, record in freeze["frozen_git_artifacts"].items():
            commit = record["source"].split(":", 1)[1]
            result = subprocess.run(
                ["git", "show", f"{commit}:{relative}"],
                cwd=ROOT,
                check=True,
                capture_output=True,
            )
            self.assertEqual(hashlib.sha256(result.stdout).hexdigest(), record["sha256"], relative)
        self.assertFalse(freeze["verification"]["staging_operational_write_attempted"])
        self.assertFalse(freeze["verification"]["production_contacted"])

    def test_artifact_hash_manifest_is_reproducible(self):
        manifest = self.load("foundation/ARTIFACT-HASHES.json")
        for relative, expected in manifest["artifacts"].items():
            with (ROOT / relative).open("rb") as handle:
                self.assertEqual(hashlib.sha256(handle.read()).hexdigest(), expected, relative)
        self.assertEqual(manifest["safety_assertions"]["service_role_used"], False)
        self.assertEqual(manifest["safety_assertions"]["raw_sql_used"], False)
        self.assertEqual(manifest["safety_assertions"]["legacy_business_logic_changed"], False)


if __name__ == "__main__":
    unittest.main()
