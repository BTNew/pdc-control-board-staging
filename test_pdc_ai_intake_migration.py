import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SQL_63 = (ROOT / 'supabase/staging_only/063_pdc_ai_intake_inbox_history.sql').read_text(encoding='utf-8').lower()
SQL_64 = (ROOT / 'supabase/staging_only/064_disable_pdc_ai_intake_decisions.sql').read_text(encoding='utf-8').lower()
SQL_65 = (ROOT / 'supabase/staging_only/065_pdc_ai_intake_admin_decisions.sql').read_text(encoding='utf-8').lower()
SQL_66 = (ROOT / 'supabase/staging_only/066_pdc_authenticated_email_canonical_import.sql').read_text(encoding='utf-8').lower()
SQL_67 = (ROOT / 'supabase/staging_only/067_pdc_email_vehicle_navision_reconciliation.sql').read_text(encoding='utf-8').lower()


class AiIntakeMigrationTests(unittest.TestCase):
    def test_is_staging_only_and_not_in_production_discovery(self):
        for sql in (SQL_63, SQL_64, SQL_65, SQL_66, SQL_67):
            self.assertIn("cdsmnqxtyyoeoznmbidd", sql)
        self.assertFalse(any(p.name.startswith(('063_', '064_', '065_', '066_', '067_')) for p in (ROOT / 'supabase/migrations').glob('*.sql')))

    def test_monitor_can_submit_observations_but_not_decide(self):
        self.assertIn('submit_pdc_ai_intake_observation', SQL_63)
        self.assertIn("v_role is distinct from 'viewer'", SQL_63)
        self.assertNotIn('grant insert on table public.pdc_ai_intake_proposals', SQL_63)
        self.assertNotIn('grant update on table public.pdc_ai_intake_proposals', SQL_63)
        self.assertNotIn('submit_pdc_ai_intake_observation', SQL_65)

    def test_containment_precedes_replacement_contract(self):
        self.assertIn('drop function public.decide_pdc_ai_intake_proposal', SQL_64)
        self.assertIn('pdc_ai_intake_064_containment_not_active', SQL_65)

    def test_only_typed_board_activation_can_mutate(self):
        self.assertIn("v_action not in ('board_activate_only','review_only')", SQL_65)
        self.assertIn("v_decision='apply' and (v_action<>'board_activate_only'", SQL_65)
        self.assertEqual(SQL_65.count('activate_navision_backend_record('), 1)
        for forbidden in ('insert into public.workshop_bookings', 'insert into public.workshop_work_items', 'update public.vehicles set', 'insert into public.sublet'):
            self.assertNotIn(forbidden, SQL_65)

    def test_decision_is_exact_revision_receipt_and_identity_bound(self):
        for token in (
            'pdc_ai_intake_decision_receipts', 'v_proposal.version<>p_expected_version',
            'v_proposal.fingerprint<>v_fingerprint', 'v_inbox_revision<>p_expected_inbox_revision',
            'v_navision_revision<>p_expected_navision_revision',
            'v_record.version<>v_proposal.backend_record_version', 'cardinality(v_stock_ids)<>1',
            'operational_identity_present', 'activation_identity_conflict', 'already_active',
            'proposal_conflicted_or_cancelled', 'proposal_expired', 'idempotency_conflict',
            'lock table public.vehicles, public.vehicle_aliases in share row exclusive mode',
            "'vehicle-master:stock_number:' || v_proposal.stock_number",
            'pg_advisory_xact_lock',
        ):
            self.assertIn(token, SQL_65)
        board_lock = SQL_65.index("'navision-board-activate:ai-intake:' || p_proposal_id::text")
        store_lock = SQL_65.index("'navision-backend-store'", board_lock)
        activation_call = SQL_65.index('activate_navision_backend_record(', store_lock)
        self.assertLess(board_lock, store_lock)
        self.assertLess(store_lock, activation_call)

    def test_email_is_observation_not_execution_authority(self):
        self.assertIn('p_authentication jsonb', SQL_63)
        self.assertIn("gmail_authentication_results' is distinct from 'true'::jsonb", SQL_63)
        self.assertIn("'email_evidence_authoritative',false", SQL_65)
        self.assertIn("'authorization_basis','authenticated_administrator_decision_and_live_server_identity'", SQL_65)

    def test_exact_active_administrator_and_no_direct_table_authority(self):
        self.assertIn("v_role is distinct from 'administrator'", SQL_65)
        self.assertIn("r.active and r.account_status='approved'", SQL_65)
        self.assertIn('revoke all on table public.pdc_ai_intake_decision_receipts', SQL_65)
        self.assertIn('grant execute on function public.decide_pdc_ai_intake_proposal', SQL_65)

    def test_durable_history_and_realtime_revision(self):
        self.assertIn('create table if not exists public.pdc_ai_intake_history', SQL_63)
        self.assertIn('pdc_ai_intake_revision', SQL_65)
        self.assertIn('insert into public.pdc_ai_intake_history', SQL_65)

    def test_066_chains_observation_to_authenticated_auto_import(self):
        self.assertIn('import_pdc_authenticated_vehicle_email', SQL_66)
        self.assertNotIn('revoke all on function public.submit_pdc_ai_intake_observation', SQL_66)
        for token in (
            "(r.auth_user_id is null or r.auth_user_id=v_actor_id)",
            "r.role='viewer' and r.active and r.account_status='approved'",
            'pdc_monitor_stage_activation_writers',
            "split_part(v_sender,'@',2) not in ('broometoyota.com.au','pmgwa.com.au')",
            "v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb",
            "jsonb_array_length(v_email->'stock_numbers')>1",
            "jsonb_array_length(v_email->'vins')>1",
            "jsonb_array_length(v_email->'stock_numbers')+jsonb_array_length(v_email->'vins')<1",
            "c.contract_name='pdc_ai_intake_063'",
            'pdc_authenticated_email_import_receipts',
            "'source_hash',v_source_hash",
            "'evidence_hash',v_evidence_hash",
            "'evidence_expired'",
            "'evidence_conflicted_or_cancelled'",
            "status='applied'",
            "'authenticated email automatic vehicle/work import'",
        ):
            self.assertIn(token, SQL_66)

    def test_066_serializes_exact_navision_and_operational_identity(self):
        for token in (
            'lock table public.vehicles,public.vehicle_aliases in share row exclusive mode',
            "'vehicle-master:vin:'||v_vin",
            "'vehicle-master:stock_number:'||v_stock",
            "'navision-backend-store'",
            'v_nav_stock_ids is distinct from v_nav_vin_ids',
            'v_operational_stock_ids is distinct from v_operational_vin_ids',
            "r.normalized_data->>'batch'",
            "r.normalized_data->>'vin'",
            "'navision_identity_conflict'",
            "'operational_identity_conflict'",
        ):
            self.assertIn(token, SQL_66)
        self.assertLess(SQL_66.index("'vehicle-master:vin:'||v_vin"), SQL_66.index("'vehicle-master:stock_number:'||v_stock"))

    def test_066_canonical_vehicle_location_activation_and_work_contract(self):
        for token in (
            "'active',true,case when v_record.id is not null then v_location else 'other' end",
            "in ('rft','readyfortransfer')",
            'current_location is deliberately absent',
            "values(v_record.id,'approved_email_build'",
            'insert into public.vehicle_work_items',
            'where not public.vehicle_work_items.completed',
            'insert into public.vehicle_parts_updates',
            'parts_required=true',
            "'completed_work_reopened',false",
            "'booking_created',false",
            'get_pdc_email_vehicle_location_snapshot',
            'pdc_email_vehicle_revision',
        ):
            self.assertIn(token, SQL_66)
        for work_key in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','sublet','pitinspection','parts'):
            self.assertIn(f"when '{work_key}'", SQL_66)
        self.assertNotIn('s.active and s.planner_enabled', SQL_66)
        self.assertNotIn('insert into public.workshop_bookings', SQL_66)
        self.assertNotIn('update public.workshop_bookings', SQL_66)

    def test_067_continuously_enriches_email_cards_from_exact_navision_data(self):
        for token in (
            'reconcile_pdc_email_vehicles_from_navision',
            'pdc_authenticated_email_import_receipts',
            "r.source_system='microsoft_navision'",
            "r.is_current and r.record_status='current'",
            'v_stock_ids[1]<>v_vin_ids[1]',
            'current_location=v_location',
            "source_system='microsoft_navision'",
            "'booking_created',false",
            "'work_changed',false",
            'pdc_email_vehicle_revision',
            'grant execute on function public.reconcile_pdc_email_vehicles_from_navision() to authenticated',
        ):
            self.assertIn(token, SQL_67)
        self.assertNotIn('insert into public.workshop_bookings', SQL_67)
        self.assertNotIn('update public.workshop_bookings', SQL_67)
        self.assertNotIn('insert into public.vehicle_work_items', SQL_67)
        self.assertNotIn('update public.vehicle_work_items', SQL_67)


if __name__ == '__main__':
    unittest.main()
