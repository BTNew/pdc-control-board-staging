-- STAGING ONLY: retained source row supplies realistic fixtures; all changes roll back.
begin;
set local statement_timeout='90s';
select set_config('request.jwt.claims','{"sub":"8a83b715-8d79-4b0e-95b2-02b55da6e8d7","email":"craig.watson@broometoyota.com.au","role":"authenticated"}',true);
create temp table key_before as select id,to_jsonb(v) state from public.vehicles v;
create function pg_temp.assert_key(ok boolean,label text) returns void language plpgsql as $f$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; end $f$;
select pg_temp.assert_key(public.pdc_tune_key_number_v1('{"Key Tag Number":503}')='503','numeric source');
select pg_temp.assert_key(public.pdc_tune_key_number_v1('{"raw_row":{"Key Tag Number":" 503.0 "}}')='503','Excel decimal source');
select pg_temp.assert_key(public.pdc_tune_key_number_v1('{"key_number":"K503"}')='K503','text key');
select pg_temp.assert_key(public.pdc_tune_key_number_v1('{"Key Tag Number":0}') is null,'zero missing');
select pg_temp.assert_key(public.pdc_tune_key_number_v1('{"Key Tag Number":"000.0"}') is null,'zero string missing');
select pg_temp.assert_key(public.pdc_tune_key_number_v1('{"Key Tag Number":""}') is null,'blank missing');
select pg_temp.assert_key(public.pdc_tune_key_number_v1('{}') is null,'absent missing');
select pg_temp.assert_key(public.pdc_tune_key_number_v1('{"Key Tag Number":"N/A"}') is null,'placeholder missing');
select pg_temp.assert_key(public.pdc_tune_source_fields_v5('{"Key Tag Number":503,"Owner Name":"Test"}')->>'key_number'='503','source extraction');
create function pg_temp.import_key(values_json jsonb,decision_text text default 'unchanged') returns jsonb language plpgsql as $f$
declare b public.pdc_pilbara_service_import_batches%rowtype; r public.pdc_pilbara_service_import_rows%rowtype; p uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); h text; vid uuid; k record;
begin
 select * into strict r from public.pdc_pilbara_service_import_rows where stock_number is not null and vehicle_id is not null and decision in('insert','unchanged') order by created_at desc limit 1;
 select * into strict b from public.pdc_pilbara_service_import_batches where batch_id=r.batch_id;
 select id into strict vid from public.vehicles where stock_number=r.stock_number and deleted_at is null;
 h:=encode(extensions.digest(p::text,'sha256'),'hex');
 insert into public.pdc_pilbara_service_import_batches select (jsonb_populate_record(null::public.pdc_pilbara_service_import_batches,to_jsonb(b)||jsonb_build_object('batch_id',p,'source_hash',h,'batch_kind','preview','idempotency_key','key-test-preview-'||p))).*;
 insert into public.pdc_pilbara_service_import_batches select (jsonb_populate_record(null::public.pdc_pilbara_service_import_batches,to_jsonb(b)||jsonb_build_object('batch_id',a,'source_hash',h,'batch_kind','apply','idempotency_key','key-test-apply-'||a))).*;
 for k in select value,ordinality from jsonb_array_elements(values_json) with ordinality loop
 insert into public.pdc_pilbara_service_import_rows select (jsonb_populate_record(null::public.pdc_pilbara_service_import_rows,to_jsonb(r)||jsonb_build_object('evidence_id',gen_random_uuid(),'batch_id',p,'source_order',k.ordinality,'original_line_number',k.ordinality,'decision',decision_text,'reason',case when decision_text='quarantine' then 'operation_update_review' else r.reason end,'normalized_payload','{}'::jsonb,'raw_row',jsonb_build_object('Key Tag Number',k.value)))).*;
 end loop;
 return public.pdc_apply_tune_key_number_v1(vid,a,p);
end $f$;
select pg_temp.assert_key(pg_temp.import_key('[987]')->>'key_number'='987','import copies key');
select pg_temp.assert_key(pg_temp.import_key('[0]')->>'key_number'='987','zero preserves existing key');
select pg_temp.assert_key(pg_temp.import_key('[""]')->>'key_number'='987','blank preserves existing key');
select pg_temp.assert_key(pg_temp.import_key('[null]')->>'key_number'='987','null preserves existing key');
select pg_temp.assert_key(pg_temp.import_key('[986]','quarantine')->>'key_number'='986','update-only operation review still copies key');
select pg_temp.assert_key((pg_temp.import_key('[986,986]')->>'changed')::boolean=false,'same-key replay does not change vehicle');
do $conflict$ begin
 begin
 perform pg_temp.import_key('[985,984]');
 raise exception 'FAIL conflict accepted';
 exception when sqlstate '22023' then
 if sqlerrm<>'conflicting_tune_key_numbers' then raise; end if;
 end;
end $conflict$;
select pg_temp.assert_key((pg_temp.import_key('[986]')->>'changed')::boolean=false,'conflicting batch made no change');
select pg_temp.assert_key(not has_function_privilege('authenticated','public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)','execute'),'no standalone client write endpoint');
select 'PASS: parser, source fields, importer write, zero/blank preservation, pending-operation key update, replay, conflict rollback and ACL' result;
rollback;
