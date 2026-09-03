from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260903140000_navision_retention_canonical_observation_repair_20260903.sql"


class NavisionRetentionCanonicalObservationRepairTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.wrapper = cls.sql.split("as $apply$", 1)[1].split("$apply$", 1)[0]

    def test_sparse_legacy_missing_items_are_not_treated_as_presence(self) -> None:
        self.assertIn("left join lateral", self.sql)
        self.assertIn("first_seen.sequence_no as first_sequence", self.sql)
        self.assertIn("coalesce(last_present_sequence,first_sequence-1)", self.sql.replace(" ", ""))
        self.assertIn("pdc_navision_retention_canonical_observations_20260903", self.sql)

    def test_exact_seventh_absence_is_the_first_retirement(self) -> None:
        self.assertIn("<public.pdc_navision_retention_threshold_20260903()", self.sql.replace(" ", ""))
        self.assertIn("'absent_retired'", self.sql)
        self.assertIn("consecutive_absences", self.sql)
        self.assertIn("check(consecutive_absencesbetween0and7)", self.sql.replace(" ", ""))

    def test_current_retained_state_is_reconciled_with_immutable_receipt(self) -> None:
        self.assertIn("pdc_navision_retention_reconciliation_receipts_20260903", self.sql)
        self.assertIn("before_record", self.sql)
        self.assertIn("after_record", self.sql)
        self.assertIn("set is_current=true,record_status='current',missing_since_batch_id=null", self.sql.replace("\n", " ").replace("  ", " "))
        self.assertNotIn("disable trigger user", self.sql)
        self.assertIn("disable trigger navision_record_operational_reconcile", self.sql)
        self.assertIn("disable trigger zz_navision_record_sublet_sync", self.sql)
        self.assertIn("disable trigger zz_navision_all_vehicle_parity_494", self.sql)
        self.assertIn("the future wrapper retains normal", self.sql)
        self.assertIn("pdc_navision_retention_immutable_20260903", self.sql)

    def test_future_wrapper_counts_from_last_actual_presence(self) -> None:
        self.assertIn("max(o.sequence_no)filter(whereo.present_in_update)", self.wrapper.replace(" ", ""))
        self.assertIn("v_sequence-coalesce(v_last_present_sequence,v_first_sequence-1)", self.wrapper.replace(" ", ""))
        self.assertIn("i.classification in('new','changed','unchanged')", self.wrapper)
        self.assertIn("on conflict(batch_id) do nothing", self.wrapper)
        self.assertIn("exact_retention_replay", self.wrapper)
        self.assertIn("record_status='current'", self.wrapper)

    def test_od_and_operational_surfaces_remain_outside_retention_writer(self) -> None:
        self.assertIn("='deliveredatdealer'", self.wrapper.replace(" ", ""))
        self.assertNotIn("update public.navision_board_activations", self.wrapper)
        self.assertNotIn("update public.vehicles", self.wrapper)
        self.assertNotIn("delete from", self.wrapper)

    def test_canonical_readback_validator_and_security_are_rebound(self) -> None:
        self.assertIn("get_pdc_navision_retention_readback_20260903", self.sql)
        self.assertIn("validate_pdc_navision_retention_contract_20260903", self.sql)
        self.assertIn("enable row level security", self.sql)
        self.assertIn("grant select", self.sql)
        self.assertIn("to authenticated", self.sql)
        self.assertIn("project_ref='cdsmnqxtyyoeoznmbidd'", self.sql.replace(" ", ""))
        self.assertIn("pdc_production_environment_sentinel", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
