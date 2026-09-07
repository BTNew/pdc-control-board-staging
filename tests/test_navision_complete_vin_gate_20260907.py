from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260907090000_navision_complete_vin_gate.sql"
APP = (ROOT / "app.js").read_text(encoding="utf-8")
INDEX = (ROOT / "index.html").read_text(encoding="utf-8")


class NavisionCompleteVinGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.compact = "".join(cls.sql.split())

    def test_browser_parser_uses_existing_vin_normalizer_for_components(self) -> None:
        self.assertIn("const vinSource = `${wmi}${vdsNumber}${frame}`.toUpperCase().replace(/[\\s-]+/g, '');", APP)
        self.assertIn("const normalizedVin = normalizeVin(vinSource);", APP)
        self.assertIn("const vin = vinSource.length === 17 && normalizedVin === vinSource ? normalizedVin : '';", APP)
        self.assertNotIn("const vin = `${wmi}${vdsNumber}${frame}`;", APP)
        self.assertNotIn("getNavisionValue(row, headerMap, 'WMI').replace(/\\s+/g, '')", APP)
        self.assertIn("navision-complete-vin=2026.09.07.0900", INDEX)

    def test_effective_vin_reuses_canonical_normalize_and_valid_contract(self) -> None:
        self.assertIn("pdc_navision_complete_vin_20260907", self.sql)
        self.assertIn("public.normalize_vehicle_vin", self.sql)
        self.assertIn("public.is_valid_vehicle_vin", self.sql)
        self.assertIn("p_data->>'wmi'", self.compact)
        self.assertIn("p_data->>'vdsnumber'", self.compact)
        self.assertIn("p_data->>'frame'", self.compact)

    def test_partial_invalid_and_prohibited_values_are_null(self) -> None:
        for marker in (
            "partial_wmi_vds_frame_must_be_null",
            "invalid_character_vin_must_be_null",
            "prohibited_i_vin_must_be_null",
            "prohibited_o_vin_must_be_null",
            "prohibited_q_vin_must_be_null",
            "legacy_short_vin_must_be_null",
        ):
            self.assertIn(marker, self.sql)
        self.assertIn("length(vin)=17", self.compact)

    def test_complete_valid_vin_is_kept_and_complete_duplicates_are_blocked(self) -> None:
        self.assertIn("complete_vin_must_be_preserved", self.sql)
        self.assertIn("duplicate_complete_vin_must_block", self.sql)
        self.assertIn("count(*)filter(wheres.vinisnotnull)over(partitionbys.vin)", self.compact)
        self.assertIn("whene.vin_count>1then'duplicate_vin'", self.compact)

    def test_normalized_projection_is_gated_but_raw_components_are_preserved(self) -> None:
        self.assertIn("create or replace function public.navision_backend_normalize_row", self.sql)
        self.assertIn("jsonb_set", self.sql)
        self.assertIn("raw_component_preservation_failed", self.sql)
        self.assertIn("raw_evidence", self.sql)
        self.assertNotIn("update public.navision_backend_records set raw_evidence", self.sql)

    def test_sibling_identity_and_reconciliation_paths_share_the_gate(self) -> None:
        self.assertIn("create or replace function public.navision_backend_candidate_vehicle_ids", self.sql)
        self.assertIn("create or replace function public.navision_import_candidate_preflight_770", self.sql)
        self.assertIn("create or replace function public.pdc_navision_effective_vin_471", self.sql)
        self.assertIn("pdc_navision_complete_vin_20260907", self.sql)

    def test_staging_rls_and_production_separation_are_preserved(self) -> None:
        self.assertIn("project_ref='cdsmnqxtyyoeoznmbidd'", self.compact)
        self.assertIn("to_regclass('public.pdc_production_environment_sentinel')isnotnull", self.compact)
        self.assertIn("revoke all on function", self.sql)
        self.assertNotIn("vjdtsswhroyguxyfjdkt", self.sql)
        self.assertNotIn("disable row level security", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
