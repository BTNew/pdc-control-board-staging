-- Rollback r758 (F364): restore the r734 delivery body and the pre-r758 trigger body, drop the helper functions and check 475.
-- Statistics rows written with the two new literals are kept (history); the check keeps allowing them.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $r758d$
DECLARE v_old text; v_new text; v_def text; sig regprocedure;
  a1 text := E' receipt uuid; duration bigint; has_interval boolean:=false; cancelled integer:=0; assignments jsonb;\n fallback_start timestamptz; has_fallback boolean:=false;\n';
  b1 text := E' receipt uuid; duration bigint; has_interval boolean:=false; cancelled integer:=0; assignments jsonb;\n';
  a2 text := E' -- r758: no RFT booking; the dealer-transit time runs from work complete (WPC, else final check) to the Navision status.\n'
          || E' IF NOT has_interval AND v.dealer_transit_closed_at IS NULL AND v.dealer_transit_duration_seconds IS NULL THEN\n'
          || E'  fallback_start:=pdc_navision_delivery_private.work_complete_at_758(v);\n'
          || E'  IF fallback_start IS NOT NULL AND fallback_start<=closed_at THEN has_fallback:=true; duration:=greatest(0,floor(extract(epoch FROM(closed_at-fallback_start)))::bigint); END IF;\n'
          || E' END IF;\n';
  a3 text := E'   dealer_transit_started_at=CASE WHEN has_fallback THEN fallback_start ELSE dealer_transit_started_at END,\n   dealer_transit_closed_at=CASE WHEN has_interval OR has_fallback THEN closed_at ELSE dealer_transit_closed_at END,\n   dealer_transit_duration_seconds=CASE WHEN has_interval OR has_fallback THEN duration ELSE dealer_transit_duration_seconds END,\n';
  b3 text := E'   dealer_transit_closed_at=CASE WHEN has_interval THEN closed_at ELSE dealer_transit_closed_at END,\n   dealer_transit_duration_seconds=CASE WHEN has_interval THEN duration ELSE dealer_transit_duration_seconds END,\n';
  a4 text := E'    ''collection_recorded'',has_interval,''work_complete_fallback'',has_fallback,''work_completion_inferred'',false,''cancelled_bookings'',cancelled),result);\n  IF has_interval OR has_fallback THEN\n';
  b4 text := E'    ''collection_recorded'',has_interval,''work_completion_inferred'',false,''cancelled_bookings'',cancelled),result);\n  IF has_interval THEN\n';
  a5 text := E'    coalesce(v.dealer_transit_started_at,fallback_start),closed_at,duration,CASE WHEN has_fallback THEN ''Delivered - At Dealer (from work complete, no RFT booking)'' ELSE ''Delivered - At Dealer'' END);\n';
  b5 text := E'    v.dealer_transit_started_at,closed_at,duration,''Delivered - At Dealer'');\n';
  t1 text := E' -- r758: the record left the latest Navision upload while the car''s work was complete (WPC or RFT): complete it.\n'
          || E' IF TG_TABLE_NAME=''navision_backend_records'' AND TG_OP=''UPDATE'' AND OLD.is_current AND OLD.record_status=''current''\n'
          || E'    AND NOT (NEW.is_current AND NEW.record_status=''current'') AND NEW.canonical_vehicle_id IS NOT NULL THEN\n'
          || E'  PERFORM pdc_navision_delivery_private.complete_left_navision_758(NEW.id);\n'
          || E' END IF;\n';
BEGIN
  sig := 'public.reconcile_navision_delivery_734(uuid,uuid,text)'::regprocedure;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  v_new := replace(replace(replace(replace(replace(v_old, a1, b1), a2, ''), a3, b3), a4, b4), a5, b5);
  IF md5(v_new) <> 'b7f8a5e503f820fa85d21ccac579e582' THEN RAISE EXCEPTION 'r758 down: delivery body would not return to the r734 md5'; END IF;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  sig := 'public.trigger_reconcile_navision_operational_record()'::regprocedure;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  v_new := replace(v_old, t1, '');
  IF md5(v_new) <> '54fbd5264b1a3dca04840ca635b5a55f' THEN RAISE EXCEPTION 'r758 down: trigger body would not return to the pre-r758 md5'; END IF;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  DROP FUNCTION pdc_navision_delivery_private.complete_left_navision_758(uuid);
  DROP FUNCTION pdc_navision_delivery_private.work_complete_at_758(public.vehicles);
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'wpc_completes_on_navision_758';
END $r758d$;
