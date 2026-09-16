-- STAGING ONLY. Synthetic viewer plus one isolated historical admin fixture;
-- no real actor impersonation. All test data and function changes roll back.
-- The station's read-only implementation is used deliberately: its outer RPC
-- performs overdue recovery and is therefore unsuitable for this read test.
BEGIN;
SET LOCAL statement_timeout='45s';
SET LOCAL lock_timeout='5s';
DO $guard$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'STAGING only';
 END IF;
END $guard$;

-- APPLY CANDIDATE MIGRATION HERE FOR PRE-DEPLOYMENT VERIFICATION.

CREATE TEMP TABLE overview_results(name text PRIMARY KEY,status text,evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE overview_fixture_admin(id uuid) ON COMMIT DROP;
CREATE FUNCTION pg_temp.overview_assert(pass boolean,label text,evidence jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $f$ BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: %',label,evidence; END IF;
 INSERT INTO overview_results VALUES(label,'PASS',evidence);
END $f$;

DO $setup$ DECLARE a uuid:=gen_random_uuid(); email text;
BEGIN
 email:='overview-timing-'||a||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(a,'authenticated','authenticated',email,now(),'{"provider":"email","providers":["email"]}','{"full_name":"Overview timing rollback fixture"}',now(),now());
 UPDATE public.pdc_user_roles SET role='viewer',active=true,account_status='approved',approved_at=now() WHERE auth_user_id=a;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',email,'role','authenticated')::text,true);
 PERFORM public.require_pdc_role('viewer');
END $setup$;

DO $history_fixture$ DECLARE bay uuid:=gen_random_uuid(); block uuid:=gen_random_uuid(); st uuid; start_time timestamptz; actor uuid:=auth.uid();
BEGIN
 SELECT id INTO st FROM public.workshop_stages WHERE code='TINT' AND active AND planner_enabled;
 INSERT INTO public.workshop_bays(id,stage_id,bay_number,code,display_name,is_active,is_sublet_row,created_by,updated_by)
 VALUES(bay,st,990631,'OVERVIEW-HISTORY-'||bay,'Overview historical rollback fixture',true,false,actor,actor);
 start_time:=public.workshop_admin_next_operational_minute(now()-interval '7 days');
 INSERT INTO public.workshop_admin_blocks(id,stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 VALUES(block,st,bay,'admin','Overview historical rollback fixture',start_time,public.workshop_add_operational_minutes(start_time,30),30,actor,actor);
 INSERT INTO overview_fixture_admin VALUES(block);
END $history_fixture$;

CREATE TEMP TABLE overview_before_bookings AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bookings b;
CREATE TEMP TABLE overview_before_vehicles AS SELECT id,to_jsonb(v) row_data FROM public.vehicles v;
CREATE TEMP TABLE overview_before_admin AS SELECT id,to_jsonb(a) row_data FROM public.workshop_admin_blocks a;
CREATE TEMP TABLE overview_before_revisions AS SELECT stage_code,revision FROM public.workshop_station_revision;

CREATE TEMP TABLE overview_snapshot AS SELECT public.get_workshop_eligibility_snapshot() body;
DO $verify$ DECLARE snap jsonb; st record; station jsonb; mismatches integer; board_count integer; station_count integer;
 d date:=(now() at time zone 'Australia/Perth')::date; v_from timestamptz; v_to timestamptz;
BEGIN
 SELECT body INTO snap FROM overview_snapshot;
 v_from:=d::timestamp at time zone 'Australia/Perth';
 v_to:=(d+15)::timestamp at time zone 'Australia/Perth';
 PERFORM pg_temp.overview_assert(jsonb_array_length(snap#>'{board,bookings}')>0,'nonempty canonical booking population',jsonb_build_object('bookings',jsonb_array_length(snap#>'{board,bookings}')));
 SELECT count(*) INTO mismatches FROM jsonb_array_elements(snap#>'{board,bookings}') x
 LEFT JOIN public.workshop_bookings b ON b.id=(x->>'booking_id')::uuid
 WHERE b.id IS NULL OR NOT (x ?& ARRAY['actual_start_at','actual_end_at','stoppage_started_at','default_duration_minutes','capacity_base_minutes','capacity_efficiency_percent'])
 OR x->>'status' IS DISTINCT FROM b.status::text
 OR (x->>'scheduled_start_at')::timestamptz IS DISTINCT FROM b.scheduled_start_at
 OR (x->>'scheduled_end_at')::timestamptz IS DISTINCT FROM b.scheduled_end_at
 OR (x->>'actual_start_at')::timestamptz IS DISTINCT FROM b.actual_start_at
 OR (x->>'actual_end_at')::timestamptz IS DISTINCT FROM b.actual_end_at
 OR (x->>'stoppage_started_at')::timestamptz IS DISTINCT FROM b.stoppage_started_at
 OR (x->>'default_duration_minutes')::integer IS DISTINCT FROM b.default_duration_minutes
 OR (x->>'capacity_base_minutes')::numeric IS DISTINCT FROM coalesce(b.capacity_base_minutes,b.default_duration_minutes::numeric)
 OR (x->>'capacity_efficiency_percent')::numeric IS DISTINCT FROM coalesce(b.capacity_efficiency_percent,100);
 PERFORM pg_temp.overview_assert(mismatches=0,'all overview timing fields equal canonical rows',jsonb_build_object('mismatches',mismatches));
 PERFORM pg_temp.overview_assert(snap#>'{board,calendar,scheduling_increment_minutes}' IS NOT DISTINCT FROM (SELECT value FROM public.workshop_settings WHERE key='scheduling_increment_minutes'),'shared scheduling increment');
 SELECT count(*) INTO mismatches FROM public.workshop_admin_blocks a
 JOIN public.workshop_bays b ON b.id=a.bay_id AND b.stage_id=a.stage_id AND NOT b.is_sublet_row
 JOIN public.workshop_stages s ON s.id=a.stage_id AND s.active AND s.planner_enabled AND s.is_physical AND NOT s.is_sublet
 WHERE a.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap#>'{board,admin_blocks}') x WHERE x->>'block_id'=a.id::text);
 PERFORM pg_temp.overview_assert(mismatches=0,'all nondeleted admin blocks remain available for earlier dates');
 PERFORM pg_temp.overview_assert(EXISTS(SELECT 1 FROM jsonb_array_elements(snap#>'{board,admin_blocks}') x JOIN overview_fixture_admin f ON f.id::text=x->>'block_id' WHERE (x->>'scheduled_end_at')::timestamptz<now()),'historical fixture is included before today');
 FOR st IN SELECT * FROM public.workshop_stages WHERE active AND planner_enabled AND is_physical AND NOT is_sublet LOOP
  station:=public.workshop_overlay_canonical_booking_fields_397(public.get_station_workshop_snapshot_pre_170(st.code,d,d+14));
  WITH visible_overview AS(
   SELECT x->>'booking_id' id,x FROM jsonb_array_elements(snap#>'{board,bookings}') x WHERE x->>'stage_code'=st.code
    AND (x->>'scheduled_start_at')::timestamptz<v_to
    AND (x->>'status' IN('started','stoppage') OR (x->>'scheduled_end_at')::timestamptz>v_from)
  ), visible_station AS(
   SELECT x->>'booking_id' id,x FROM jsonb_array_elements(station->'bookings') x WHERE x->>'status' IN('queued','planned','started','stoppage')
  )
  SELECT count(*) FILTER(WHERE a.id IS NULL OR b.id IS NULL OR a.x->>'status' IS DISTINCT FROM b.x->>'status'
    OR a.x->>'version' IS DISTINCT FROM b.x->>'version'
    OR (a.x->>'scheduled_start_at')::timestamptz IS DISTINCT FROM (b.x->>'scheduled_start_at')::timestamptz
    OR (a.x->>'scheduled_end_at')::timestamptz IS DISTINCT FROM (b.x->>'scheduled_end_at')::timestamptz
    OR (a.x->>'actual_start_at')::timestamptz IS DISTINCT FROM (b.x->>'actual_start_at')::timestamptz
    OR (a.x->>'stoppage_started_at')::timestamptz IS DISTINCT FROM (b.x->>'stoppage_started_at')::timestamptz),
    count(a.id),count(b.id) INTO mismatches,board_count,station_count
   FROM visible_overview a FULL JOIN visible_station b USING(id);
  PERFORM pg_temp.overview_assert(mismatches=0,'station parity '||st.code,jsonb_build_object('overview',board_count,'station',station_count,'mismatches',mismatches));
 END LOOP;
 PERFORM pg_temp.overview_assert(NOT EXISTS(SELECT 1 FROM overview_before_bookings o FULL JOIN public.workshop_bookings b USING(id) WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'bookings unchanged');
 PERFORM pg_temp.overview_assert(NOT EXISTS(SELECT 1 FROM overview_before_vehicles o FULL JOIN public.vehicles v USING(id) WHERE o.row_data IS DISTINCT FROM to_jsonb(v)),'vehicles unchanged');
 PERFORM pg_temp.overview_assert(NOT EXISTS(SELECT 1 FROM overview_before_admin o FULL JOIN public.workshop_admin_blocks a USING(id) WHERE o.row_data IS DISTINCT FROM to_jsonb(a)),'admin blocks unchanged');
 PERFORM pg_temp.overview_assert(NOT EXISTS(SELECT 1 FROM overview_before_revisions o FULL JOIN public.workshop_station_revision r USING(stage_code) WHERE o.revision IS DISTINCT FROM r.revision),'station revisions unchanged');
 PERFORM pg_temp.overview_assert(NOT has_function_privilege('anon','public.get_workshop_overview_revisions()','EXECUTE'),'anonymous revision access denied');
 PERFORM pg_temp.overview_assert(public.get_workshop_overview_revisions()=(SELECT jsonb_agg(jsonb_build_object('stage_code',x->>'code','revision',x->'revision') ORDER BY ord) FROM jsonb_array_elements(snap->'stages') WITH ORDINALITY t(x,ord)),'lightweight revisions equal full overview revisions');
END $verify$;

-- Validate the lightweight endpoint under actual authenticated RLS.
GRANT SELECT,INSERT ON overview_results TO authenticated;
SET LOCAL ROLE authenticated;
DO $rls$ DECLARE c integer; blocked boolean:=false;
BEGIN
 SELECT jsonb_array_length(public.get_workshop_overview_revisions()) INTO c;
 IF c=0 THEN RAISE EXCEPTION 'Synthetic approved viewer cannot read station revisions'; END IF;
 INSERT INTO overview_results VALUES('authenticated viewer can read revision endpoint','PASS',jsonb_build_object('rows',c));
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 BEGIN PERFORM public.get_workshop_overview_revisions(); EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'Missing identity was not rejected'; END IF;
 INSERT INTO overview_results VALUES('missing authenticated identity denied','PASS','{}');
END $rls$;
RESET ROLE;
SELECT jsonb_build_object('checks',count(*),'results',jsonb_agg(to_jsonb(r) ORDER BY name)) result FROM overview_results r;
ROLLBACK;
