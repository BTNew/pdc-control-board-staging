-- Confirmed final Navision delivery closes the PMB lifecycle, even if PMB
-- collection was not recorded. Cancel allocations; never fabricate work/QC.
DO $$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS pdc_navision_delivery_private;
REVOKE ALL ON SCHEMA pdc_navision_delivery_private FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE pdc_navision_delivery_private.booking_cancellations (
 transaction_id bigint NOT NULL,
 booking_id uuid NOT NULL REFERENCES public.workshop_bookings(id),
 backend_record_id uuid NOT NULL REFERENCES public.navision_backend_records(id),
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 cancelled_at timestamptz NOT NULL,
 actor_id uuid REFERENCES auth.users(id),
 before_booking jsonb NOT NULL,
 before_assignments jsonb NOT NULL,
 PRIMARY KEY(transaction_id,booking_id)
);
ALTER TABLE pdc_navision_delivery_private.booking_cancellations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_navision_delivery_private.booking_cancellations FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_navision_delivery_private.exact_link(p_backend_id uuid,p_vehicle_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.navision_backend_records b
 JOIN public.vehicles v ON v.id=b.canonical_vehicle_id
 WHERE b.id=p_backend_id AND v.id=p_vehicle_id AND v.deleted_at IS NULL
 AND b.source_system='microsoft_navision' AND b.is_current AND b.record_status='current'
 AND b.dealer_code=v.source_batch_id
 AND lower(regexp_replace(btrim(coalesce(b.normalized_data->>'toyotaStatus','')),'[[:space:]–-]','','g'))='deliveredatdealer'
 AND NOT EXISTS(SELECT 1 FROM public.navision_backend_records other
  WHERE other.id<>b.id AND other.canonical_vehicle_id=v.id AND other.is_current AND other.record_status='current'));
$$;

-- These are private, transaction-bound exceptions to existing planner guards.
-- A final-delivery import may cancel only its exact original booking, with
-- every schedule, duration, bay, actual-work and vehicle field preserved.
CREATE FUNCTION pdc_navision_delivery_private.allowed_booking_cancel(p_old jsonb,p_new jsonb)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM pdc_navision_delivery_private.booking_cancellations c
 WHERE c.transaction_id=txid_current() AND c.booking_id=(p_old->>'id')::uuid
 AND c.before_booking=p_old AND c.vehicle_id=(p_new->>'vehicle_id')::uuid
 AND p_old->>'deleted_at' IS NULL AND p_old->>'status' IN('queued','planned','started','stoppage')
 AND p_new->>'status'='deleted' AND (p_new->>'deleted_at')::timestamptz=c.cancelled_at
 AND p_new->>'deleted_reason'='Navision Delivered - At Dealer'
 AND (p_new->>'updated_by')::uuid IS NOT DISTINCT FROM c.actor_id
 AND (p_new->>'version')::bigint=(p_old->>'version')::bigint+1
 AND p_new-ARRAY['status','deleted_at','deleted_reason','version','updated_at','updated_by']
     =p_old-ARRAY['status','deleted_at','deleted_reason','version','updated_at','updated_by']
 AND pdc_navision_delivery_private.exact_link(c.backend_record_id,c.vehicle_id));
$$;
CREATE FUNCTION pdc_navision_delivery_private.allowed_assignment_release(p_old jsonb,p_new jsonb)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM pdc_navision_delivery_private.booking_cancellations c
 CROSS JOIN LATERAL jsonb_array_elements(c.before_assignments) a
 WHERE c.transaction_id=txid_current() AND c.booking_id=(p_old->>'booking_id')::uuid
 AND a=p_old AND p_old->>'released_at' IS NULL
 AND (p_new->>'released_at')::timestamptz=c.cancelled_at
 AND p_new-ARRAY['released_at','updated_at']=p_old-ARRAY['released_at','updated_at']
 AND pdc_navision_delivery_private.exact_link(c.backend_record_id,c.vehicle_id));
$$;

