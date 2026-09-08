CREATE OR REPLACE FUNCTION public.get_vehicle_workshop_detail_scoped(p_vehicle_id uuid, p_dealer_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_scope jsonb; v_dealer text; v_vehicle_dealer text;
BEGIN
 v_scope:=public.pdc_auditor_actor_scope();
 v_dealer:=btrim(coalesce(p_dealer_code,''));
 IF v_dealer NOT IN ('14450','37047') OR v_scope->>'environment' IS DISTINCT FROM 'staging' OR v_scope->>'dealer_code' IS DISTINCT FROM v_dealer THEN
   RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied','data',jsonb_build_object('environment','staging','dealer_code',v_dealer));
 END IF;
 SELECT public.pdc_auditor_vehicle_dealer(v.id) INTO v_vehicle_dealer
 FROM public.vehicles v
 WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active';
 IF v_vehicle_dealer IS DISTINCT FROM v_dealer THEN
   RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_dealer_scope','data',jsonb_build_object('vehicle_id',p_vehicle_id,'dealer_code',v_dealer));
 END IF;
 RETURN public.get_vehicle_workshop_detail(p_vehicle_id);
END $function$
