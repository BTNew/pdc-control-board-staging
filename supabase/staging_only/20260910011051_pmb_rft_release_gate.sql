-- STAGING ONLY. Mobile QC and PMB release are separate audited steps.
-- Changes functions only; existing vehicles and evidence are not rewritten.
DO $migration$
DECLARE d text; item record;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' THEN RAISE EXCEPTION 'STAGING required'; END IF;
 FOR item IN SELECT * FROM (VALUES
 ('set_rft_confirmation_736(uuid,integer,boolean,uuid)','fdf63d060ae7528f854a10d1c3999cac'),
 ('book_rft_transport_734(uuid,integer,uuid)','f1168c2e636ffd3946e4d202696fbe0d'),
 ('book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)','d88264dca26ccea1b147db69675f602e'),
 ('read_rft_transport_booking_context_739(uuid)','03c38146a02342364c12b2e189446e18'),
 ('read_rft_transport_draft_739(uuid)','7bbb0969ba5b69b682e9a90899fb5f19')
 ) t(signature,digest)
 LOOP
  IF md5(pg_get_functiondef(('public.'||item.signature)::regprocedure))<>item.digest THEN RAISE EXCEPTION 'Function changed: %',item.signature; END IF;
 END LOOP;
 SELECT pg_get_functiondef('public.set_rft_confirmation_736(uuid,integer,boolean,uuid)'::regprocedure) INTO d;
 d:=replace(d,'current_confirmed:=v.rft_confirmed_at IS NOT NULL;',
  'IF p_confirmed AND (v.qc_completed_at IS NULL OR v.rft_transferred_at IS NULL) THEN RETURN jsonb_build_object(''ok'',false,''code'',''qc_signoff_required''); END IF;
  current_confirmed:=v.rft_confirmed_at IS NOT NULL AND v.qc_completed_at IS NOT NULL AND v.rft_confirmed_at>=v.qc_completed_at;');
 d:=replace(d,'rft_confirmed_by=uid,dealer_transit_started_at=coalesce(dealer_transit_started_at,now_at),dealer_transit_closed_at=null,dealer_transit_duration_seconds=null,',
  'rft_confirmed_by=uid,');
 d:=replace(d,'rft_confirmed_by=null,dealer_transit_started_at=null,dealer_transit_closed_at=null,dealer_transit_duration_seconds=null,',
  'rft_confirmed_by=null,');
 d:=replace(d,'''timer_cleared'',not p_confirmed','''timer_cleared'',false');
 EXECUTE d;
 FOR item IN SELECT * FROM (VALUES
 ('book_rft_transport_734(uuid,integer,uuid)'),
 ('book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)')
 ) t(signature)
 LOOP
  SELECT pg_get_functiondef(('public.'||item.signature)::regprocedure) INTO d;
  d:=replace(d,'IF v.qc_completed_at IS NULL OR v.rft_transferred_at IS NULL THEN',
   'IF v.qc_completed_at IS NULL OR v.rft_transferred_at IS NULL OR v.rft_confirmed_at IS NULL OR v.rft_confirmed_at<v.qc_completed_at THEN');
  EXECUTE d;
 END LOOP;
 SELECT pg_get_functiondef('public.read_rft_transport_booking_context_739(uuid)'::regprocedure) INTO d;
 d:=replace(d,'salesperson:=public.pdc_vehicle_effective_salesperson_json_386(v.id);',
  'IF v.qc_completed_at IS NULL OR v.rft_transferred_at IS NULL OR v.rft_confirmed_at IS NULL OR v.rft_confirmed_at<v.qc_completed_at THEN RETURN jsonb_build_object(''ok'',false,''code'',''rft_confirmation_required''); END IF;
  salesperson:=public.pdc_vehicle_effective_salesperson_json_386(v.id);');
 EXECUTE d;
 SELECT pg_get_functiondef('public.read_rft_transport_draft_739(uuid)'::regprocedure) INTO d;
 d:=replace(d,'SELECT * INTO d FROM public.pdc_rft_transport_email_drafts_739 WHERE vehicle_id=p_vehicle_id ORDER BY created_at DESC LIMIT 1;',
  'IF NOT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL
   AND v.qc_completed_at IS NOT NULL AND v.rft_transferred_at IS NOT NULL
   AND v.rft_confirmed_at IS NOT NULL AND v.rft_confirmed_at>=v.qc_completed_at)
   THEN RETURN jsonb_build_object(''ok'',false,''code'',''rft_confirmation_required''); END IF;
  SELECT * INTO d FROM public.pdc_rft_transport_email_drafts_739 WHERE vehicle_id=p_vehicle_id ORDER BY created_at DESC LIMIT 1;');
 EXECUTE d;
END $migration$;
