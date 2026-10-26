-- Released 2026-10-26 22:28 Perth: migration 20261026142832.
-- Staging cdsmnqxtyyoeoznmbidd only; no operational data writes.
-- The existing cascade owner must finish writing hours before resizing bookings.
-- No collision, lifecycle, calendar, permission, or constraint guard is changed.
DO $repair$
DECLARE
 target regprocedure:=to_regprocedure('public.workshop_extend_running_after_hours_538()');
 definition text; revised text; before_acl aclitem[]; before_owner oid; before_metadata jsonb; pins_before text;
 cache_anchor text:=$cache_anchor$  IF tg_op IN('UPDATE','DELETE') AND old.active THEN$cache_anchor$;
 cache_replacement text:=$cache_replacement$  -- Evict only this adjustment's vehicles before the scheduler reads their lines.
  -- The existing later invalidator still owns epoch bumps and other cache inputs.
  IF TG_OP='INSERT' THEN
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id=NEW.vehicle_id;
  ELSIF TG_OP='UPDATE' THEN
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id IN(OLD.vehicle_id,NEW.vehicle_id);
  ELSE
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id=OLD.vehicle_id;
  END IF;
  IF tg_op IN('UPDATE','DELETE') AND old.active THEN$cache_replacement$;
 anchor text:=E'BEGIN\n IF TG_OP';
 replacement text:=E'BEGIN\n -- The enclosing owner will reconcile once all authoritative hours are written.\n -- Honor only the existing 407 contract shared by the three cascade owners.\n IF current_setting(''pdc.defer_workshop_adjustment_reconcile'',true)=''407'' THEN RETURN NEW; END IF;\n IF TG_OP';
BEGIN
 cache_replacement:=replace(cache_replacement,chr(13),'');
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 THEN RAISE EXCEPTION 'staging_only'; END IF;
 SELECT pg_get_functiondef(p.oid),p.proacl,p.proowner,to_jsonb(p)-'prosrc' INTO definition,before_acl,before_owner,before_metadata FROM pg_proc p WHERE p.oid=target;
 IF md5(definition) IS DISTINCT FROM '3a46a6f9846ab5c2bc36ce107dc7c905'
 THEN RAISE EXCEPTION 'reviewed_running_hours_trigger_changed'; END IF;
 IF md5(pg_get_functiondef('public.workshop_extend_running_booking_538(uuid,text,integer)'::regprocedure)) IS DISTINCT FROM 'f70d2eb94c4825f8ec61efb4354a3dbe'
  OR md5(pg_get_functiondef('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)'::regprocedure)) IS DISTINCT FROM '1080428babb9d0fae3d9d56a581327ee'
  OR md5(pg_get_functiondef('pdc_operation_updates_private.reconcile_estimate_bookings_20261018(uuid,text[],uuid,uuid)'::regprocedure)) IS DISTINCT FROM 'a338ae78a36b80bf9474bab846e1f851'
 THEN RAISE EXCEPTION 'reviewed_cascade_authority_changed'; END IF;
 IF md5(pg_get_functiondef('public.workshop_reconcile_adjustment_booking_duration()'::regprocedure)) IS DISTINCT FROM 'f6ee35c0252cfcf4afe7c261a4f64dd7'
  OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='pdc_work_categories_private.qc_operation_lines_cache'::regclass
    AND contype='p' AND pg_get_constraintdef(oid)='PRIMARY KEY (vehicle_id)')
 THEN RAISE EXCEPTION 'reviewed_adjustment_cache_contract_changed'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.signature)::text,'[]')) INTO pins_before FROM pdc_ops.expected_function_md5 e;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'running_hours_anchor_count'; END IF;
 revised:=replace(definition,anchor,replacement);
 IF md5(revised)<>'1b2c507e05f0247bec9d41446e2cb5eb' THEN RAISE EXCEPTION 'running_hours_candidate_mismatch'; END IF;
 EXECUTE revised;
 IF md5(pg_get_functiondef(target)) IS DISTINCT FROM '1b2c507e05f0247bec9d41446e2cb5eb'
  OR (SELECT to_jsonb(p)-'prosrc' IS DISTINCT FROM before_metadata FROM pg_proc p WHERE oid=target)
  OR (SELECT md5(coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.signature)::text,'[]')) FROM pdc_ops.expected_function_md5 e) IS DISTINCT FROM pins_before
 THEN RAISE EXCEPTION 'running_hours_candidate_readback_failed'; END IF;
 -- Same atomic DO: if the second body or invariant fails, neither change remains.
 target:=to_regprocedure('public.workshop_reconcile_adjustment_booking_duration()');
 SELECT pg_get_functiondef(p.oid),to_jsonb(p)-'prosrc' INTO definition,before_metadata FROM pg_proc p WHERE p.oid=target;
 IF (length(definition)-length(replace(definition,cache_anchor,'')))/length(cache_anchor)<>1 THEN RAISE EXCEPTION 'adjustment_cache_anchor_count'; END IF;
 revised:=replace(definition,cache_anchor,cache_replacement);
 IF md5(revised)<>'ef3116918cfb1d1c44cc45ef6e425bab' THEN RAISE EXCEPTION 'adjustment_cache_candidate_mismatch'; END IF;
 EXECUTE revised;
 IF md5(pg_get_functiondef(target)) IS DISTINCT FROM 'ef3116918cfb1d1c44cc45ef6e425bab'
  OR (SELECT to_jsonb(p)-'prosrc' IS DISTINCT FROM before_metadata FROM pg_proc p WHERE oid=target)
  OR (SELECT md5(coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.signature)::text,'[]')) FROM pdc_ops.expected_function_md5 e) IS DISTINCT FROM pins_before
 THEN RAISE EXCEPTION 'adjustment_cache_candidate_readback_failed'; END IF;
END
$repair$;
