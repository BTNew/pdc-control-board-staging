-- Authenticated database-session authorization checks on disposable PostgreSQL.
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","email":"auditor@example.test","role":"authenticated"}',false);

create function pg_temp.auth_env4(p_instruction text,p_scope jsonb,p_delivery uuid,p_nonce text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,extensions as $$declare issued text;expires text;evidence jsonb;env jsonb;digest text;begin
 issued:=to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');expires:=to_char((clock_timestamp()+interval '2 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');digest:=encode(extensions.digest(convert_to(p_instruction,'UTF8'),'sha256'),'hex');
 evidence:=jsonb_build_object('bot_identity','pdc-auditor-staging','instruction_sha256',digest,'original_instruction',p_instruction,'telegram_chat_id',7828138290,'telegram_message_id',4,'telegram_sender_id',7828138290,'telegram_update_id',4);
 env:=jsonb_build_object('gateway_instance_id','fixture-gateway','delivery_uuid',p_delivery,'key_id','fixture-key','nonce',p_nonce,'issued_at',issued,'expires_at',expires,'instruction_sha256',digest,'selected_scope',p_scope,'telegram_evidence',evidence,'signature',repeat('0',64));
 return jsonb_set(env,'{signature}',to_jsonb(encode(extensions.hmac(public.pdc_auditor_signing_bytes_253(env),decode(repeat('42',32),'hex'),'sha256'),'hex')));end$$;
grant execute on function pg_temp.auth_env4(text,jsonb,uuid,text) to authenticated;

-- Authorised Auditor Review -> Apply -> Undo through controlled RPCs while SET ROLE authenticated.
select jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','add','apply_unambiguous',true,'selector',jsonb_build_object('vehicle_id','20000000-0000-4000-8000-000000000010'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','Authenticated RPC line','estimated_hours',0.5,'operation_code','AUTH1','work_key','pitInspection')))::text plan_scope \gset
select pg_temp.auth_env4('Authenticated Auditor review',:'plan_scope'::jsonb,'61000000-0000-4000-8000-000000000001','authenticated-auditor-plan')::text plan_env \gset
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","email":"auditor@example.test","role":"authenticated"}',false);
select public.plan_pdc_auditor_typed_instruction_253('add','apply',:'plan_scope'::jsonb,:'plan_env'::jsonb)::text plan_result \gset
reset role;
select (:'plan_result'::jsonb->'data'->>'proposal_id') proposal_id,(:'plan_result'::jsonb->'data'->>'proposal_version') proposal_version,:'plan_result'::jsonb->'data'->>'proposal_hash' proposal_hash,:'plan_result'::jsonb->'data'->>'typed_item_set_hash' typed_hash,:'plan_result'::jsonb->'data'->>'final_scope_hash' scope_hash,:'plan_result'::jsonb->'data'->>'expected_row_versions_hash' versions_hash \gset
select jsonb_build_object('contract','pdc-auditor-apply-selection-253-v1','proposal_id',:'proposal_id','proposal_version',:'proposal_version'::int,'proposal_hash',:'proposal_hash','typed_item_set_hash',:'typed_hash','final_scope_hash',:'scope_hash','expected_row_versions_hash',:'versions_hash')::text apply_scope \gset
select pg_temp.auth_env4('Apply these corrections',:'apply_scope'::jsonb,'62000000-0000-4000-8000-000000000001','authenticated-auditor-apply')::text apply_env \gset
set role authenticated;
select public.apply_pdc_auditor_typed_plan_253(:'proposal_id'::uuid,:'proposal_version'::int,:'proposal_hash',:'typed_hash',:'scope_hash',:'versions_hash',:'apply_env'::jsonb)::text apply_result \gset
reset role;
select case when :'apply_result'::jsonb->>'code'='typed_plan_applied_253' then 1 else 1/0 end authenticated_apply_ok;
select (:'apply_result'::jsonb->'data'->>'run_id') run_id \gset
select run_revision_after run_revision from public.pdc_auditor_typed_runs_253 where run_id=:'run_id'::uuid \gset
select jsonb_build_object('contract','pdc-auditor-undo-selection-253-v1','run_id',:'run_id','run_revision_after',:'run_revision')::text undo_scope \gset
select pg_temp.auth_env4('Undo the selected Auditor run',:'undo_scope'::jsonb,'63000000-0000-4000-8000-000000000001','authenticated-auditor-undo')::text undo_env \gset
set role authenticated;
select public.undo_last_pdc_auditor_typed_run_253(:'undo_env'::jsonb)::text undo_result \gset
reset role;
select case when :'undo_result'::jsonb->>'code'='typed_run_undone_253' then 1 else 1/0 end authenticated_undo_ok;

