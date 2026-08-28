import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / 'supabase/staging_only/20260828540000_732_bounded_authenticated_exact_claim_successor.sql'
PROCESSOR = ROOT / 'backend/email_intake_processor_successor_20260861.py'


class BoundedExactClaimSuccessor732Tests(unittest.TestCase):
    def test_sql_binds_731_hash_excludes_synthetic_uids_and_revokes_predecessors(self):
        sql = SQL.read_text(encoding='utf-8').lower()
        for marker in (
            'create or replace function public.claim_pdc_email_intake_authenticated_exact_732(',
            'a7cd82b4ab1ba1629f9d7466a6bd06657ac5a068dbe67512640ec61869e52513',
            'provider_uid~\'^imap_uid:[0-9]+$\'',
            '100000',
            "provider_uid<>'imap_uid:514'",
            'claim_token=gen_random_uuid()',
            'queue_attempts=queue_attempts+1',
            'source_hash',
            'revoke all on function public.claim_pdc_email_intake_batch(integer,text)',
            'revoke all on function public.claim_pdc_email_intake_authenticated_exact_731(integer,text)',
            'grant execute on function public.claim_pdc_email_intake_authenticated_exact_732(integer,text) to authenticated',
            "'20260828540000'",
        ):
            self.assertIn(marker, sql)
        self.assertNotIn('grant execute on function public.claim_pdc_email_intake_batch(integer,text) to authenticated', sql)
        self.assertNotIn('grant execute on function public.claim_pdc_email_intake_authenticated_exact_731(integer,text) to authenticated', sql)
        self.assertNotIn('grant update on public.ai_email_intake', sql)
        self.assertNotIn('grant select on public.ai_email_intake', sql)

    def test_processor_is_fixed_scope_and_ambiguous_mail_is_review_only(self):
        source = PROCESSOR.read_text(encoding='utf-8').lower()
        self.assertIn('claim_pdc_email_intake_authenticated_exact_732', source)
        self.assertIn('exact_gateway_instance_id = "pdc-monitor-staging-sales-uid509-v1"', source)
        self.assertIn('default=10', source)
        self.assertIn('code": "review_required"', source)
        self.assertIn('request_payload = canonical_jobcard_request', source)
        self.assertNotIn('f"pdc-monitor-{os.getpid()}', source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