-- Keep the deployed guard bodies and all their ordinary checks intact.
DO $$
DECLARE n text; definition text; body text; prefix text;
BEGIN
 FOREACH n IN ARRAY ARRAY['workshop_enforce_booking_lifecycle',
  'workshop_require_planner_booking_mutation','workshop_block_legacy_ambiguous_booking_mutation',
  'workshop_require_planner_assignment_mutation'] LOOP
  SELECT pg_get_functiondef(p.oid),p.prosrc INTO definition,body FROM pg_proc p
  JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname=n AND p.pronargs=0;
  IF definition IS NULL THEN RAISE EXCEPTION 'required_delivery_guard_missing: %',n; END IF;
  prefix:=CASE WHEN n='workshop_require_planner_assignment_mutation'
   THEN E'BEGIN\n IF TG_OP=\'UPDATE\' AND pdc_navision_delivery_private.allowed_assignment_release(to_jsonb(OLD),to_jsonb(NEW)) THEN RETURN NEW; END IF;'
   ELSE E'BEGIN\n IF TG_OP=\'UPDATE\' AND pdc_navision_delivery_private.allowed_booking_cancel(to_jsonb(OLD),to_jsonb(NEW)) THEN RETURN NEW; END IF;' END;
  IF position('pdc_navision_delivery_private.allowed_' IN body)=0 THEN
   EXECUTE replace(definition,body,regexp_replace(body,'\mBEGIN\M',prefix,'i'));
  END IF;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_navision_delivery_734(
 p_backend_record_id uuid,p_actor_id uuid DEFAULT NULL,p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public','extensions'
SET statement_timeout='120s' AS $$
DECLARE b public.navision_backend_records%rowtype; v public.vehicles%rowtype;
 old public.pdc_rft_transport_lifecycle_receipts_734%rowtype; booking public.workshop_bookings%rowtype;
 after_booking public.workshop_bookings%rowtype; closed_at timestamptz:=clock_timestamp();
 actor_email text:=coalesce(nullif(lower(btrim(p_actor_email)),''),'system@staging.invalid');
 before_state jsonb; after_state jsonb; request_payload jsonb; request_sha text; result jsonb;
 receipt uuid; duration bigint; has_interval boolean:=false; cancelled integer:=0; assignments jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR p_backend_record_id IS NULL
 THEN RETURN public.navision_backend_response(false,'wrong_environment_or_invalid_input'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-734-delivery-record:'||p_backend_record_id::text,0));
 SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id FOR UPDATE;
 IF NOT FOUND OR NOT b.is_current OR b.record_status<>'current' OR b.canonical_vehicle_id IS NULL
 THEN RETURN public.navision_backend_response(false,'delivery_record_not_current'); END IF;
 IF lower(regexp_replace(btrim(coalesce(b.normalized_data->>'toyotaStatus','')),'[[:space:]–-]','','g'))<>'deliveredatdealer'
 THEN RETURN public.navision_backend_response(false,'delivery_status_not_exact'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('workshop:vehicle:'||b.canonical_vehicle_id::text,0));
 SELECT * INTO v FROM public.vehicles WHERE id=b.canonical_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN public.navision_backend_response(false,'delivery_vehicle_not_found'); END IF;
 IF b.dealer_code IS DISTINCT FROM v.source_batch_id THEN RETURN public.navision_backend_response(false,'delivery_wrong_dealer_scope'); END IF;
 IF NOT pdc_navision_delivery_private.exact_link(b.id,v.id)
 THEN RETURN public.navision_backend_response(false,'delivery_identity_not_exact'); END IF;
 SELECT * INTO old FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=v.id AND action='delivered';
 before_state:=public.pdc_rft_transport_snapshot_734(v.id)||jsonb_build_object('vehicle',to_jsonb(v));
 -- Snapshot original assignments before the Bus activity trigger releases helpers.
 FOR booking IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id
  AND deleted_at IS NULL AND status IN('queued','planned','started','stoppage') ORDER BY id FOR UPDATE LOOP
  SELECT coalesce(jsonb_agg(to_jsonb(a)),'[]'::jsonb) INTO assignments
   FROM public.workshop_booking_assignments a WHERE a.booking_id=booking.id AND a.released_at IS NULL;
  INSERT INTO pdc_navision_delivery_private.booking_cancellations
   (transaction_id,booking_id,backend_record_id,vehicle_id,cancelled_at,actor_id,before_booking,before_assignments)
  VALUES(txid_current(),booking.id,b.id,v.id,closed_at,p_actor_id,to_jsonb(booking),assignments);
  UPDATE public.workshop_booking_assignments SET released_at=closed_at,updated_at=closed_at
   WHERE booking_id=booking.id AND released_at IS NULL;
  UPDATE public.workshop_bookings SET status='deleted',deleted_at=closed_at,
   deleted_reason='Navision Delivered - At Dealer',version=version+1,updated_at=closed_at,updated_by=p_actor_id
   WHERE id=booking.id AND vehicle_id=v.id AND deleted_at IS NULL RETURNING * INTO after_booking;
  INSERT INTO public.workshop_booking_history(booking_id,vehicle_id,event_type,before_data,after_data,actor_user_id,actor_email,metadata)
  VALUES(booking.id,v.id,'navision_dealer_delivery_cancelled',to_jsonb(booking),to_jsonb(after_booking),p_actor_id,actor_email,
   jsonb_build_object('backend_record_id',b.id,'status_literal','Delivered - At Dealer','work_completion_inferred',false));
  cancelled:=cancelled+1;
 END LOOP;
 has_interval:=v.dealer_transit_started_at IS NOT NULL AND v.dealer_transit_closed_at IS NULL
  AND v.dealer_transit_duration_seconds IS NULL
  AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=v.id AND action='rft_booked')
  AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=v.id AND action='collected');
 IF has_interval THEN duration:=greatest(0,floor(extract(epoch FROM(closed_at-v.dealer_transit_started_at)))::bigint); END IF;
 IF v.lifecycle_state<>'completed' OR v.current_location IS DISTINCT FROM 'Completed' OR v.visible_on_board
  OR v.active_workshop_booking_id IS NOT NULL OR v.pmb_stage IS NOT NULL OR v.pmb_bay_stage IS NOT NULL OR v.pmb_bay_number IS NOT NULL THEN
  UPDATE public.vehicles SET lifecycle_state='completed',current_location='Completed',visible_on_board=false,
   active_workshop_booking_id=NULL,pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,workshop_status='completed',
   workshop_status_updated_at=closed_at,workshop_status_updated_by=p_actor_id,
   location_override=NULL,location_override_reason=NULL,location_override_at=NULL,location_override_by=NULL,
   dealer_transit_closed_at=CASE WHEN has_interval THEN closed_at ELSE dealer_transit_closed_at END,
   dealer_transit_duration_seconds=CASE WHEN has_interval THEN duration ELSE dealer_transit_duration_seconds END,
   delivered_to_dealer_date=coalesce(delivered_to_dealer_date,(closed_at AT TIME ZONE 'Australia/Perth')::date),
   source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('navision_dealer_delivery_rule','20261007',
    'navision_record_id',b.id,'navision_status_literal','Delivered - At Dealer','delivered_at',closed_at),
   version=version+1,updated_at=closed_at,updated_by=p_actor_id WHERE id=v.id RETURNING * INTO v;
 END IF;
 UPDATE public.navision_board_activations SET active=false,completed_at=coalesce(completed_at,closed_at),
  completion_reason='Delivered - At Dealer',completed_by=p_actor_id,completed_by_email=actor_email,updated_at=closed_at
  WHERE backend_record_id=b.id AND (active OR completed_at IS NULL);
 receipt:=coalesce(old.receipt_id,extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734','delivery:'||b.id::text||':'||v.id::text));
 result:=jsonb_build_object('ok',true,'code','delivered_at_dealer_completed','replay',old.receipt_id IS NOT NULL,
  'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',v.id,'backend_record_id',b.id,'status','Delivered - At Dealer',
   'vehicle_version_after',v.version,'current_location','Completed','lifecycle_state','completed','cancelled_bookings',cancelled,
   'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,
   'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds));
 after_state:=public.pdc_rft_transport_snapshot_734(v.id)||jsonb_build_object('vehicle',to_jsonb(v));
 IF old.receipt_id IS NULL THEN
  request_payload:=jsonb_build_object('contract','pdc-navision-dealer-delivery-20261007','backend_record_id',b.id,
   'vehicle_id',v.id,'status','Delivered - At Dealer');
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  INSERT INTO public.pdc_rft_transport_lifecycle_receipts_734
   (receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,v.id,'delivered',p_actor_id,actor_email,
   extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734','delivery-idempotency:'||b.id::text||':'||v.id::text),
   request_sha,request_payload,before_state,after_state,jsonb_build_object('exact_status_literal',true,
    'normalized_status','deliveredatdealer','dealer_scope_exact',true,'open_interval_required',false,
    'collection_recorded',has_interval,'work_completion_inferred',false,'cancelled_bookings',cancelled),result);
  IF has_interval THEN
   INSERT INTO public.pdc_rft_dealer_transit_statistics_734
    (statistic_id,vehicle_id,delivered_receipt_id,started_at,closed_at,duration_seconds,status_literal)
   VALUES(extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734','statistic:'||v.id::text),v.id,receipt,
    v.dealer_transit_started_at,closed_at,duration,'Delivered - At Dealer');
  END IF;
 END IF;
 IF before_state IS DISTINCT FROM after_state OR cancelled>0 THEN
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state,after_state,
   jsonb_build_object('action','navision_dealer_delivery_completed','receipt_id',receipt,'backend_record_id',b.id,
    'status_literal','Delivered - At Dealer','cancelled_bookings',cancelled,'work_completion_inferred',false));
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=closed_at WHERE singleton;
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.reconcile_navision_delivery_734(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

-- Linking an already-delivered backend record must run the same rule.
CREATE FUNCTION pdc_navision_delivery_private.reconcile_link() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF NEW.canonical_vehicle_id IS NOT NULL AND NEW.is_current AND NEW.record_status='current'
 AND lower(regexp_replace(btrim(coalesce(NEW.normalized_data->>'toyotaStatus','')),'[[:space:]–-]','','g'))='deliveredatdealer' THEN
  result:=public.reconcile_navision_delivery_734(NEW.id,auth.uid(),public.current_actor_email());
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'navision_dealer_delivery_failed: %',result->>'code'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER zzz_navision_dealer_delivery_link AFTER UPDATE OF canonical_vehicle_id ON public.navision_backend_records
FOR EACH ROW WHEN(OLD.canonical_vehicle_id IS DISTINCT FROM NEW.canonical_vehicle_id)
EXECUTE FUNCTION pdc_navision_delivery_private.reconcile_link();

-- An import cannot silently ignore a failed final-delivery reconciliation.
CREATE OR REPLACE FUNCTION public.trigger_reconcile_navision_operational_record() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public' AS $$
DECLARE v_backend_record_id uuid; result jsonb; b public.navision_backend_records%rowtype;
BEGIN
 IF pg_trigger_depth()>1 THEN RETURN NEW; END IF;
 v_backend_record_id:=CASE WHEN TG_TABLE_NAME='navision_board_activations' THEN NEW.backend_record_id ELSE NEW.id END;
 result:=public.reconcile_navision_operational_record(v_backend_record_id,auth.uid(),public.current_actor_email());
 SELECT * INTO b FROM public.navision_backend_records WHERE id=v_backend_record_id;
 IF b.canonical_vehicle_id IS NOT NULL AND b.is_current AND b.record_status='current'
 AND lower(regexp_replace(btrim(coalesce(b.normalized_data->>'toyotaStatus','')),'[[:space:]–-]','','g'))='deliveredatdealer'
 AND result->>'ok' IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'navision_dealer_delivery_failed: %',result->>'code';
 END IF;
 RETURN NEW;
END $$;

CREATE FUNCTION pdc_navision_delivery_private.prevent_rebooking() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.deleted_at IS NULL AND NEW.status IN('queued','planned','started','stoppage')
 AND (EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=NEW.vehicle_id AND v.lifecycle_state='completed')
 OR EXISTS(SELECT 1 FROM public.navision_backend_records b WHERE b.canonical_vehicle_id=NEW.vehicle_id
  AND b.is_current AND b.record_status='current' AND b.source_system='microsoft_navision'
  AND lower(regexp_replace(btrim(coalesce(b.normalized_data->>'toyotaStatus','')),'[[:space:]–-]','','g'))='deliveredatdealer'))
 THEN RAISE EXCEPTION 'dealer_delivered_vehicle_cannot_be_booked' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER workshop_booking_000_dealer_delivery_guard BEFORE INSERT OR UPDATE OF vehicle_id,status,deleted_at
ON public.workshop_bookings FOR EACH ROW EXECUTE FUNCTION pdc_navision_delivery_private.prevent_rebooking();

-- Bind the automatic completion rule into the existing reviewed preview hash.
ALTER FUNCTION pdc_navision_upload_private.preview_profile(text,jsonb,text,timestamptz)
RENAME TO preview_profile_pre_dealer_delivery_20261007;
CREATE FUNCTION pdc_navision_upload_private.preview_profile(p_profile text,p_rows jsonb,p_source_name text,
 p_source_timestamp timestamptz DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='' SET statement_timeout='60s' AS $$
DECLARE result jsonb; data jsonb; preview_hash text;
BEGIN
 result:=pdc_navision_upload_private.preview_profile_pre_dealer_delivery_20261007(p_profile,p_rows,p_source_name,p_source_timestamp);
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RETURN result; END IF;
 data:=(result->'data')-'preview_hash'-'operational_mutations';
 data:=data||jsonb_build_object('authority','shared_navision_backend_with_final_delivery_completion',
  'dealer_delivery_rule','Delivered - At Dealer completes linked PMB vehicles and cancels active bookings; history retained');
 preview_hash:=encode(extensions.digest(convert_to(jsonb_build_object('data',data,'source_name',coalesce(p_source_name,''),
  'source_timestamp',p_source_timestamp)::text,'UTF8'),'sha256'),'hex');
 RETURN public.navision_backend_response(true,'preview',data||jsonb_build_object('preview_hash',preview_hash));
END $$;
REVOKE ALL ON FUNCTION pdc_navision_upload_private.preview_profile(text,jsonb,text,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_navision_delivery_private FROM PUBLIC,anon,authenticated,service_role;
