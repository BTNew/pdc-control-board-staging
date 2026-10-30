-- r764 (F421): Broome sales My Day showed "Sales workspace exceeds supported size".
-- Cause: crm_observe logged a "workshop changed" alert whenever anything in a bay booking moved,
-- including the per-line running timers (progress.current[].elapsed_minutes) and the minute-by-minute
-- re-planning of overdue jobs. 2,488 of 2,715 workshop alerts were that noise, each carrying a full
-- copy of the line list (up to 9 KB), so the My Day payload passed its 8 MB cap on 29 Oct.
-- Fix:
--  * the sales observer stores bay bookings without the progress block (no sales page reads it);
--  * a workshop alert is only raised when stage, bay, status, actual times, a stoppage, or the
--    booked DAY (Perth) changes; same-day schedule drift updates the baseline silently;
--  * existing history is slimmed the same way and the noise alerts are removed;
--  * full backups of the three tables are kept in *_bak_r764.

-- 1. Backups (private schema, no client access).
CREATE TABLE pdc_sales_private.crm_timeline_bak_r764 AS TABLE pdc_sales_private.crm_timeline;
CREATE TABLE pdc_sales_private.crm_observations_bak_r764 AS TABLE pdc_sales_private.crm_observations;
CREATE TABLE pdc_sales_private.crm_alert_dismissals_bak_r764 AS TABLE pdc_sales_private.crm_alert_dismissals;
ALTER TABLE pdc_sales_private.crm_timeline_bak_r764 ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.crm_observations_bak_r764 ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.crm_alert_dismissals_bak_r764 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_sales_private.crm_timeline_bak_r764, pdc_sales_private.crm_observations_bak_r764,
  pdc_sales_private.crm_alert_dismissals_bak_r764 FROM PUBLIC, anon, authenticated;

