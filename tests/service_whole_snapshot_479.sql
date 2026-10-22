-- r479 (F92) contract test: run on staging (cdsmnqxtyyoeoznmbidd) AFTER the migration, as the management connection.
-- Everything happens inside BEGIN ... ROLLBACK with synthetic R/Os (J138999xxx / J139999xxx) and synthetic stocks
-- (SYN479...); nothing is left behind and no vehicle, job, line, booking or hold is read for output or changed.
-- Prints one row per assertion (name, ok) and raises at the end if any failed.
BEGIN;
SET LOCAL lock_timeout = '2s';
CREATE TEMP TABLE r479_t(n serial, name text, ok boolean) ON COMMIT DROP;
DO $t$
DECLARE
 h1 jsonb:=jsonb_build_object('snapshot_sha256',repeat('a',64),'report_title','PMG PD Service as a Whole w/Sublet','snapshot_scope','full_open_ro_snapshot_r479',
  'source_snapshot_at','2026-10-22T03:02:00+00:00','line_count',4,'ro_count',3,'gmail_message_id','synthetic479','lib_md5',repeat('0',32));
 h2 jsonb; l1 jsonb; l2 jsonb; r jsonb; ok boolean;
BEGIN
 l1:='[["139","J139999001",1,"SYN479A",null,null,null,"linked"],["139","J139999001",2,"SYN479A",null,null,"80","linked"],
       ["139","J139999002",1,"SYN479B",null,null,"80","linked"],["138","J138999003",1,null,"SYN479X",null,null,"no_board_vehicle"]]';
 -- parts: first two lines, then all four (idempotent)
 r:=pdc_service_snapshot_private.record_snapshot_479(h1,jsonb_path_query_array(l1,'$[0 to 1]'));
 INSERT INTO r479_t(name,ok) VALUES('part 1 recorded, not complete',(r->>'lines_recorded_now')::int=2 AND NOT (r->>'complete')::boolean);
 r:=pdc_service_snapshot_private.record_snapshot_479(h1,l1);
 INSERT INTO r479_t(name,ok) VALUES('all lines, idempotent, complete',(r->>'lines_recorded_now')::int=2 AND (r->>'lines_total')::int=4 AND (r->>'complete')::boolean);
 r:=pdc_service_snapshot_private.record_snapshot_479(h1,l1);
 INSERT INTO r479_t(name,ok) VALUES('replay records nothing',(r->>'lines_recorded_now')::int=0);
 BEGIN PERFORM pdc_service_snapshot_private.record_snapshot_479(h1,'[["139","J139999001",1,"SYN479Z",null,null,null,"linked"]]'); ok:=false;
 EXCEPTION WHEN unique_violation THEN ok:=true; END;
 INSERT INTO r479_t(name,ok) VALUES('changed line value refused',ok);
 BEGIN PERFORM pdc_service_snapshot_private.record_snapshot_479(jsonb_set(h1,'{line_count}','5'),l1); ok:=false;
 EXCEPTION WHEN unique_violation THEN ok:=true; END;
 INSERT INTO r479_t(name,ok) VALUES('changed header refused',ok);
 BEGIN PERFORM pdc_service_snapshot_private.record_snapshot_479(jsonb_set(h1,'{snapshot_sha256}',to_jsonb(repeat('b',64))),'[["139","J138999001",1,"SYN",null,null,null,"linked"]]'); ok:=false;
 EXCEPTION WHEN invalid_parameter_value THEN ok:=true; END;
 INSERT INTO r479_t(name,ok) VALUES('R/O not matching its department refused',ok);
 BEGIN PERFORM pdc_service_snapshot_private.record_snapshot_479(jsonb_set(h1,'{snapshot_sha256}',to_jsonb(repeat('b',64))),'[["139","J139999001",1,null,null,null,null,"linked"]]'); ok:=false;
 EXCEPTION WHEN invalid_parameter_value THEN ok:=true; END;
 INSERT INTO r479_t(name,ok) VALUES('linked line without a stock refused',ok);
 BEGIN UPDATE pdc_service_snapshot_private.snapshot_lines_479 SET sub_status='99' WHERE snapshot_sha256=repeat('a',64); ok:=false;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN ok:=true; END;
 INSERT INTO r479_t(name,ok) VALUES('snapshot rows are append-only (UPDATE)',ok);
 BEGIN DELETE FROM pdc_service_snapshot_private.snapshots_479 WHERE snapshot_sha256=repeat('a',64); ok:=false;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN ok:=true; END;
 INSERT INTO r479_t(name,ok) VALUES('snapshot rows are append-only (DELETE)',ok);
 -- one snapshot: synthetic R/Os give one no-board-vehicle item and one all-80/99 R/O; missing items are only *_pending
 r:=pdc_service_snapshot_private.reconcile_479(NULL);
 INSERT INTO r479_t(name,ok) VALUES('reconcile, one snapshot: no-board-vehicle and 80/99 found, nothing flagged missing yet',
  (r->>'ok')::boolean AND jsonb_array_length(r->'snapshots')=1
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'category'='open_ro_no_board_vehicle' AND i->>'ro'='J138999003')
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'category'='ro_all_lines_80_99_still_open' AND i->>'ro'='J139999002')
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'category'='ro_all_lines_80_99_still_open' AND i->>'ro'='J139999001')
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'category' IN ('board_vehicle_missing','board_ro_missing')));
 -- second consecutive snapshot (an hour later): missing items are now flagged, never changed
 h2:=jsonb_set(jsonb_set(jsonb_set(h1,'{snapshot_sha256}',to_jsonb(repeat('c',64))),'{source_snapshot_at}',to_jsonb('2026-10-22T04:02:00+00:00'::text)),'{line_count}','1');
 h2:=jsonb_set(h2,'{ro_count}','1');
 r:=pdc_service_snapshot_private.record_snapshot_479(h2,'[["139","J139999001",1,"SYN479A",null,null,null,"linked"]]');
 r:=pdc_service_snapshot_private.reconcile_479(NULL);
 INSERT INTO r479_t(name,ok) VALUES('reconcile, two snapshots: window is the newest two, newest first',
  (r->>'ok')::boolean AND jsonb_array_length(r->'snapshots')=2 AND r->'snapshots'->0->>'snapshot_sha256'=repeat('c',64)
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') i WHERE i->>'category' LIKE '%\_pending'));
 r:=pdc_service_snapshot_private.reconcile_479(repeat('a',64));
 INSERT INTO r479_t(name,ok) VALUES('reconcile as of the first snapshot',(r->>'ok')::boolean AND jsonb_array_length(r->'snapshots')=1);
 r:=pdc_service_snapshot_private.reconcile_479(repeat('e',64));
 INSERT INTO r479_t(name,ok) VALUES('reconcile refuses an unknown snapshot',r->>'code'='snapshot_not_complete_or_unknown');
 INSERT INTO r479_t(name,ok) VALUES('review list rows match the reconcile items',
  (SELECT count(*) FROM pdc_service_snapshot_private.review_list_479())=jsonb_array_length(pdc_service_snapshot_private.reconcile_479(NULL)->'items'));
END $t$;
SELECT n, name, ok FROM r479_t ORDER BY n;
DO $c$ BEGIN IF EXISTS(SELECT 1 FROM r479_t WHERE ok IS NOT TRUE) THEN RAISE EXCEPTION 'r479 contract test FAILED: %',(SELECT string_agg(name,'; ') FROM r479_t WHERE ok IS NOT TRUE); END IF;
 RAISE NOTICE 'r479 contract test PASS (% assertions)',(SELECT count(*) FROM r479_t); END $c$;
ROLLBACK;
