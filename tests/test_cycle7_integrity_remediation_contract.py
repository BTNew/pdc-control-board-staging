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
M789 = ROOT / "supabase/staging_only/20260830190000_789_historical_proposal_binding_successor.sql"
M790 = ROOT / "supabase/staging_only/20260830191000_790_historical_proposal_conflict_wrapper.sql"
M791 = ROOT / "supabase/staging_only/20260830192000_791_historical_manifest_compatibility_successor.sql"
M792 = ROOT / "supabase/staging_only/20260830193000_792_historical_vehicle_identity_successor.sql"
M793 = ROOT / "supabase/staging_only/20260830200000_793_historical_proposal_review_successor.sql"
M795 = ROOT / "supabase/staging_only/20260830202000_795_historical_wrapper_short_name_repair.sql"

class Cycle7IntegrityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m783 = M783.read_text(encoding="utf-8").lower()
        cls.m784 = M784.read_text(encoding="utf-8").lower()
        cls.m785 = M785.read_text(encoding="utf-8").lower()
        cls.m786 = M786.read_text(encoding="utf-8").lower()
        cls.m787 = M787.read_text(encoding="utf-8").lower()
        cls.m788 = M788.read_text(encoding="utf-8").lower()
        cls.m789 = M789.read_text(encoding="utf-8").lower()
        cls.m790 = M790.read_text(encoding="utf-8").lower()
        cls.m791 = M791.read_text(encoding="utf-8").lower()
        cls.m792 = M792.read_text(encoding="utf-8").lower()
        cls.m793 = M793.read_text(encoding="utf-8").lower()
        cls.m795 = M795.read_text(encoding="utf-8").lower()

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

    def test_789_proposal_binding_successor_contract(self):
        self.assertEqual(len(parse_sql(M789.read_text(encoding="utf-8"))), 24)
        sql = self.m789

    def test_790_typed_conflict_wrapper_successor_contract(self):
        self.assertEqual(len(parse_sql(M790.read_text(encoding="utf-8"))), 13)
        for marker in (
            "20260830190000,789_historical_proposal_binding_successor",
            "pdc_790_current_head_guard_failed",
            "historical_proposal_tuple_conflict",
            "historical_proposal_payload_conflict",
            "v_existing_proposal",
            "limit 1 for update",
            "submit_pdc_historical_reconciliation_789_proposal_binding_base",
            "has_function_privilege('anon'",
            "historical_proposal_conflict_wrapper",
        ):
            self.assertIn(marker, self.m790)

    def test_791_manifest_compatibility_successor_contract(self):
        self.assertEqual(len(parse_sql(M791.read_text(encoding="utf-8"))), 16)
        for marker in (
            "20260830191000,790_historical_proposal_conflict_wrapper",
            "pdc_791_current_head_guard_failed",
            "v_manifest_text",
            "to_jsonb(m->>''content_type'')",
            "submit_pdc_historical_reconciliation_791_manifest_compatibility_base",
            "historical_proposal_tuple_conflict",
            "pdc_791_postcondition_failed",
            "pdc_historical_proposal_bindings_789",
        ):
            self.assertIn(marker, self.m791)

    def test_792_deterministic_vehicle_identity_successor_contract(self):
        self.assertEqual(len(parse_sql(M792.read_text(encoding="utf-8"))), 16)
        for marker in (
            "20260830192000,791_historical_manifest_compatibility_successor",
            "pdc_792_current_head_guard_failed",
            "select count(*) into v_attachment_count",
            "order by v.id limit 1",
            "pdc_782_identity_conflict",
            "submit_pdc_historical_reconciliation_792_vehicle_identity_successor",
            "historical_proposal_tuple_conflict",
            "pdc_792_postcondition_failed",
        ):
            self.assertIn(marker, self.m792)
        body = self.m792.split("as $body$", 1)[1].split("revoke all on function public.submit_pdc_historical_reconciliation_792_vehicle_identity_successor", 1)[0]
        self.assertNotIn("max(v.id)", body)

    def test_793_pending_proposal_review_successor_contract(self):
        self.assertEqual(len(parse_sql(M793.read_text(encoding="utf-8"))), 24)
        for marker in (
            "20260830193000,792_historical_vehicle_identity_successor",
            "pdc_793_current_head_guard_failed",
            "pdc_historical_proposal_compatibility_reviews_793",
            "historical_proposal_observation_review_required",
            "v_parent_result->>''code''=''already_noticed''",
            "on conflict(proposal_id,request_sha256) do nothing",
            "pdc_793_proposal_review_immutable",
            "pdc_793_postcondition_failed",
            "submit_pdc_historical_reconciliation_793_proposal_review_successor",
        ):
            self.assertIn(marker, self.m793)
        self.assertNotIn("update public.pdc_ai_intake_proposals", self.m793)
        self.assertNotIn("delete from public.pdc_ai_intake_proposals", self.m793)

    def test_795_wrapper_short_name_repair_contract(self):
        self.assertEqual(len(parse_sql(M795.read_text(encoding="utf-8"))), 13)
        wrapper = self.m795.split("create or replace function public.submit_pdc_historical_reconciliation_778", 1)[1].split("revoke all on function public.submit_pdc_historical_reconciliation_778", 1)[0]
        for marker in (
            "20260830200000,793_historical_proposal_review_successor",
            "pdc_795_current_head_guard_failed",
            "submit_pdc_historical_reconciliation_793_proposal_review_succes",
            "historical_proposal_tuple_conflict",
            "limit 1 for update",
            "p_request->",
            "pdc_795_postcondition_failed",
        ):
            self.assertIn(marker, self.m795)
        self.assertNotIn("v_request->", wrapper)

if __name__ == "__main__":
    unittest.main(verbosity=2)
