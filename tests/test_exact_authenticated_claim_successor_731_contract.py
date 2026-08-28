import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / 'supabase/staging_only/20260828530000_731_authenticated_exact_claim_successor.sql'
PROCESSOR = ROOT / 'backend/email_intake_processor_successor_20260860.py'


class ExactAuthenticatedClaimSuccessor731Tests(unittest.TestCase):
    def test_sql_is_append_only_exact_actor_claim_and_revokes_legacy_execute(self):
        sql = SQL.read_text(encoding='utf-8').lower()
        for marker in (
            'create or replace function public.claim_pdc_email_intake_authenticated_exact_731(',
            "'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid",
            "'sales@broometoyota.com.au'",
            "'authenticated'",
            "'importer'",
            "'pdc-monitor-staging-sales-uid509-v1'",
            "'pdc-monitor-staging-m502-2026.08.44'",
            "'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'",
            "provider_uid~'^imap_uid:[0-9]+$'",
            "provider_uid<>'imap_uid:514'",
            'revoke all on function public.claim_pdc_email_intake_batch(integer,text) from public,anon,authenticated',
            'grant execute on function public.claim_pdc_email_intake_authenticated_exact_731(integer,text) to authenticated',
            'security definer',
            'source_hash',
        ):
            self.assertIn(marker, sql)
        self.assertNotIn('grant execute on function public.claim_pdc_email_intake_batch(integer,text) to authenticated', sql)
        self.assertNotIn('grant select on public.ai_email_intake', sql)
        self.assertNotIn('grant update on public.ai_email_intake', sql)
        self.assertNotIn('delete from public.ai_email_intake', sql)

    def test_processor_uses_fixed_gateway_and_exact_claim_rpc(self):
        source = PROCESSOR.read_text(encoding='utf-8').lower()
        self.assertIn('claim_pdc_email_intake_authenticated_exact_731', source)
        self.assertIn('pdc-monitor-staging-sales-uid509-v1', source)
        self.assertNotIn('f"pdc-monitor-{os.getpid()}', source)
        self.assertIn('p_gateway_instance_id', source)
        self.assertIn('default=10', source)
        self.assertIn('limit <= 10', source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
