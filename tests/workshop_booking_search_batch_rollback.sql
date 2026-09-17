-- STAGING ONLY. One temporary viewer/scope; existing vehicle/booking rows are
-- read for comparison with the established scoped-detail authority, not edited.
-- Run after the booking-search migration, in one transaction/connection.
BEGIN;
SET LOCAL statement_timeout='120s';
SET LOCAL lock_timeout='5s';
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Staging only'; END IF;
END $guard$;
CREATE TEMP TABLE search_checks(label text PRIMARY KEY,evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE search_actor(id uuid,email text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.search_assert(pass boolean,label text,evidence jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $fn$ BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: %',label,evidence; END IF;
 INSERT INTO search_checks VALUES(label,evidence);
END $fn$;

DO $setup$
DECLARE actor uuid:=gen_random_uuid(); email text; denied boolean:=false;
BEGIN
 PERFORM pg_temp.search_assert(NOT has_function_privilege('anon','public.get_workshop_booking_search_scoped(jsonb)','execute')
  AND NOT has_function_privilege('service_role','public.get_workshop_booking_search_scoped(jsonb)','execute')
  AND has_function_privilege('authenticated','public.get_workshop_booking_search_scoped(jsonb)','execute'),'least-privilege RPC grants');
 PERFORM set_config('request.jwt.claims','{}',true);
 BEGIN PERFORM public.get_workshop_booking_search_scoped('[]');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM pg_temp.search_assert(denied,'missing authenticated actor is denied');
 email:='booking-search-'||actor||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(actor,'authenticated','authenticated',email,clock_timestamp(),'{"provider":"email","providers":["email"]}',
  '{"full_name":"Temporary booking search rollback fixture"}',clock_timestamp(),clock_timestamp());
 UPDATE public.pdc_user_roles SET role='viewer',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=actor;
 INSERT INTO public.pdc_auditor_user_dealer_scopes(auth_user_id,normalized_email,dealer_code,environment,active)
 VALUES(actor,email,'14450','staging',true);
 INSERT INTO search_actor VALUES(actor,email);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',email,'role','authenticated')::text,true);
 PERFORM pg_temp.search_assert(public.pdc_auditor_actor_scope()->>'role'='viewer','viewer receives established dealer scope');
END $setup$;

-- Prioritize cross-station/multi-day vehicles so identical booking projections
-- explicitly cover the searches most likely to disappear under a date filter.
CREATE TEMP TABLE search_candidates ON COMMIT DROP AS
 SELECT v.id,public.pdc_auditor_vehicle_dealer(v.id) dealer,
  count(DISTINCT b.stage_id) stages,
  coalesce(bool_or((b.scheduled_end_at AT TIME ZONE 'Australia/Perth')::date
   >(b.scheduled_start_at AT TIME ZONE 'Australia/Perth')::date),false) multiday
 FROM public.vehicles v LEFT JOIN public.workshop_bookings b ON b.vehicle_id=v.id AND b.deleted_at IS NULL
  AND b.status IN('queued','planned','started','stoppage','completed')
 WHERE v.deleted_at IS NULL AND v.lifecycle_state='active'
  AND public.pdc_workshop_actor_vehicle_allowed(public.pdc_auditor_actor_scope(),v.id,public.pdc_auditor_vehicle_dealer(v.id))
 GROUP BY v.id ORDER BY multiday DESC,stages DESC,v.id LIMIT 25;
CREATE TEMP TABLE search_before_bookings ON COMMIT DROP AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bookings b
 WHERE b.vehicle_id IN(SELECT id FROM search_candidates);

DO $checks$
DECLARE requests jsonb; response jsonb; expected jsonb; item record; one jsonb; bad jsonb; t timestamptz;
 batch_ms numeric; detail_ms numeric; denied boolean:=false; actor uuid;
BEGIN
 SELECT jsonb_agg(jsonb_build_object('vehicle_id',id,'dealer_code',dealer) ORDER BY id) INTO requests FROM search_candidates;
 PERFORM pg_temp.search_assert(jsonb_array_length(requests)=25,'full 25-vehicle request fixture');
 PERFORM pg_temp.search_assert(EXISTS(SELECT 1 FROM search_candidates WHERE multiday),'fixture includes multi-day carryover');
 PERFORM pg_temp.search_assert(EXISTS(SELECT 1 FROM search_candidates WHERE stages>1),'fixture includes other-station bookings');
 t:=clock_timestamp(); response:=public.get_workshop_booking_search_scoped(requests);
 batch_ms:=extract(epoch FROM clock_timestamp()-t)*1000;
 PERFORM pg_temp.search_assert(response->>'ok'='true' AND jsonb_array_length(response->'results')=25,'one complete metadata batch');
 t:=clock_timestamp();
 FOR item IN SELECT * FROM search_candidates ORDER BY id LOOP
  SELECT x INTO one FROM jsonb_array_elements(response->'results') x WHERE x->>'vehicle_id'=item.id::text;
  expected:=public.get_vehicle_workshop_detail_scoped(item.id,item.dealer);
  PERFORM pg_temp.search_assert(one->>'ok'='true' AND one->>'dealer_code'=item.dealer
   AND one->'bookings'=expected->'bookings','exact booking projection '||item.id,
   jsonb_build_object('booking_count',jsonb_array_length(one->'bookings')));
  PERFORM pg_temp.search_assert(NOT (one ? 'requirements' OR one ? 'line_adjustments' OR one ? 'vehicle_version'),
   'metadata only '||item.id);
 END LOOP;
 detail_ms:=extract(epoch FROM clock_timestamp()-t)*1000;
 PERFORM pg_temp.search_assert(true,'read timing',jsonb_build_object('batch_ms',round(batch_ms,2),
  '25_details_ms',round(detail_ms,2),'network_requests_before',25,'network_requests_after',1));

 FOR bad IN SELECT x FROM (VALUES ('null'::jsonb),('{}'::jsonb),('[]'::jsonb),
  ('[{"vehicle_id":"stock-123","dealer_code":"14450"}]'::jsonb),
  (jsonb_build_array(requests->0,requests->0)),(requests||jsonb_build_array(requests->0)),
  (jsonb_build_array(jsonb_build_object('vehicle_id',(requests->0)->>'vehicle_id','dealer_code','')))) invalid(x)
 LOOP
  PERFORM pg_temp.search_assert(public.get_workshop_booking_search_scoped(bad)->>'error'='invalid_identity',
   'invalid request '||md5(bad::text));
 END LOOP;

 -- One denied identity must not hide an allowed match or appear unbooked.
 one:=jsonb_build_object('vehicle_id',gen_random_uuid(),'dealer_code','14450');
 response:=public.get_workshop_booking_search_scoped(jsonb_build_array(requests->0,one));
 PERFORM pg_temp.search_assert(response->>'ok'='true' AND response#>>'{results,0,ok}'='true'
  AND response#>>'{results,1,ok}'='false' AND NOT (response#>'{results,1}' ? 'bookings'),'mixed allowed/unknown identities fail closed per vehicle');
 one:=(requests->0)||jsonb_build_object('dealer_code',CASE WHEN requests#>>'{0,dealer_code}'='14450' THEN '37047' ELSE '14450' END);
 response:=public.get_workshop_booking_search_scoped(jsonb_build_array(one));
 PERFORM pg_temp.search_assert(response#>>'{results,0,error}'='dealer_scope_denied'
  AND NOT (response#>'{results,0}' ? 'bookings'),'wrong exact dealer exposes no booking metadata');

 SELECT id INTO actor FROM search_actor;
 UPDATE public.pdc_auditor_user_dealer_scopes SET active=false WHERE auth_user_id=actor;
 BEGIN PERFORM public.get_workshop_booking_search_scoped(requests);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM pg_temp.search_assert(denied,'revoked actor dealer scope is denied');
 PERFORM pg_temp.search_assert(NOT EXISTS(SELECT 1 FROM search_before_bookings old
  LEFT JOIN public.workshop_bookings b ON b.id=old.id WHERE to_jsonb(b) IS DISTINCT FROM old.row_data),'existing booking versions and rows remain unchanged');
END $checks$;
SELECT jsonb_build_object('count',count(*),'results',jsonb_agg(to_jsonb(c) ORDER BY label)) result FROM search_checks c;
ROLLBACK;
