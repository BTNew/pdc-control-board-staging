import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SQL_PATH = ROOT / "supabase" / "staging_only" / "135_ai_intake_verified_stock_auto_activation.sql"
RUNTIME_PATH = ROOT / "scripts" / "rehearse_migration_135_runtime.py"
SQL = SQL_PATH.read_text(encoding="utf-8")
LOWER = SQL.lower()
RUNTIME = RUNTIME_PATH.read_text(encoding="utf-8").lower()


class Migration135StaticContractTests(unittest.TestCase):
    def test_staging_predecessor_and_append_only_guards(self):
        self.assertIn("pdc_ai_intake_135_staging_sentinel_mismatch", LOWER)
        self.assertIn("project_ref='cdsmnqxtyyoeoznmbidd'", LOWER)
        self.assertIn("pdc_production_environment_sentinel", LOWER)
        self.assertIn("version='134' and name='navision_preserve_deleted_canonical_identity'", LOWER)
        self.assertIn("pdc_ai_intake_auto_activation_receipts') is not null", LOWER)
        self.assertIn("pdc_ai_intake_auto_backlog_receipts') is not null", LOWER)

    def test_private_core_retained_helper_and_receipts_have_no_client_authority(self):
        self.assertRegex(
            LOWER,
            r"revoke all on function public\.pdc_auto_apply_ai_intake_activation_internal\(uuid,uuid,text,boolean\)\s+from public,anon,authenticated,service_role",
        )
        self.assertRegex(
            LOWER,
            r"revoke all on function public\.submit_pdc_ai_intake_observation_pre135\([\s\S]+?\) from public,anon,authenticated,service_role",
        )
        self.assertRegex(
            LOWER,
            r"grant execute on function public\.submit_pdc_ai_intake_observation\([\s\S]+?\) to authenticated",
        )
        self.assertGreaterEqual(LOWER.count("enable row level security"), 2)
        self.assertIn("revoke all on table public.pdc_ai_intake_auto_activation_receipts", LOWER)
        self.assertIn("revoke all on table public.pdc_ai_intake_auto_backlog_receipts", LOWER)

    def test_actor_authority_is_locked_through_wrapper_and_core(self):
        self.assertGreaterEqual(LOWER.count("from public.pdc_user_roles r"), 3)
        self.assertGreaterEqual(LOWER.count("from public.pdc_monitor_stage_activation_writers w"), 2)
        self.assertGreaterEqual(LOWER.count("for share;"), 5)
        self.assertIn("v_proposal.submitted_by<>p_actor_id", LOWER)
        self.assertIn("v_proposal_id,v_actor_id,lower(btrim(v_actor_email)),false", LOWER)

    def test_provider_source_and_exact_evidence_are_revalidated(self):
        self.assertIn("from public.pdc_email_source_claims c", LOWER)
        self.assertIn("c.contract_name='pdc_ai_intake_063'", LOWER)
        self.assertIn("c.proposal_ref=v_proposal.proposal_id::text", LOWER)
        self.assertIn("proposal_evidence_invalid", LOWER)
        self.assertIn("v_proposal.observations ?& array[", LOWER)
        self.assertIn("resolved_navision_exact", LOWER)
        self.assertIn("gmail_authentication_results", LOWER)
        self.assertIn("v_proposal.observations->'authenticated' is distinct from 'true'::jsonb", LOWER)

    def test_cancellation_and_conflicts_fail_closed_for_primary_and_fan_in(self):
        self.assertIn("jsonb_typeof(v_proposal.observations->'conflicts') is distinct from 'array'", LOWER)
        self.assertIn("v_proposal.observations->'conflicts'<>'[]'::jsonb", LOWER)
        for key in ("cancelled", "canceled", "is_cancelled", "is_canceled"):
            self.assertIn(f"v_proposal.observations ? '{key}'", LOWER)
            self.assertIn(f"q.observations ? '{key}'", LOWER)
        self.assertIn("same_stock_evidence_conflict", LOWER)
        self.assertIn("proposal_conflicted_or_cancelled", LOWER)

    def test_same_stock_primary_lock_and_navision_lock_order(self):
        proposal_lock = LOWER.index("pdc-ai-intake-decision:")
        inbox_lock = LOWER.index("from public.pdc_ai_intake_revision where singleton for update")
        stock_fan_in_lock = LOWER.index("navision-board-activate:ai-intake-auto:")
        fan_in_rows = LOWER.index("perform proposal_id from public.pdc_ai_intake_proposals")
        proposal_row_lock = LOWER.index("where proposal_id=p_proposal_id\n  for update;")
        store_lock = LOWER.index("navision-backend-store")
        revision_lock = LOWER.index("from public.navision_backend_revision where singleton for update")
        identity_table_lock = LOWER.index("lock table public.vehicles,public.vehicle_aliases")
        identity_stock_lock = LOWER.index("vehicle-master:stock_number:")
        self.assertLess(proposal_lock, inbox_lock)
        self.assertLess(inbox_lock, stock_fan_in_lock)
        self.assertLess(stock_fan_in_lock, fan_in_rows)
        self.assertLess(fan_in_rows, proposal_row_lock)
        self.assertLess(proposal_row_lock, store_lock)
        self.assertLess(store_lock, revision_lock)
        self.assertLess(revision_lock, identity_table_lock)
        self.assertLess(identity_table_lock, identity_stock_lock)
        self.assertIn("order by source_received_at desc,submitted_at desc,proposal_id desc", LOWER)
        self.assertIn("superseded_pending_proposal", LOWER)

    def test_fail_closed_lifecycle_identity_and_postcondition_guards(self):
        required = (
            "proposal_expired", "record_changed", "protected_backend_lifecycle",
            "identity_conflict", "operational_identity_conflict", "protected_existing_lifecycle",
            "protected_historical_identity", "vin_conflict_non_authoritative",
            "backend_canonical_identity_conflict", "backend_source_identity_conflict",
            "protected_or_conflicting_activation", "activation_identity_conflict",
            "automatic_activation_failed", "pdc_ai_intake_135_postcondition_failed",
        )
        for token in required:
            self.assertIn(token, LOWER)

    def test_replay_receipt_is_policy_and_immutable_request_bound(self):
        self.assertIn("policy_version text not null check(policy_version='135.1')", LOWER)
        self.assertIn("request_hash text not null unique", LOWER)
        self.assertIn("'fingerprint',v_proposal.fingerprint", LOWER)
        self.assertIn("'backend_record_version',v_proposal.backend_record_version", LOWER)
        self.assertIn("'actor_id',p_actor_id,'actor_email',v_actor_email", LOWER)
        self.assertIn("'allow_current_record_refresh',coalesce(p_allow_current_record_refresh,false)", LOWER)
        self.assertIn("v_receipt.actor_id<>p_actor_id", LOWER)
        self.assertIn("v_receipt.actor_email<>v_actor_email", LOWER)
        self.assertIn("auto_receipt_conflict", LOWER)
        self.assertIn("proposal_id,policy_version,request_hash,source_hash", LOWER)

    def test_backlog_is_exact_preflighted_atomic_and_receipted(self):
        self.assertIn("pdc-ai-intake-auto-backlog:135.1", LOWER)
        self.assertGreaterEqual(LOWER.count("pdc-ai-intake-submit-gate:135.1"), 2)
        backlog_index = LOWER.index("do $backlog$")
        gate_index = LOWER.index("pdc-ai-intake-submit-gate:135.1", backlog_index)
        auto_lock_index = LOWER.index("'pdc-ai-intake-auto:'||v_lock_proposal_id::text", gate_index)
        decision_lock_index = LOWER.index("'pdc-ai-intake-decision:'||v_lock_proposal_id::text", auto_lock_index)
        inbox_drain_index = LOWER.index(
            "perform 1 from public.pdc_ai_intake_revision where singleton for update;", decision_lock_index
        )
        lock_index = LOWER.index("lock table public.pdc_email_source_claims", inbox_drain_index)
        hash_index = LOWER.index("encode(digest(jsonb_agg(jsonb_build_object(", lock_index)
        self.assertLess(gate_index, auto_lock_index)
        self.assertLess(auto_lock_index, decision_lock_index)
        self.assertLess(decision_lock_index, inbox_drain_index)
        self.assertLess(inbox_drain_index, lock_index)
        self.assertLess(lock_index, hash_index)
        for locked_relation in (
            "public.pdc_email_source_claims", "public.pdc_ai_intake_proposals",
            "public.pdc_user_roles", "public.pdc_monitor_stage_activation_writers",
        ):
            self.assertIn(locked_relation, LOWER[lock_index:hash_index])
        self.assertIn("in share mode", LOWER[lock_index:hash_index])
        self.assertIn("v_proposal_count<>28 or v_stock_count<>12", LOWER)
        self.assertIn("bcbf177ae28cb616eb7f671ca8ee4ea82f589cdbcc26fce622737fb92e7df017", LOWER)
        for bound_input in (
            "'submitted_by',p.submitted_by", "'submitted_at',p.submitted_at",
            "'source_received_at',p.source_received_at", "'sender_address',p.sender_address",
            "'authentication',p.authentication", "'observations',p.observations",
            "'subject',p.subject", "'summary',p.summary", "'source_claim'", "'claimed_at',c.claimed_at",
            "'actor_authority'", "'email',r.email", "'writer_active',w.active",
            "'writer_revoked_at',w.revoked_at",
        ):
            self.assertIn(bound_input, LOWER)
        self.assertIn("array_agg(proposal_id order by proposal_id)", LOWER)
        self.assertGreaterEqual(LOWER.count("proposal_id=any(v_input_proposal_ids)"), 3)
        self.assertNotIn("where decision_reason like 'automatically %'", LOWER)
        self.assertIn("pdc_ai_intake_135_backlog_preflight_changed", LOWER)
        self.assertIn("pdc_ai_intake_135_backlog_blocked", LOWER)
        self.assertIn("pdc_ai_intake_135_backlog_postcondition_failed", LOWER)
        self.assertIn("pdc_ai_intake_auto_backlog_receipts", LOWER)
        self.assertIn("'executor','migration_135_staging_ledger_runner'", LOWER)
        self.assertNotIn("raise notice", LOWER)

    def test_audit_history_and_forbidden_email_mutation_surfaces(self):
        self.assertIn("insert into public.navision_backend_audit", LOWER)
        self.assertGreaterEqual(LOWER.count("insert into public.pdc_ai_intake_history"), 4)
        self.assertIn("automatically_closed_duplicate", LOWER)
        forbidden = (
            "insert into public.vehicle_work_items", "update public.vehicle_work_items",
            "insert into public.vehicle_parts_updates", "update public.vehicle_parts_updates",
            "insert into public.workshop_bookings", "update public.workshop_bookings",
        )
        for statement in forbidden:
            self.assertNotIn(statement, LOWER)
        self.assertIn("current navision reconciliation remains location authority", LOWER)
        self.assertIn("'booking_created',false", LOWER)
        self.assertIn("'work_mutated',false", LOWER)
        self.assertIn("'parts_mutated',false", LOWER)

    def test_dynamic_runtime_harness_covers_review_cancel_conflict_success_and_acl(self):
        self.assertIn("review_only", RUNTIME)
        self.assertIn("structured_cancelled", RUNTIME)
        self.assertIn("malformed_conflicts", RUNTIME)
        self.assertIn("clean_activation", RUNTIME)
        self.assertIn("has_function_privilege", RUNTIME)
        self.assertIn("rollback_restored", RUNTIME)
        self.assertIn('"active_activations": 1', RUNTIME)
        self.assertIn('"work_items": 0', RUNTIME)
        self.assertIn('"parts_updates": 0', RUNTIME)
        self.assertIn('"bookings": 0', RUNTIME)

    def test_ledger_identity(self):
        self.assertIn("values('135','ai_intake_verified_stock_auto_activation'", LOWER)
        self.assertTrue(re.search(r"^commit;\s*$", SQL, re.MULTILINE))


if __name__ == "__main__":
    unittest.main()