-- Build a valid untouched signed request and prove every non-Auditor database session is denied.
create temp table denied_env4(persona text primary key,user_id uuid,email text,envelope jsonb);
insert into auth.users(id,email) values
('70000000-0000-4000-8000-000000000001','viewer@example.test'),
('70000000-0000-4000-8000-000000000002','monitor@example.test'),
('70000000-0000-4000-8000-000000000003','importer@example.test'),
('70000000-0000-4000-8000-000000000004','ordinary@example.test');
insert into public.pdc_user_roles(email,role,active,auth_user_id,account_status) values
('viewer@example.test','viewer',true,'70000000-0000-4000-8000-000000000001','approved'),
('monitor@example.test','viewer',true,'70000000-0000-4000-8000-000000000002','approved'),
('importer@example.test','importer',true,'70000000-0000-4000-8000-000000000003','approved');
insert into denied_env4 select p,u,e,pg_temp.auth_env4('Denied persona review',:'plan_scope'::jsonb,('64000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'denied-persona-fixture-'||n) from (values('viewer','70000000-0000-4000-8000-000000000001'::uuid,'viewer@example.test',1),('monitor','70000000-0000-4000-8000-000000000002','monitor@example.test',2),('importer','70000000-0000-4000-8000-000000000003','importer@example.test',3),('ordinary','70000000-0000-4000-8000-000000000004','ordinary@example.test',4))x(p,u,e,n);
grant select on denied_env4 to authenticated;
set role authenticated;
do $$declare x record;begin
 for x in select * from denied_env4 loop
  perform set_config('request.jwt.claim.sub',x.user_id::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',x.user_id,'email',x.email,'role','authenticated')::text,true);
  begin perform public.plan_pdc_auditor_typed_instruction_253('add','review',x.envelope->'selected_scope',x.envelope);raise exception '% unexpectedly invoked Auditor RPC',x.persona;exception when insufficient_privilege then null;end;
 end loop;
end$$;
-- Direct writes and protected-domain changes are denied to the Auditor DB session.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","email":"auditor@example.test","role":"authenticated"}',false);
do $$begin
 begin insert into public.pdc_auditor_workshop_revisions(dealer_code,environment,event_type,run_id) values('14450','staging','telegram_plan_applied_226',gen_random_uuid());raise exception 'direct revision write succeeded';exception when insufficient_privilege then null;end;
 begin update public.vehicle_workshop_line_adjustments set description='forbidden direct write';raise exception 'direct overlay write succeeded';exception when insufficient_privilege then null;end;
 begin delete from public.vehicles where id='20000000-0000-4000-8000-000000000010';raise exception 'Auditor vehicle delete succeeded';exception when insufficient_privilege then null;end;
 begin update public.vehicles set current_location='forbidden' where id='20000000-0000-4000-8000-000000000010';raise exception 'Auditor location/date/state write succeeded';exception when insufficient_privilege then null;end;
end$$;
reset role;

-- Approved human Administrator can read Realtime revisions but cannot write.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","email":"craig@example.test","role":"authenticated"}',true);
do $$begin if (select count(*) from public.pdc_auditor_workshop_revisions)=0 then raise exception 'approved human cannot read revisions';end if;begin delete from public.pdc_auditor_workshop_revisions;raise exception 'approved human wrote revisions';exception when insufficient_privilege then null;end;end$$;
rollback;
-- Missing approval timestamp and disabled accounts fail closed for browser reads.
begin;
update public.pdc_user_roles set approved_at=null where auth_user_id='10000000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","email":"craig@example.test","role":"authenticated"}',true);
do $$begin if (select count(*) from public.pdc_auditor_workshop_revisions)<>0 then raise exception 'missing approval timestamp retained revision read';end if;end$$;
rollback;
begin;
update public.pdc_user_roles set disabled_at=clock_timestamp() where auth_user_id='10000000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","email":"craig@example.test","role":"authenticated"}',true);
do $$begin if (select count(*) from public.pdc_auditor_workshop_revisions)<>0 then raise exception 'disabled account retained revision read';end if;end$$;
rollback;
select 'AI_AUDITOR_253_AUTHENTICATED_SESSIONS_PASS' result;
