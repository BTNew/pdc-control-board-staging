-- Executable migration-253 behavior checks on the disposable loopback fixture only.
\set ON_ERROR_STOP on

insert into public.pdc_auditor_gateway_keys_253(gateway_instance_id,key_id,hmac_key,active,valid_from,valid_until,provisioned_by)
values('fixture-gateway','fixture-key',decode(repeat('42',32),'hex'),true,clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 hour','10000000-0000-4000-8000-000000000003');

create function pg_temp.envelope(p_instruction text,p_scope jsonb,p_delivery uuid,p_nonce text) returns jsonb
language plpgsql as $$
declare issued text; expires text; evidence jsonb; env jsonb; digest text;
begin
 issued:=to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
 expires:=to_char((clock_timestamp()+interval '2 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
 digest:=encode(extensions.digest(convert_to(p_instruction,'UTF8'),'sha256'),'hex');
 evidence:=jsonb_build_object('bot_identity','pdc-auditor-staging','instruction_sha256',digest,'original_instruction',p_instruction,'telegram_chat_id',7828138290,'telegram_message_id',1,'telegram_sender_id',7828138290,'telegram_update_id',1);
 env:=jsonb_build_object('gateway_instance_id','fixture-gateway','delivery_uuid',p_delivery,'key_id','fixture-key','nonce',p_nonce,'issued_at',issued,'expires_at',expires,'instruction_sha256',digest,'selected_scope',p_scope,'telegram_evidence',evidence,'signature',repeat('0',64));
 return jsonb_set(env,'{signature}',to_jsonb(encode(extensions.hmac(public.pdc_auditor_signing_bytes_253(env),decode(repeat('42',32),'hex'),'sha256'),'hex')));
end$$;

create function pg_temp.run_roundtrip(p_action text,p_scope jsonb,p_vehicle uuid,p_job text,p_seed integer,p_diverge boolean default false) returns void
language plpgsql as $$
declare plan_env jsonb; plan_result jsonb; d jsonb; apply_scope jsonb; apply_env jsonb; apply_result jsonb; runid uuid; rev text; undo_scope jsonb; undo_env jsonb; before_state jsonb; receipts_before bigint; revisions_before bigint;
begin
 before_state:=public.pdc_auditor_typed_snapshot_253(p_vehicle,p_job);
 plan_env:=pg_temp.envelope('Apply typed fixture action '||p_action,p_scope,('41000000-0000-4000-8000-'||lpad(p_seed::text,12,'0'))::uuid,'plan-fixture-'||lpad(p_seed::text,4,'0')||'-nonce');
 plan_result:=public.plan_pdc_auditor_typed_instruction_253(p_action,'apply',p_scope,plan_env);
 d:=plan_result->'data';
 if plan_result->>'code'<>'typed_apply_proposal_created' or (d->>'proposed_count')::int<1 or (d->>'ambiguous_count')::int<>0 then raise exception 'behavior % plan failed: %',p_action,plan_result;end if;
 apply_scope:=jsonb_build_object('contract','pdc-auditor-apply-selection-253-v1','proposal_id',d->>'proposal_id','proposal_version',(d->>'proposal_version')::int,'proposal_hash',d->>'proposal_hash','typed_item_set_hash',d->>'typed_item_set_hash','final_scope_hash',d->>'final_scope_hash','expected_row_versions_hash',d->>'expected_row_versions_hash');
 apply_env:=pg_temp.envelope('Apply these corrections',apply_scope,('42000000-0000-4000-8000-'||lpad(p_seed::text,12,'0'))::uuid,'apply-fixture-'||lpad(p_seed::text,4,'0')||'-nonce');
 apply_result:=public.apply_pdc_auditor_typed_plan_253((d->>'proposal_id')::uuid,(d->>'proposal_version')::int,d->>'proposal_hash',d->>'typed_item_set_hash',d->>'final_scope_hash',d->>'expected_row_versions_hash',apply_env);
 if apply_result->>'code'<>'typed_plan_applied_253' then raise exception 'behavior % apply failed: %',p_action,apply_result;end if;
 runid:=(apply_result->'data'->>'run_id')::uuid;select run_revision_after into rev from public.pdc_auditor_typed_runs_253 where run_id=runid;
 if public.pdc_auditor_typed_snapshot_253(p_vehicle,p_job)=before_state then raise exception 'behavior % made no logical change',p_action;end if;
 undo_scope:=jsonb_build_object('contract','pdc-auditor-undo-selection-253-v1','run_id',runid,'run_revision_after',rev);
 undo_env:=pg_temp.envelope('Undo the selected Auditor run',undo_scope,('43000000-0000-4000-8000-'||lpad(p_seed::text,12,'0'))::uuid,'undo-fixture-'||lpad(p_seed::text,4,'0')||'-nonce');
 if p_diverge then
  update public.vehicle_workshop_line_adjustments set description=description||' externally diverged',version=version+1 where adjustment_id=(select adjustment_id from public.pdc_auditor_typed_change_receipts_253 where run_id=runid order by mutation_sequence limit 1);
  select count(*) into receipts_before from public.pdc_auditor_typed_undo_receipts_253;select count(*) into revisions_before from public.pdc_auditor_workshop_revisions;
  begin perform public.undo_last_pdc_auditor_typed_run_253(undo_env);raise exception 'diverged Undo unexpectedly succeeded';exception when sqlstate '40001' then null;end;
  if receipts_before<>(select count(*) from public.pdc_auditor_typed_undo_receipts_253) or revisions_before<>(select count(*) from public.pdc_auditor_workshop_revisions) or (select undo_state from public.pdc_auditor_typed_runs_253 where run_id=runid)<>'available' then raise exception 'diverged Undo wrote partial state';end if;
  return;
 end if;
 if public.undo_last_pdc_auditor_typed_run_253(undo_env)->>'code'<>'typed_run_undone_253' then raise exception 'behavior % undo failed',p_action;end if;
 if public.pdc_auditor_typed_snapshot_253(p_vehicle,p_job)<>before_state then raise exception 'behavior % exact restoration failed',p_action;end if;
end$$;

-- One isolated vehicle per action prevents one round trip from hiding another.
insert into public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,current_location) values
('20000000-0000-4000-8000-000000000010','perm-add','S10','J10','active','YH'),
('20000000-0000-4000-8000-000000000011','perm-edit','S11','J11','active','YH'),
('20000000-0000-4000-8000-000000000012','perm-split','S12','J12','active','YH'),
('20000000-0000-4000-8000-000000000013','perm-combine','S13','J13','active','YH'),
('20000000-0000-4000-8000-000000000014','perm-reorder','S14','J14','active','YH'),
('20000000-0000-4000-8000-000000000015','perm-dedup','S15','J15','active','YH');
insert into public.fixture_vehicle_dealers select id,'14450' from public.vehicles where id::text like '20000000-0000-4000-8000-00000000001%';
insert into public.pdc_authenticated_email_operation_lines(operation_line_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint,estimated_hours,job_card_number,source_row_no) values
('30000000-0000-4000-8000-000000000010','20000000-0000-4000-8000-000000000010','ha','ua','A1','fitting','Existing add scope','fa',1,'J10',1),
('30000000-0000-4000-8000-000000000011','20000000-0000-4000-8000-000000000011','he','ue','E1','fitting','Edit me','fe',2,'J11',1),
('30000000-0000-4000-8000-000000000012','20000000-0000-4000-8000-000000000012','hs','us','S1','fitting','Split me','fs',2,'J12',1),
('30000000-0000-4000-8000-000000000013','20000000-0000-4000-8000-000000000013','hc1','uc1','C1','fitting','Combine one','fc1',1,'J13',1),
('30000000-0000-4000-8000-000000000014','20000000-0000-4000-8000-000000000013','hc2','uc2','C2','fitting','Combine two','fc2',1,'J13',2),
('30000000-0000-4000-8000-000000000015','20000000-0000-4000-8000-000000000014','hr1','ur1','R1','fitting','Reorder one','fr1',1,'J14',1),
('30000000-0000-4000-8000-000000000016','20000000-0000-4000-8000-000000000014','hr2','ur2','R2','hoist','Reorder two','fr2',1,'J14',2),
('30000000-0000-4000-8000-000000000017','20000000-0000-4000-8000-000000000015','hd1','dup-uid','D1','fitting','Duplicate exact','dup-fp',1,'J15',1),
('30000000-0000-4000-8000-000000000018','20000000-0000-4000-8000-000000000015','hd2','dup-uid','D1','fitting','Duplicate exact','dup-fp',1,'J15',2);

do $$begin
 perform pg_temp.run_roundtrip('add',jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','add','apply_unambiguous',true,'selector',jsonb_build_object('vehicle_id','20000000-0000-4000-8000-000000000010'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','Added line','estimated_hours',1,'operation_code','A2','work_key','hoist'))),'20000000-0000-4000-8000-000000000010','J10',10);
 perform pg_temp.run_roundtrip('edit',jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','edit','apply_unambiguous',true,'selector',jsonb_build_object('operation_ref','source:30000000-0000-4000-8000-000000000011'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','Edited'))),'20000000-0000-4000-8000-000000000011','J11',11);
 perform pg_temp.run_roundtrip('split',jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','split','apply_unambiguous',true,'selector',jsonb_build_object('operation_ref','source:30000000-0000-4000-8000-000000000012'),'desire',jsonb_build_object('children',jsonb_build_array(jsonb_build_object('description','Split A','estimated_hours',1,'work_key','fitting'),jsonb_build_object('description','Split B','estimated_hours',1,'work_key','hoist')))),'20000000-0000-4000-8000-000000000012','J12',12);
 perform pg_temp.run_roundtrip('combine',jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','combine','apply_unambiguous',true,'selector',jsonb_build_object('operation_refs',jsonb_build_array('source:30000000-0000-4000-8000-000000000013','source:30000000-0000-4000-8000-000000000014')),'desire',jsonb_build_object('survivor_operation_ref','source:30000000-0000-4000-8000-000000000013','new_value',jsonb_build_object('description','Combined','estimated_hours',2,'operation_code','C1','work_key','fitting'))),'20000000-0000-4000-8000-000000000013','J13',13);
 perform pg_temp.run_roundtrip('reorder',jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','reorder','apply_unambiguous',true,'selector',jsonb_build_object('operation_refs',jsonb_build_array('source:30000000-0000-4000-8000-000000000016','source:30000000-0000-4000-8000-000000000015')),'desire',jsonb_build_object('complete_effective_set',true)),'20000000-0000-4000-8000-000000000014','J14',14);
 perform pg_temp.run_roundtrip('remove_duplicate',jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','remove_duplicate','apply_unambiguous',true,'selector',jsonb_build_object('operation_refs',jsonb_build_array('source:30000000-0000-4000-8000-000000000017','source:30000000-0000-4000-8000-000000000018')),'desire',jsonb_build_object('duplicate_proof','database_exact','survivor_operation_ref','source:30000000-0000-4000-8000-000000000017')),'20000000-0000-4000-8000-000000000015','J15',15);
end$$;

-- Exact query schemas reject extra fields before envelope verification.
do $$begin
 begin perform public.query_pdc_auditor_typed_253('operation_snapshot',jsonb_build_object('contract','pdc-auditor-query-selection-253-v1','vehicle_id','20000000-0000-4000-8000-000000000010','job_card_number','J10','extra',true),'{}');raise exception 'query extra field accepted';exception when sqlstate '22023' then null;end;
end$$;

-- Exact delivery replay is idempotent, but a changed signed request reusing the
-- delivery UUID conflicts persistently.
do $$declare scope jsonb; env jsonb; changed jsonb; first_result jsonb; second_result jsonb;begin
 scope:=jsonb_build_object('contract','pdc-auditor-query-selection-253-v1','vehicle_id','20000000-0000-4000-8000-000000000010','job_card_number','J10');
 env:=pg_temp.envelope('Why was this changed',scope,'44000000-0000-4000-8000-000000000001','query-replay-fixture-nonce');
 first_result:=public.query_pdc_auditor_typed_253('operation_snapshot',scope,env);
 second_result:=public.query_pdc_auditor_typed_253('operation_snapshot',scope,env);
 if first_result<>second_result then raise exception 'exact replay changed result';end if;
 changed:=pg_temp.envelope('Why was this changed',jsonb_set(scope,'{job_card_number}','"J10-CHANGED"'),'44000000-0000-4000-8000-000000000001','query-replay-fixture-nonce-2');
 begin perform public.query_pdc_auditor_typed_253('operation_snapshot',changed->'selected_scope',changed);raise exception 'conflicting delivery replay accepted';exception when unique_violation then null;end;
end$$;

-- A forced failure during a multi-write split must roll back the entire plan,
-- delivery, run, overlay, receipt, revision and work-item statement.
insert into public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,current_location) values('20000000-0000-4000-8000-000000000021','perm-fail','S21','J21','active','YH');
insert into public.fixture_vehicle_dealers values('20000000-0000-4000-8000-000000000021','14450');
insert into public.pdc_authenticated_email_operation_lines(operation_line_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint,estimated_hours,job_card_number,source_row_no) values('30000000-0000-4000-8000-000000000021','20000000-0000-4000-8000-000000000021','hf','uf','F1','fitting','Forced failure parent','ff',2,'J21',1);
create function pg_temp.force_second_child_failure() returns trigger language plpgsql as $$begin if new.description='Split Fail B' then raise exception 'fixture forced apply failure' using errcode='P0001';end if;return new;end$$;
create trigger fixture_force_apply_failure before insert or update on public.vehicle_workshop_line_adjustments for each row execute function pg_temp.force_second_child_failure();
do $$declare p bigint;r bigint;a bigint;w bigint;v bigint;begin
 select count(*) into p from public.pdc_auditor_typed_plans_253;select count(*) into r from public.pdc_auditor_typed_runs_253;select count(*) into a from public.vehicle_workshop_line_adjustments;select count(*) into w from public.vehicle_work_items;select count(*) into v from public.pdc_auditor_workshop_revisions;
 begin perform pg_temp.run_roundtrip('split',jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','split','apply_unambiguous',true,'selector',jsonb_build_object('operation_ref','source:30000000-0000-4000-8000-000000000021'),'desire',jsonb_build_object('children',jsonb_build_array(jsonb_build_object('description','Split Fail A','estimated_hours',1,'work_key','fitting'),jsonb_build_object('description','Split Fail B','estimated_hours',1,'work_key','hoist')))),'20000000-0000-4000-8000-000000000021','J21',21);raise exception 'forced Apply unexpectedly succeeded';exception when raise_exception then if sqlerrm<>'fixture forced apply failure' then raise;end if;end;
 if p<>(select count(*) from public.pdc_auditor_typed_plans_253) or r<>(select count(*) from public.pdc_auditor_typed_runs_253) or a<>(select count(*) from public.vehicle_workshop_line_adjustments) or w<>(select count(*) from public.vehicle_work_items) or v<>(select count(*) from public.pdc_auditor_workshop_revisions) then raise exception 'forced Apply left partial writes';end if;
end$$;
drop trigger fixture_force_apply_failure on public.vehicle_workshop_line_adjustments;

-- Diverged whole-run Undo fails with no Undo receipt/revision/seal mutation.
insert into public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,current_location) values('20000000-0000-4000-8000-000000000022','perm-diverge','S22','J22','active','YH');
insert into public.fixture_vehicle_dealers values('20000000-0000-4000-8000-000000000022','14450');
insert into public.pdc_authenticated_email_operation_lines(operation_line_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint,estimated_hours,job_card_number,source_row_no) values('30000000-0000-4000-8000-000000000022','20000000-0000-4000-8000-000000000022','hv','uv','V1','fitting','Diverge me','fv',1,'J22',1);
do $$begin perform pg_temp.run_roundtrip('edit',jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','edit','apply_unambiguous',true,'selector',jsonb_build_object('operation_ref','source:30000000-0000-4000-8000-000000000022'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','Applied before divergence'))),'20000000-0000-4000-8000-000000000022','J22',22,true);end$$;

-- Browser RLS personas: only the exact approved active Administrator identity reads.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","email":"craig@example.test","role":"authenticated"}',true);
do $$begin if (select count(*) from public.pdc_auditor_workshop_revisions)=0 then raise exception 'approved Administrator cannot read revisions';end if;end$$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","email":"wrong@example.test","role":"authenticated"}',true);
do $$begin if (select count(*) from public.pdc_auditor_workshop_revisions)<>0 then raise exception 'wrong-email persona leaked revisions';end if;end$$;
rollback;

select 'AI_AUDITOR_253_SQL_BEHAVIOR_PASS' result;
