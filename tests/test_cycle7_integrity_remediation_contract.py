from pathlib import Path
import unittest
from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
M783 = ROOT / "supabase/staging_only/20260830180000_783_historical_observation_digest_repair.sql"
M784 = ROOT / "supabase/staging_only/20260830181000_784_stage_a_integrity_projection.sql"
M785 = ROOT / "supabase/staging_only/20260830182000_785_narrow_authenticated_contracts.sql"
M786 = ROOT / "supabase/staging_only/20260830183000_786_cycle7_contract_repair.sql"
M787 = ROOT / "supabase/staging_only/20260830184000_787_cycle7_contract_version_repair.sql"
M788 = ROOT / "supabase/staging_only/20260830185000_788_canonical_historical_digest_contract.sql"

class Cycle7IntegrityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m783 = M783.read_text(encoding="utf-8").lower()
        cls.m784 = M784.read_text(encoding="utf-8").lower()
        cls.m785 = M785.read_text(encoding="utf-8").lower()
        cls.m786 = M786.read_text(encoding="utf-8").lower()
        cls.m787 = M787.read_text(encoding="utf-8").lower()
        cls.m788 = M788.read_text(encoding="utf-8").lower()

    def test_migrations_parse_and_are_append_only(self):
        self.assertEqual(len(parse_sql(M783.read_text(encoding="utf-8"))), 15)
        self.assertEqual(len(parse_sql(M784.read_text(encoding="utf-8"))), 13)
        for sql in (self.m783, self.m784):
            self.assertIn("lock table supabase_migrations.schema_migrations in exclusive mode", sql)
            self.assertIn("pdc_production_environment_sentinel", sql)
            self.assertIn("pdc_monitor_staging_guard", sql)
            self.assertNotIn("pdc_production_environment_sentinel from", sql)

    def test_historical_request_and_observation_digests_are_distinct(self):
        for marker in ("observation_sha256", "request_sha256,observation_sha256", "v_request_hash,v_observation_sha", "historical_replay_conflict", "pdc_783_observation_replay_conflict"):
            self.assertIn(marker, self.m783)
        self.assertIn("grant execute on function public.submit_pdc_historical_reconciliation_782_base(jsonb) to postgres", self.m783)
        self.assertNotIn("grant execute on function public.submit_pdc_historical_reconciliation_782_base(jsonb) to authenticated", self.m783)

    def test_stage_a_projection_and_pagination_contract(self):
        for marker in ("p.vin", "p.job_card_number", "pdc_sublet_booking_instances", "limit 500) e", "'limit',500", "source_contradiction_review", "actual_duration_minutes"):
            self.assertIn(marker, self.m784)
        self.assertIn("completesqlarray(row.workflow_events", (ROOT / "pdc-ai-auditor-stage-a.js").read_text(encoding="utf-8").lower())
        self.assertIn("const workflowlimit = completeness.workflow_events?.limit === 500 ? 500 : 100", (ROOT / "pdc-ai-auditor-stage-a.js").read_text(encoding="utf-8").lower())

    def test_narrow_authenticated_planner_and_intake_contracts(self):
        for marker in ("get_vehicle_workshop_detail_scoped(uuid,text)", "pdc_auditor_actor_scope", "pdc_auditor_vehicle_dealer", "dealer_scope_denied", "vehicle_not_in_dealer_scope", "grant execute on function public.get_vehicle_workshop_detail_scoped(uuid,text) to authenticated"):
            self.assertIn(marker, self.m785)
        for marker in ("get_pdc_email_intake_status(uuid)", "email_intake_not_in_dealer_scope", "last_error_code", "pdc_auditor_vehicle_dealer", "grant execute on function public.get_pdc_email_intake_status(uuid) to authenticated"):
            self.assertIn(marker, self.m785)
        self.assertNotIn("grant select on public.ai_email_intake", self.m785)
        self.assertNotIn("grant execute on function public.get_vehicle_workshop_detail_scoped(uuid,text) to anon", self.m785)
        app = (ROOT / "app.js").read_text(encoding="utf-8").lower()
        self.assertIn("rpc/get_vehicle_workshop_detail_scoped", app)

    def test_post_review_contract_repair_seals_observations_and_old_rpc(self):
        self.assertEqual(len(parse_sql(M786.read_text(encoding="utf-8"))), 17)
        for marker in ("values('778.1',v_authz.authorization_id", "request_sha256,observation_sha256", "pdc_historical_observation_sha256_unique_786", "alter column observation_sha256 set not null", "revoke all on function public.get_vehicle_workshop_detail(uuid)", "get_vehicle_workshop_detail_scoped(uuid,text)", "pdc_786_historical_postcondition_failed"):
            self.assertIn(marker, self.m786)
        self.assertNotIn("grant execute on function public.get_vehicle_workshop_detail(uuid) to authenticated", self.m786)

    def test_all_historical_contract_versions_match_the_778_table_contract(self):
        self.assertEqual(len(parse_sql(M787.read_text(encoding="utf-8"))), 13)
        function_body = self.m787.split("as $body$", 1)[1].split("revoke all on function", 1)[0]
        self.assertNotIn("'782.1'", function_body)
        for marker in ("'778.1'", "v_request_hash,v_observation_sha", "pdc_787_historical_postcondition_failed", "20260830183000"):
            self.assertIn(marker, self.m787)

    def test_788_recomputes_canonical_request_and_observation_digests(self):
        self.assertEqual(len(parse_sql(M788.read_text(encoding="utf-8"))), 26)
        body = self.m788.split("as $body$", 1)[1].split("revoke all on function public.submit_pdc_historical_reconciliation_782_base", 1)[0]
        for marker in (
            "pdc_historical_canonical_field_788",
            "pdc_historical_canonical_request_788",
            "pdc_historical_canonical_observation_788",
            "canonical_request_utf8",
            "observation_sha256",
            "attachment_ordinal",
            "attachment_kind",
            "attachment_source_hash",
            "observations_jsonb",
            "extraction_jsonb",
            "pdc_788_protected_boundary_drift",
            "pdc_sublet_bookings",
            "pdc_sublet_booking_instances",
            "pdc_pmb_stoppage_receipts_422",
            "monitored_mailboxes",
            "pdc_email_monitor_status",
            "pdc_qc_salesperson_update_outbox_399",
            "pdc_rft_transport_email_outbox_734",
            "pdc_sublet_email_update_receipts",
            "relforcerowsecurity",
            "pdc_788_observation_uniqueness_missing",
            "request_sha256=v_request_hash",
            "observation_sha256=v_observation_sha",
        ):
            self.assertIn(marker, self.m788)
        self.assertNotIn("'782.1'", body)
        self.assertIn("octet_length(convert_to", self.m788)
        self.assertIn("case when p_value is null then '-1:'", self.m788)
        self.assertIn("pdc_788_current_head_guard_failed", self.m788)

if __name__ == "__main__":
    unittest.main(verbosity=2)
