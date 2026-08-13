-- Permit authenticated approved users to receive the non-sensitive online-state
-- revision signal through Supabase Realtime. Operational payload tables remain
-- RPC-only and are never directly replicated.
begin;

drop policy if exists pdc_online_state_revision_read
  on public.pdc_online_state_revision;
create policy pdc_online_state_revision_read
  on public.pdc_online_state_revision
  for select to authenticated
  using (auth.uid() is not null and public.is_pdc_role('viewer'));

grant select on table public.pdc_online_state_revision to authenticated;
revoke all on table public.pdc_online_operational_state,
  public.pdc_online_state_receipts from public, anon, authenticated;

comment on policy pdc_online_state_revision_read
  on public.pdc_online_state_revision is
  'Approved signed-in PDC users may receive only the global revision signal; operational documents remain RPC-only.';

commit;
