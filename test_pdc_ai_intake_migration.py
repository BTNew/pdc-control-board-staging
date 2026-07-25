import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SQL = (ROOT / 'supabase/staging_only/063_pdc_ai_intake_inbox_history.sql').read_text(encoding='utf-8').lower()

class AiIntakeMigrationTests(unittest.TestCase):
    def test_is_staging_only_and_not_in_production_discovery(self):
        self.assertIn("project_ref = 'cdsmnqxtyyoeoznmbidd'", SQL)
        self.assertFalse(any(p.name.startswith('063_') for p in (ROOT / 'supabase/migrations').glob('*.sql')))

    def test_monitor_can_submit_observations_but_not_decide(self):
        self.assertIn('submit_pdc_ai_intake_observation', SQL)
        self.assertIn("v_role is distinct from 'viewer'", SQL)
        self.assertIn("v_role is distinct from 'administrator'", SQL)
        self.assertNotIn('grant insert on table public.pdc_ai_intake_proposals', SQL)
        self.assertNotIn('grant update on table public.pdc_ai_intake_proposals', SQL)

    def test_only_typed_board_activation_can_mutate(self):
        self.assertIn("action_type in ('board_activate_only','review_only')", SQL)
        self.assertIn("if v_proposal.action_type<>'board_activate_only'", SQL)
        self.assertEqual(SQL.count('insert into public.navision_board_activations'), 1)
        for forbidden in ('insert into public.workshop_bookings', 'insert into public.workshop_work_items', 'update public.vehicles set', 'insert into public.sublet'):
            self.assertNotIn(forbidden, SQL)

    def test_decision_is_fingerprint_version_and_identity_bound(self):
        self.assertIn('v_proposal.version<>p_expected_version', SQL)
        self.assertIn('v_proposal.fingerprint<>v_fingerprint', SQL)
        self.assertIn('v_record.version<>v_proposal.backend_record_version', SQL)
        self.assertIn('cardinality(v_stock_ids)<>1', SQL)
        self.assertIn('activation_identity_conflict', SQL)

    def test_email_auth_receipt_and_shared_replay_claim_are_server_bound(self):
        self.assertIn('p_authentication jsonb', SQL)
        self.assertIn("gmail_authentication_results' is distinct from 'true'::jsonb", SQL)
        self.assertIn('create table if not exists public.pdc_email_source_claims', SQL)
        self.assertIn('pdc_claim_legacy_stage_activation_source', SQL)
        self.assertIn("'pdc_ai_intake_063'", SQL)
        self.assertIn('source_already_claimed', SQL)

    def test_durable_history_and_realtime_revision(self):
        self.assertIn('create table if not exists public.pdc_ai_intake_history', SQL)
        self.assertIn('pdc_ai_intake_revision', SQL)
        self.assertIn('alter publication supabase_realtime add table public.pdc_ai_intake_revision', SQL)

if __name__ == '__main__':
    unittest.main()
