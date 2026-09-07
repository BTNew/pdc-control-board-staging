from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts/apply_pilbara_service_operation_classifier_staging.py"


class PilbaraServiceClassifierRunnerContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = RUNNER.read_text(encoding="utf-8")

    def test_runner_is_staging_only_preview_first_and_hash_bound(self) -> None:
        for marker in (
            'STAGING_REF = "cdsmnqxtyyoeoznmbidd"',
            'MODE_CHOICES = ("local-preview", "migrate", "apply-with-rollback-check", "inspect")',
            "validate_manifest",
            "pdc_pilbara_service_classification_preview_v1",
            "pdc_pilbara_service_classification_apply_v1",
            "pdc_pilbara_service_classification_rollback_v1",
            "manifest_hash",
            "preview_batch_id",
        ):
            self.assertIn(marker, self.source)
        self.assertNotIn("vjdtsswhroyguxyfjdkt", self.source)
        self.assertIn("from apply_pdc14_staging import management_write", self.source)
        self.assertIn("management_write(MIGRATION.read_text", self.source)
        self.assertIn("REPAIR_MIGRATION.read_text", self.source)
        self.assertIn("HEAD_REPAIR_MIGRATION.read_text", self.source)
        self.assertIn("ROLLBACK_REPAIR_MIGRATION.read_text", self.source)
        self.assertIn("CLEANUP_REPAIR_MIGRATION.read_text", self.source)
        self.assertIn("20260907111000", self.source)
        self.assertIn("20260907112000", self.source)
        self.assertIn("20260907113000", self.source)
        self.assertIn("20260907114000", self.source)
        self.assertIn("pilbara-classifier-v1r2-preview-initial", self.source)
        self.assertIn('review-evidence/t_d8549cf1/classifier', self.source)
        self.assertIn('_write("authoritative-final-readback.json"', self.source)
        self.assertIn("def _one_privileged(query: str)", self.source)
        self.assertIn("rows = management_write(query)", self.source)
        self.assertIn("return _one_privileged(f\"select public.pdc_pilbara_service_classification_apply_v1", self.source)
        self.assertIn("return _one_privileged(f\"select public.pdc_pilbara_service_classification_rollback_v1", self.source)
        self.assertNotIn("management_query(MIGRATION.read_text", self.source)

    def test_runner_records_replay_rollback_and_forbidden_state_readback(self) -> None:
        for marker in (
            "apply_replay",
            "rolled_back",
            "raw_operations_hash",
            "vehicles_hash",
            "booking_count",
            "completed_work_count",
            "current_classification_count",
            "classification_history_count",
            "work_control_count",
            "quarantine_count",
            "review-evidence/t_d8549cf1/classifier",
        ):
            self.assertIn(marker, self.source)
    def test_representative_totals_use_a_valid_preaggregated_subquery(self) -> None:
        compact = "".join(self.source.lower().split())
        self.assertIn("from(selecth.category,count(*)jobs", compact)
        self.assertIn("groupbyh.categoryorderbyh.category)q)representative_13061263", compact)
        self.assertNotIn("jsonb_build_object('category',h.category,'jobs',count(*)", compact)
        self.assertIn("joinpublic.pdc_pilbara_service_operationsoono.operation_id=c.operation_id", compact)
        self.assertEqual(compact.count("joinpublic.pdc_pilbara_service_operationsousing(operation_id)"), 1)

    def test_retry_recovery_accepts_idempotent_replay_responses(self) -> None:
        compact = "".join(self.source.lower().split())
        self.assertIn("applied.get(\"code\")notin(\"applied\",\"apply_replay\")", compact)
        self.assertIn("rollback.get(\"code\")notin(\"rolled_back\",\"rollback_replay\")", compact)
        self.assertIn("final_apply.get(\"code\")notin(\"applied\",\"apply_replay\")", compact)
        self.assertIn('ifbefore["current_classification_count"]==122', compact)
        self.assertIn('"code":"already_final"', compact)
        self.assertIn('pilbara-classifier-v1r2-verify-final', compact)
        self.assertIn('verification.get("unchanged")!=122', compact)
        self.assertIn('final_apply.get("code")notin("applied","apply_replay")', compact)

    def test_rollback_readback_compares_the_actual_prior_state(self) -> None:
        compact = "".join(self.source.lower().split())
        self.assertIn("after_rollback[key]!=before[key]", compact)
        self.assertNotIn("after_rollback[\"current_classification_count\"]!=0", compact)


if __name__ == "__main__":
    unittest.main(verbosity=2)
