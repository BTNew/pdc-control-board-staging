-- Undo r389: restore workshop_read_vehicle_allowed_20261013 to md5 56ff1f82635ec4161a492db79fc23255
-- (pg_get_functiondef), the definition before 20 Oct 2026. Staging cdsmnqxtyyoeoznmbidd only.
DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF md5(pg_get_functiondef('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)'::regprocedure)) IS DISTINCT FROM 'f381b46c18302045ff362abd92d7178c' THEN
    RAISE EXCEPTION 'workshop_read_vehicle_allowed_not_r389';
  END IF;
END $guard$;
-- The live body uses CRLF line ends; EXECUTE restores them so the stored function
-- keeps the same bytes as before apart from the changed line (SQL clients strip CR).
DO $apply$
BEGIN
  EXECUTE replace($def$CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(p_scope jsonb, p_vehicle_id uuid, p_requested_dealer text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$ SELECT coalesce((public.pdc_workshop_actor_vehicle_allowed(p_scope,p_vehicle_id,p_requested_dealer)
 OR pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(p_scope,p_vehicle_id,p_requested_dealer))
 AND (NOT (p_scope ? 'department_scope') OR
   (p_scope->>'department_scope'='138' AND p_scope->>'environment'='staging' AND p_scope->>'role' IN ('viewer','operator','administrator') AND p_scope->>'dealer_code'='14450' AND p_requested_dealer='14450' AND EXISTS (
SELECT 1 FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews n ON n.vehicle_id=v.id
WHERE v.id=p_vehicle_id AND v.source_system='tune_pmg' AND v.lifecycle_state='active' AND v.visible_on_board AND v.deleted_at IS NULL AND v.board_purged_at IS NULL AND nullif(btrim(v.stock_number),'') IS NOT NULL
AND n.status='approved' AND n.approved_at IS NOT NULL AND n.approved_by IS NOT NULL AND n.approval_receipt->>'ok'='true' AND n.approval_receipt->>'code'='new_vehicle_approved'
AND EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND j.source_system='tune_pmg' AND j.company='01' AND j.division='1' AND j.departments=ARRAY['138']::text[] AND j.stock_number=v.stock_number)
AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND (j.source_system IS DISTINCT FROM 'tune_pmg' OR j.company IS DISTINCT FROM '01' OR j.division IS DISTINCT FROM '1' OR j.departments IS DISTINCT FROM ARRAY['138']::text[] OR j.stock_number IS DISTINCT FROM v.stock_number))
AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN pdc_parts_private.jobs j ON j.vehicle_id=o.vehicle_id AND j.ro_number=o.repair_order_number AND j.closed_at IS NULL WHERE o.vehicle_id=v.id AND o.department='138' AND o.stock_number=v.stock_number AND o.raw_evidence_id IS NOT NULL)
AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND (o.department IS DISTINCT FROM '138' OR o.stock_number IS DISTINCT FROM v.stock_number OR o.raw_evidence_id IS NULL))
))),false); $function$;$def$, E'\n', E'\r\n');
END $apply$;
DO $post$
BEGIN
  IF md5(pg_get_functiondef('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)'::regprocedure)) IS DISTINCT FROM '56ff1f82635ec4161a492db79fc23255' THEN
    RAISE EXCEPTION 'workshop_read_vehicle_allowed_restore_failed: %', md5(pg_get_functiondef('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)'::regprocedure));
  END IF;
END $post$;
