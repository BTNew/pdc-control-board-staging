from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260903133000_navision_seven_update_retention_ledger_20260903.sql"


class NavisionSevenUpdateRetentionLedgerContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.wrapper = cls.sql.split("as $apply$", 1)[1].split("$apply$", 1)[0]

    def test_dealer_scoped_applicable_update_ledger_is_append_only(self) -> None:
        self.assertIn("pdc_navision_applicable_updates_20260903", self.sql)
        self.assertIn("unique(batch_id)", self.sql.replace(" ", ""))
        self.assertIn("unique(source_system,dealer_code,sequence_no)", self.sql.replace(" ", ""))
        self.assertIn("status='applied'", self.sql.replace(" ", ""))
        self.assertIn("pdc_navision_retention_immutable_20260903", self.sql)
        self.assertIn("before update or delete", self.sql)

    def test_every_record_gets_immutable_per_update_observation(self) -> None:
        self.assertIn("pdc_navision_retention_observations_20260903", self.sql)
        self.assertIn("consecutive_absences", self.sql)
        self.assertIn("absent_retained", self.sql)
        self.assertIn("absent_retired", self.sql)
        self.assertIn("delivered_at_dealer", self.sql)
        self.assertIn("primarykey(source_system,dealer_code,sequence_no,backend_record_id)", self.sql.replace(" ", ""))

    def test_replay_does_not_allocate_a_second_sequence_or_observation(self) -> None:
        self.assertIn("on conflict(batch_id) do nothing", self.wrapper)
        self.assertIn("exact_retention_replay", self.wrapper)
        self.assertIn("if not v_new_update then", self.wrapper)

    def test_first_six_absences_restore_full_canonical_visibility(self) -> None:
        self.assertIn("v_consecutive_absences<7", self.wrapper.replace(" ", ""))
        self.assertIn("set is_current=true,record_status='current',missing_since_batch_id=null", self.wrapper.replace("\n", " ").replace("  ", " "))
        self.assertIn("pdc_navision_retain_after_absence_count_20260903", self.wrapper)

    def test_seventh_absence_retires_but_exact_od_remains_terminal(self) -> None:
        self.assertIn("='deliveredatdealer'", self.wrapper.replace(" ", ""))
        self.assertIn("'delivered_at_dealer'", self.wrapper)
        self.assertIn("'absent_retired'", self.wrapper)
        self.assertIn("pdc_navision_retention_threshold_20260903", self.sql)

    def test_retention_never_mutates_board_vehicle_or_deletes_history(self) -> None:
        self.assertNotIn("update public.navision_board_activations", self.wrapper)
        self.assertNotIn("update public.vehicles", self.wrapper)
        self.assertNotIn("delete from", self.wrapper)
        self.assertIn("backend_only_retention", self.wrapper)
        self.assertIn("board_lifecycle_mutated_by_retention", self.wrapper)

    def test_exact_readback_rls_and_staging_only_guards_exist(self) -> None:
        self.assertIn("get_pdc_navision_retention_readback_20260903", self.sql)
        self.assertIn("validate_pdc_navision_retention_contract_20260903", self.sql)
        self.assertIn("project_ref='cdsmnqxtyyoeoznmbidd'", self.sql.replace(" ", ""))
        self.assertIn("pdc_production_environment_sentinel", self.sql)
        self.assertIn("enable row level security", self.sql)
        self.assertIn("grant select", self.sql)
        self.assertIn("to authenticated", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
