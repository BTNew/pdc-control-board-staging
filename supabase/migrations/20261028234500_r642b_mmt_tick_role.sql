-- r642b (F257). Staging cdsmnqxtyyoeoznmbidd only. The MMT login's Complete tick is recorded as 'sublet_provider'
-- on the board's sublet tick. Split from r642 because a backup held the table at 18:11 AWST on 28 Oct 2026.
-- Undo: in supabase/rollbacks/20261028233000_r642_mmt_sublet.down.sql
SET LOCAL lock_timeout = '4s';
ALTER TABLE public.pdc_sublet_line_ticks_439 DROP CONSTRAINT pdc_sublet_line_ticks_439_changed_role_check;
ALTER TABLE public.pdc_sublet_line_ticks_439 ADD CONSTRAINT pdc_sublet_line_ticks_439_changed_role_check
  CHECK (changed_role = ANY (ARRAY['operator'::text, 'administrator'::text, 'fitter'::text, 'sublet_provider'::text]));
