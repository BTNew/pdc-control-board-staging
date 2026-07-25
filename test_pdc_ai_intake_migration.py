import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SQL_63 = (ROOT / 'supabase/staging_only/063_pdc_ai_intake_inbox_history.sql').read_text(encoding='utf-8').lower()
SQL_64 = (ROOT / 'supabase/staging_only/064_disable_pdc_ai_intake_decisions.sql').read_text(encoding='utf-8').lower()
SQL_65 = (ROOT / 'supabase/staging_only/065_pdc_ai_intake_admin_decisions.sql').read_text(encoding='utf-8').lower()


class AiIntakeMigrationTests(unittest.TestCase):
    def test_is_staging_only_and_not_in_production_discovery(self):
        for sql in (SQL_63, SQL_64, SQL_65):
            self.assertIn("cdsmnqxtyyoeoznmbidd", sql)
        self.assertFalse(any(p.name.startswith(('063_', '064_', '065_')) for p in (ROOT / 'supabase/migrations').glob('*.sql')))

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


if __name__ == '__main__':
    unittest.main()
