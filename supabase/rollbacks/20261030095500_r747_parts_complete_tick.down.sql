-- Rollback for r747 (F353). Puts back the original parts flags body and removes the Parts complete tick.
SET LOCAL lock_timeout = '6s';
DO $$ DECLARE v_old text := (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure);
BEGIN
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_old, '6c828cb4ffdd7e0717bd5d9f50f4c764') WHERE check_name IN ('outlook_parts_completion_514', 'outlook_internal_parts_auth_515');
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = '6c828cb4ffdd7e0717bd5d9f50f4c764' WHERE prosrc_md5 = v_old;
END $$;
CREATE OR REPLACE FUNCTION public.pdc_parts_flags_vehicle_20260911(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE imported jsonb; c public.pdc_parts_completion_email_confirmations%rowtype; mark jsonb;
BEGIN
 imported:=public.pdc_imported_parts_flags_vehicle_20260912(p_vehicle_id);
 SELECT * INTO c FROM public.pdc_parts_completion_email_confirmations WHERE vehicle_id=p_vehicle_id AND active;
 IF NOT FOUND THEN RETURN imported; END IF;
 mark:=jsonb_build_object('colour','green','label','Parts complete — person confirmed','parts_complete',true,
 'override_source','authorised_email_confirmation','person_confirmed',true,'confirmation_id',c.confirmation_id,
 'confirmed_at',c.received_at,'confirmed_by',c.sender,'confirmed_by_name',coalesce(nullif(c.authentication->>'display_name',''),c.sender),
 'meaning','A person confirmed the parts are here. This confirmation takes priority over import backorder flags; original import evidence is retained.');
 RETURN coalesce(imported,'{}')||mark||jsonb_build_object('import_status',imported,
 'jobs',(SELECT coalesce(jsonb_agg(j||mark||jsonb_build_object('import_status',j)),'[]') FROM jsonb_array_elements(coalesce(imported->'jobs','[]')) j),
 'operations',(SELECT coalesce(jsonb_object_agg(key,value||mark||jsonb_build_object('import_status',value,'job_label','A person confirmed parts complete for this vehicle')),'{}') FROM jsonb_each(coalesce(imported->'operations','{}'))));
END $function$;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'parts_complete_tick_747';
DROP FUNCTION IF EXISTS public.set_pdc_parts_board_complete_747(uuid, boolean);
DROP TABLE IF EXISTS public.pdc_parts_board_complete_history_747;
DROP TABLE IF EXISTS public.pdc_parts_board_complete_747;
UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE singleton;