-- 2. Stored shape: bay bookings without the progress block.
CREATE OR REPLACE FUNCTION pdc_sales_private.crm_workshop_facts(p jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'pg_catalog' AS $$
 SELECT CASE WHEN jsonb_typeof(p)='array' THEN coalesce((
   SELECT jsonb_agg(CASE WHEN jsonb_typeof(b)='object' THEN b-'progress' ELSE b END ORDER BY ord)
   FROM jsonb_array_elements(p) WITH ORDINALITY x(b,ord)),'[]'::jsonb) ELSE p END $$;

-- 3. Comparison shape: booked start/finish reduced to the Perth calendar day.
CREATE OR REPLACE FUNCTION pdc_sales_private.crm_workshop_day(p text)
RETURNS text LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog' AS $$
BEGIN
 IF p IS NULL OR p='' THEN RETURN NULL; END IF;
 RETURN to_char(p::timestamptz AT TIME ZONE 'Australia/Perth','YYYY-MM-DD');
EXCEPTION WHEN others THEN RETURN p;
END $$;

CREATE OR REPLACE FUNCTION pdc_sales_private.crm_workshop_compare(p jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'pg_catalog' AS $$
 SELECT CASE WHEN jsonb_typeof(p)='array' THEN coalesce((
   SELECT jsonb_agg(CASE WHEN jsonb_typeof(b)='object' THEN
     (b-ARRAY['progress','scheduled_start_at','scheduled_end_at'])
     ||jsonb_build_object('scheduled_start_day',pdc_sales_private.crm_workshop_day(b->>'scheduled_start_at'),
                          'scheduled_end_day',pdc_sales_private.crm_workshop_day(b->>'scheduled_end_at'))
     ELSE b END ORDER BY b->>'booking_id',ord)
   FROM jsonb_array_elements(p) WITH ORDINALITY x(b,ord)),'[]'::jsonb) ELSE p END $$;

REVOKE ALL ON FUNCTION pdc_sales_private.crm_workshop_facts(jsonb), pdc_sales_private.crm_workshop_day(text),
  pdc_sales_private.crm_workshop_compare(jsonb) FROM PUBLIC, anon, authenticated;

-- 4. Observer: same as before except the workshop group (store slim, alert only on a real change).
CREATE OR REPLACE FUNCTION pdc_sales_private.crm_observe(p_items jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); item jsonb; v_facts jsonb; prior pdc_sales_private.crm_observations; group_key text; old_group jsonb; new_group jsonb; event_key text; title text; inserted integer;
BEGIN
 -- This internal function only observes server-authorised snapshots, never client data.
 FOR item IN SELECT value FROM jsonb_array_elements(p_items) ORDER BY value->>'tracking_id' LOOP
  v_facts:=jsonb_build_object('stock',coalesce(item->>'stock',''),
   'eta',jsonb_build_object('kewdale_eta',item->>'kewdale_eta','dealer_eta',item->>'dealer_eta','port_plant_eta',item->>'port_plant_eta'),
   'location',jsonb_build_object('toyota_status',item->>'toyota_status','location_status',item->>'location_status','pmb_location',item->>'pmb_location','pmb_stage',item->>'pmb_stage','workshop_status',item->>'workshop_status','pmb_arrival_date',item->>'pmb_arrival_date','dealer_delivered_date',item->>'dealer_delivered_date'),
   'workshop',pdc_sales_private.crm_workshop_facts(coalesce(item->'bay_bookings','[]'::jsonb)),
   'parts',CASE WHEN jsonb_typeof(item->'parts')='object' THEN (item->'parts')-ARRAY['snapshot_at','confirmed_at','updated_at','jobs'] ELSE 'null'::jsonb END);
  INSERT INTO pdc_sales_private.crm_observations(tracking_id,facts) VALUES((item->>'tracking_id')::uuid,v_facts) ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS inserted=ROW_COUNT;
  SELECT * INTO prior FROM pdc_sales_private.crm_observations WHERE tracking_id=(item->>'tracking_id')::uuid FOR UPDATE;
  IF inserted=1 THEN
   INSERT INTO pdc_sales_private.crm_timeline(tracking_id,event_type,title,details,is_alert,observed_by)
   VALUES(prior.tracking_id,'tracking_started','Tracking started',jsonb_build_object('observed',v_facts),false,auth.uid());
   CONTINUE;
  END IF;
  FOREACH group_key IN ARRAY ARRAY['stock','eta','location','workshop','parts'] LOOP
   old_group:=prior.facts->group_key; new_group:=v_facts->group_key;
   IF group_key='workshop' THEN
    old_group:=pdc_sales_private.crm_workshop_facts(old_group);
    -- r764: timers ticking or same-day re-planning is not a sales alert; the baseline still moves on.
    IF pdc_sales_private.crm_workshop_compare(old_group) IS NOT DISTINCT FROM pdc_sales_private.crm_workshop_compare(new_group) THEN CONTINUE; END IF;
   END IF;
   IF old_group IS NOT DISTINCT FROM new_group THEN CONTINUE; END IF;
   IF group_key='stock' THEN
    event_key:=CASE WHEN coalesce(prior.facts->>'stock','')='' AND coalesce(v_facts->>'stock','')<>'' THEN 'stock_allocated' ELSE 'stock_changed' END;
    title:=CASE WHEN event_key='stock_allocated' THEN 'Stock number allocated' ELSE 'Stock number changed' END;
   ELSE
    event_key:=CASE group_key WHEN 'eta' THEN 'eta_changed' WHEN 'location' THEN 'location_changed' WHEN 'workshop' THEN 'workshop_changed' ELSE 'parts_changed' END;
    title:=CASE group_key WHEN 'eta' THEN 'ETA changed' WHEN 'location' THEN 'Vehicle location or status changed' WHEN 'workshop' THEN 'Workshop booking or progress changed' ELSE 'Parts status changed' END;
   END IF;
   INSERT INTO pdc_sales_private.crm_timeline(tracking_id,event_type,title,details,observed_by)
   VALUES(prior.tracking_id,event_key,title,jsonb_build_object('before',old_group,'after',new_group),auth.uid());
  END LOOP;
  IF prior.facts IS DISTINCT FROM v_facts THEN UPDATE pdc_sales_private.crm_observations SET facts=v_facts,last_observed_at=clock_timestamp() WHERE tracking_id=prior.tracking_id; END IF;
 END LOOP;
END $function$;

-- 5. Remove the noise alerts (and their dismissals), then slim what is left.
CREATE TEMP TABLE r764_noise ON COMMIT DROP AS
 SELECT id FROM pdc_sales_private.crm_timeline
 WHERE event_type='workshop_changed'
   AND pdc_sales_private.crm_workshop_compare(details->'before') IS NOT DISTINCT FROM pdc_sales_private.crm_workshop_compare(details->'after');
DELETE FROM pdc_sales_private.crm_alert_dismissals WHERE event_id IN (SELECT id FROM r764_noise);
DELETE FROM pdc_sales_private.crm_timeline WHERE id IN (SELECT id FROM r764_noise);

UPDATE pdc_sales_private.crm_timeline
 SET details=jsonb_build_object('before',pdc_sales_private.crm_workshop_facts(details->'before'),'after',pdc_sales_private.crm_workshop_facts(details->'after'))
 WHERE event_type='workshop_changed' AND details::text LIKE '%"progress"%';
UPDATE pdc_sales_private.crm_timeline
 SET details=jsonb_set(details,'{observed,workshop}',pdc_sales_private.crm_workshop_facts(details->'observed'->'workshop'))
 WHERE event_type='tracking_started' AND jsonb_typeof(details->'observed'->'workshop')='array' AND details::text LIKE '%"progress"%';
UPDATE pdc_sales_private.crm_observations
 SET facts=jsonb_set(facts,'{workshop}',pdc_sales_private.crm_workshop_facts(facts->'workshop'))
 WHERE jsonb_typeof(facts->'workshop')='array' AND facts::text LIKE '%"progress"%';

-- 6. Lock the observer and add the daily regression check.
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note)
SELECT 'pdc_sales_private.crm_observe(jsonb)',md5(p.prosrc),'r764','Sales observer: no workshop alert for timers or same-day re-planning'
FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_sales_private.crm_observe(jsonb)')
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=EXCLUDED.prosrc_md5,release=EXCLUDED.release,note=EXCLUDED.note,updated_at=now()
 WHERE pdc_ops.expected_function_md5.signature=EXCLUDED.signature;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in)
VALUES('sales_workspace_size_764','F421',
 'My Day must stay well under its 8 MB cap: no workshop alert whose only change is timers or same-day re-planning, and the stored history stays small.',
 $c$WITH n AS (
   SELECT count(*) noise FROM pdc_sales_private.crm_timeline
   WHERE event_type='workshop_changed' AND occurred_at>now()-interval '7 days'
     AND pdc_sales_private.crm_workshop_compare(details->'before') IS NOT DISTINCT FROM pdc_sales_private.crm_workshop_compare(details->'after')),
 s AS (SELECT coalesce(sum(octet_length(details::text)),0) bytes FROM (SELECT details FROM pdc_sales_private.crm_timeline ORDER BY occurred_at DESC LIMIT 3000) t)
 SELECT n.noise=0 AND s.bytes<4000000, 'noise alerts 7d='||n.noise||', latest 3000 events='||s.bytes||' bytes (limit 4000000)' FROM n,s$c$,
 true,545,'r764');
