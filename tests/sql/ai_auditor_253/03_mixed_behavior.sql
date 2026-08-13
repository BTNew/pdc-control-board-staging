-- Real migration-253 functions on the disposable compatibility database.
-- This is source-debugging evidence; final approval additionally requires run_real_chain.sh.
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","email":"auditor@example.test","role":"authenticated"}',false);

create function pg_temp.envelope3(p_instruction text,p_scope jsonb,p_delivery uuid,p_nonce text) returns jsonb
language plpgsql as $$declare issued text;expires text;evidence jsonb;env jsonb;digest text;begin
 issued:=to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');expires:=to_char((clock_timestamp()+interval '2 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');digest:=encode(extensions.digest(convert_to(p_instruction,'UTF8'),'sha256'),'hex');
 evidence:=jsonb_build_object('bot_identity','pdc-auditor-staging','instruction_sha256',digest,'original_instruction',p_instruction,'telegram_chat_id',7828138290,'telegram_message_id',2,'telegram_sender_id',7828138290,'telegram_update_id',2);
 env:=jsonb_build_object('gateway_instance_id','fixture-gateway','delivery_uuid',p_delivery,'key_id','fixture-key','nonce',p_nonce,'issued_at',issued,'expires_at',expires,'instruction_sha256',digest,'selected_scope',p_scope,'telegram_evidence',evidence,'signature',repeat('0',64));
 return jsonb_set(env,'{signature}',to_jsonb(encode(extensions.hmac(public.pdc_auditor_signing_bytes_253(env),decode(repeat('42',32),'hex'),'sha256'),'hex')));end$$;

create function pg_temp.operational_state3() returns jsonb language sql stable as $$
select jsonb_build_object(
 'effective',coalesce((select jsonb_agg(to_jsonb(e) order by e.vehicle_id,e.job_card_number,e.display_order,e.operation_line_identifier) from public.pdc_effective_operation_lines e),'[]'::jsonb),
 'overlays',coalesce((select jsonb_agg(to_jsonb(a) order by a.adjustment_id) from public.vehicle_workshop_line_adjustments a),'[]'::jsonb),
 'work',coalesce((select jsonb_agg(to_jsonb(w) order by w.id) from public.vehicle_work_items w),'[]'::jsonb),
 'vehicles',coalesce((select jsonb_agg(to_jsonb(v) order by v.id) from public.vehicles v),'[]'::jsonb))$$;

create function pg_temp.logical_scopes3() returns jsonb language sql stable as $$
select jsonb_agg(public.pdc_auditor_typed_snapshot_253(
 ('20000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'J'||n::text) order by n)
from generate_series(10,15)n$$;

create temp table failure_control3(stage text primary key,seen integer not null,fail_at integer not null);
create function pg_temp.inject_failure3() returns trigger language plpgsql as $$
declare wanted text;counter integer;target integer;matches boolean:=false;
begin
 select stage,seen,fail_at into wanted,counter,target from failure_control3 limit 1;
 if not found then return new;end if;
 matches:=case wanted
  when 'before_first_mutation' then tg_table_name='vehicle_workshop_line_adjustments'
  when 'after_early_operation' then tg_table_name='vehicle_workshop_line_adjustments'
  when 'recalculation' then tg_table_name='vehicle_work_items'
  when 'receipt_creation' then tg_table_name='pdc_auditor_typed_change_receipts_253'
  when 'realtime_revision' then tg_table_name='pdc_auditor_workshop_revisions'
  when 'undo_after_reversal' then tg_table_name='vehicle_workshop_line_adjustments' and to_jsonb(new)->>'correction_origin' in('ai_auditor_rolled_back','ai_auditor')
  else false end;
 if matches then update failure_control3 set seen=seen+1 returning seen,fail_at into counter,target;if counter=target then raise exception 'fixture injected failure: %',wanted using errcode='P0001';end if;end if;
 return new;
end$$;
create trigger failure_overlay3 before insert or update on public.vehicle_workshop_line_adjustments for each row execute function pg_temp.inject_failure3();
create trigger failure_work3 before insert or update on public.vehicle_work_items for each row execute function pg_temp.inject_failure3();
create trigger failure_receipt3 before insert on public.pdc_auditor_typed_change_receipts_253 for each row execute function pg_temp.inject_failure3();
create trigger failure_revision3 before insert on public.pdc_auditor_workshop_revisions for each row execute function pg_temp.inject_failure3();

-- Unrelated protected values must survive every operation.
insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes)
select '20000000-0000-4000-8000-000000000010','tint',true,true,'10000000-0000-4000-8000-000000000003',clock_timestamp(),'protected completed fixture'
where not exists(select 1 from public.vehicle_work_items where notes='protected completed fixture');
insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,job_card_number)
select '20000000-0000-4000-8000-000000000010','manual:protected','manual','FAB','Protected manual fixture',3,true,7,'10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003','MANUAL',99,true,'manual_operator','J10'
where not exists(select 1 from public.vehicle_workshop_line_adjustments where line_key='manual:protected');

do $$declare
 scopes jsonb[]; actions text[]:=array['add','edit','split','combine','reorder','remove_duplicate'];
 proposals uuid[]:='{}'; scope jsonb; env jsonb; result jsonb; d jsonb; before_review jsonb;before_apply jsonb;after_apply jsonb;
 compose_scope jsonb;compose_result jsonb;apply_scope jsonb;apply_env jsonb;apply_result jsonb;replay jsonb;runid uuid;rev text;undo_scope jsonb;undo_env jsonb;undo_result jsonb;
 protected_work jsonb;protected_manual jsonb;i int;revision_count bigint;receipt_count bigint;failure text;failure_before jsonb;failure_after jsonb;history_before jsonb;history_after jsonb;changed_env jsonb;overlap_result jsonb;overlap_proposal uuid;overlap_proposals uuid[];
begin
 scopes:=array[
 jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','add','apply_unambiguous',true,'selector',jsonb_build_object('vehicle_id','20000000-0000-4000-8000-000000000010'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','Mixed Added','estimated_hours',1.25,'operation_code','MXA','ordered_position',2,'work_key','hoist'))),
 jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','edit','apply_unambiguous',true,'selector',jsonb_build_object('operation_ref','source:30000000-0000-4000-8000-000000000011'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','Mixed Edited','estimated_hours',2.5,'operation_code','MXE','ordered_position',4,'work_key','electrical'))),
 jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','split','apply_unambiguous',true,'selector',jsonb_build_object('operation_ref','source:30000000-0000-4000-8000-000000000012'),'desire',jsonb_build_object('children',jsonb_build_array(jsonb_build_object('description','Mixed Split A','estimated_hours',0.75,'operation_code','MXS1','work_key','fitting'),jsonb_build_object('description','Mixed Split B','estimated_hours',1.25,'operation_code','MXS2','work_key','hoist')))),
 jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','combine','apply_unambiguous',true,'selector',jsonb_build_object('operation_refs',jsonb_build_array('source:30000000-0000-4000-8000-000000000013','source:30000000-0000-4000-8000-000000000014')),'desire',jsonb_build_object('survivor_operation_ref','source:30000000-0000-4000-8000-000000000013','new_value',jsonb_build_object('description','Mixed Combined','estimated_hours',2,'operation_code','MXC','work_key','fabrication'))),
 jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','reorder','apply_unambiguous',true,'selector',jsonb_build_object('operation_refs',jsonb_build_array('source:30000000-0000-4000-8000-000000000016','source:30000000-0000-4000-8000-000000000015')),'desire',jsonb_build_object('complete_effective_set',true)),
 jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','remove_duplicate','apply_unambiguous',true,'selector',jsonb_build_object('operation_refs',jsonb_build_array('source:30000000-0000-4000-8000-000000000017','source:30000000-0000-4000-8000-000000000018')),'desire',jsonb_build_object('duplicate_proof','database_exact','survivor_operation_ref','source:30000000-0000-4000-8000-000000000017'))];
 before_review:=pg_temp.operational_state3();
 for i in 1..6 loop
  scope:=scopes[i];env:=pg_temp.envelope3('Review mixed fixture '||actions[i],scope,('51000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'mixed-review-fixture-'||i);
  result:=public.plan_pdc_auditor_typed_instruction_253(actions[i],'review',scope,env);d:=result->'data';
  if result->>'code'<>'typed_review_proposal_created' or (d->>'proposed_count')::int<1 or (d->>'ambiguous_count')::int<>0 then raise exception 'mixed Review % invalid %',actions[i],result;end if;
  proposals:=array_append(proposals,(d->>'proposal_id')::uuid);
 end loop;
 if pg_temp.operational_state3()<>before_review then raise exception 'Review mutated operational state';end if;
 -- A separately valid Edit and Split may not be composed when both reference
 -- the same source operation. The composition statement must fail atomically.
 scope:=jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','edit','apply_unambiguous',true,'selector',jsonb_build_object('operation_ref','source:30000000-0000-4000-8000-000000000012'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','Overlapping Edit','estimated_hours',2,'operation_code','MXOVER','ordered_position',1,'work_key','fitting')));
 env:=pg_temp.envelope3('Review overlapping mixed edit',scope,'51900000-0000-4000-8000-000000000001','mixed-overlap-review');
 overlap_result:=public.plan_pdc_auditor_typed_instruction_253('edit','review',scope,env);overlap_proposal:=(overlap_result->'data'->>'proposal_id')::uuid;
 overlap_proposals:=array[proposals[1],overlap_proposal,proposals[3],proposals[4],proposals[5],proposals[6]];
 compose_scope:=jsonb_build_object('contract','pdc-auditor-compose-selection-253-v1','proposal_ids',to_jsonb(overlap_proposals));env:=pg_temp.envelope3('Compose these reviewed corrections',compose_scope,'51900000-0000-4000-8000-000000000002','mixed-overlap-compose');
 begin perform public.compose_pdc_auditor_typed_plan_253(overlap_proposals,env);raise exception 'overlapping mixed composition succeeded';exception when invalid_parameter_value then if sqlerrm<>'PDC_253_COMPOSE_OVERLAPPING_OPERATION_SCOPE' then raise;end if;end;
 if pg_temp.operational_state3()<>before_review then raise exception 'rejected overlapping composition mutated operational state';end if;
 compose_scope:=jsonb_build_object('contract','pdc-auditor-compose-selection-253-v1','proposal_ids',to_jsonb(proposals));env:=pg_temp.envelope3('Compose these reviewed corrections',compose_scope,'52000000-0000-4000-8000-000000000001','mixed-compose-fixture');
 compose_result:=public.compose_pdc_auditor_typed_plan_253(proposals,env);d:=compose_result->'data';
 if compose_result->>'code'<>'typed_mixed_proposal_created' or (select array_agg(distinct operation_action order by operation_action) from public.pdc_auditor_typed_plan_items_253 where plan_id=(d->>'proposal_id')::uuid)<>array['add','combine','edit','remove_duplicate','reorder','split']::text[] then raise exception 'mixed composition invalid %',compose_result;end if;
 before_apply:=pg_temp.logical_scopes3();select to_jsonb(w) into protected_work from public.vehicle_work_items w where notes='protected completed fixture';select to_jsonb(a) into protected_manual from public.vehicle_workshop_line_adjustments a where line_key='manual:protected';
 apply_scope:=jsonb_build_object('contract','pdc-auditor-apply-selection-253-v1','proposal_id',d->>'proposal_id','proposal_version',(d->>'proposal_version')::int,'proposal_hash',d->>'proposal_hash','typed_item_set_hash',d->>'typed_item_set_hash','final_scope_hash',d->>'final_scope_hash','expected_row_versions_hash',d->>'expected_row_versions_hash');apply_env:=pg_temp.envelope3('Apply these corrections',apply_scope,'53000000-0000-4000-8000-000000000001','mixed-apply-fixture');
 -- Every failure uses this same six-action proposal and must leave all operational,
 -- ordering, totals, identifiers, receipt and revision state exactly unchanged.
 foreach failure in array array['before_first_mutation','after_early_operation','recalculation','receipt_creation','realtime_revision'] loop
  delete from failure_control3;insert into failure_control3 values(failure,0,case when failure='after_early_operation' then 2 else 1 end);
  failure_before:=pg_temp.operational_state3();history_before:=jsonb_build_object('deliveries',(select count(*) from public.pdc_auditor_signed_deliveries_253),'results',(select count(*) from public.pdc_auditor_signed_delivery_results_253),'runs',(select count(*) from public.pdc_auditor_typed_runs_253),'scopes',(select count(*) from public.pdc_auditor_typed_scope_receipts_253),'changes',(select count(*) from public.pdc_auditor_typed_change_receipts_253),'undo',(select count(*) from public.pdc_auditor_typed_undo_receipts_253),'revisions',(select count(*) from public.pdc_auditor_workshop_revisions),'audit',(select count(*) from public.audit_events));
  env:=pg_temp.envelope3('Apply these corrections',apply_scope,('53100000-0000-4000-8000-'||lpad(array_position(array['before_first_mutation','after_early_operation','recalculation','receipt_creation','realtime_revision'],failure)::text,12,'0'))::uuid,'mixed-failure-'||failure);
  begin perform public.apply_pdc_auditor_typed_plan_253((d->>'proposal_id')::uuid,(d->>'proposal_version')::int,d->>'proposal_hash',d->>'typed_item_set_hash',d->>'final_scope_hash',d->>'expected_row_versions_hash',env);raise exception 'failure stage % unexpectedly succeeded',failure;exception when raise_exception then if sqlerrm not like 'fixture injected failure:%' then raise;end if;end;
  failure_after:=pg_temp.operational_state3();history_after:=jsonb_build_object('deliveries',(select count(*) from public.pdc_auditor_signed_deliveries_253),'results',(select count(*) from public.pdc_auditor_signed_delivery_results_253),'runs',(select count(*) from public.pdc_auditor_typed_runs_253),'scopes',(select count(*) from public.pdc_auditor_typed_scope_receipts_253),'changes',(select count(*) from public.pdc_auditor_typed_change_receipts_253),'undo',(select count(*) from public.pdc_auditor_typed_undo_receipts_253),'revisions',(select count(*) from public.pdc_auditor_workshop_revisions),'audit',(select count(*) from public.audit_events));
  if failure_after<>failure_before or history_after<>history_before or protected_work<>(select to_jsonb(w) from public.vehicle_work_items w where notes='protected completed fixture') or protected_manual<>(select to_jsonb(a) from public.vehicle_workshop_line_adjustments a where line_key='manual:protected') then raise exception 'failure stage % left partial state',failure;end if;
 end loop;
 delete from failure_control3;
 select count(*) into revision_count from public.pdc_auditor_workshop_revisions;apply_result:=public.apply_pdc_auditor_typed_plan_253((d->>'proposal_id')::uuid,(d->>'proposal_version')::int,d->>'proposal_hash',d->>'typed_item_set_hash',d->>'final_scope_hash',d->>'expected_row_versions_hash',apply_env);runid:=(apply_result->'data'->>'run_id')::uuid;
 if apply_result->>'code'<>'typed_plan_applied_253' or (select count(*) from public.pdc_auditor_workshop_revisions)<>revision_count+1 then raise exception 'mixed Apply/revision invalid';end if;
 -- Exact effective fields, ordering, totals, department totals and required identifiers.
 if not exists(select 1 from public.pdc_effective_operation_lines where vehicle_id='20000000-0000-4000-8000-000000000010' and active and description='Mixed Added' and operation_code='MXA' and work_key='hoist' and estimated_hours=1.25 and display_order=2) then raise exception 'Add result wrong';end if;
 if not exists(select 1 from public.pdc_effective_operation_lines where vehicle_id='20000000-0000-4000-8000-000000000011' and active and description='Mixed Edited' and operation_code='MXE' and work_key='electrical' and estimated_hours=2.5 and display_order=4) then raise exception 'Edit result wrong';end if;
 if (select count(*) from public.pdc_effective_operation_lines where vehicle_id='20000000-0000-4000-8000-000000000012' and active and description like 'Mixed Split %')<>2 or (select sum(estimated_hours) from public.pdc_effective_operation_lines where vehicle_id='20000000-0000-4000-8000-000000000012' and active)<>2 then raise exception 'Split result/totals wrong';end if;
 if not exists(select 1 from public.pdc_effective_operation_lines where vehicle_id='20000000-0000-4000-8000-000000000013' and active and description='Mixed Combined' and operation_code='MXC' and work_key='fabrication' and estimated_hours=2) or (select count(*) from public.pdc_effective_operation_lines where vehicle_id='20000000-0000-4000-8000-000000000013' and active)<>1 then raise exception 'Combine result wrong';end if;
 if (select array_agg(operation_code order by display_order,operation_line_identifier) from public.pdc_effective_operation_lines where vehicle_id='20000000-0000-4000-8000-000000000014' and active)<>array['R2','R1']::text[] then raise exception 'Reorder wrong';end if;
 if (select count(*) from public.pdc_effective_operation_lines where vehicle_id='20000000-0000-4000-8000-000000000015' and active)<>1 then raise exception 'Remove duplicate wrong';end if;
 if not exists(select 1 from public.vehicle_work_items where vehicle_id='20000000-0000-4000-8000-000000000010' and work_key='hoist' and required) or not exists(select 1 from public.vehicle_work_items where vehicle_id='20000000-0000-4000-8000-000000000011' and work_key='electrical' and required) or not exists(select 1 from public.vehicle_work_items where vehicle_id='20000000-0000-4000-8000-000000000013' and work_key='fabrication' and required) then raise exception 'required-work identifiers wrong';end if;
 if protected_work<>(select to_jsonb(w) from public.vehicle_work_items w where notes='protected completed fixture') or protected_manual<>(select to_jsonb(a) from public.vehicle_workshop_line_adjustments a where line_key='manual:protected') then raise exception 'protected value changed';end if;
 select count(*) into receipt_count from public.pdc_auditor_typed_scope_receipts_253 where run_id=runid and before_snapshot is not null and after_snapshot is not null;if receipt_count<>6 or exists(select 1 from public.pdc_auditor_typed_change_receipts_253 where run_id=runid and (overlay_after is null or reason='' or server_rule_evidence is null)) then raise exception 'receipts incomplete';end if;
 after_apply:=pg_temp.operational_state3();replay:=public.apply_pdc_auditor_typed_plan_253((d->>'proposal_id')::uuid,(d->>'proposal_version')::int,d->>'proposal_hash',d->>'typed_item_set_hash',d->>'final_scope_hash',d->>'expected_row_versions_hash',apply_env);if replay<>apply_result or pg_temp.operational_state3()<>after_apply then raise exception 'Apply replay not idempotent';end if;
 changed_env:=pg_temp.envelope3('Apply these corrections',jsonb_set(apply_scope,'{proposal_version}','2'::jsonb),'53000000-0000-4000-8000-000000000001','mixed-apply-changed-intent');
 begin perform public.apply_pdc_auditor_typed_plan_253((d->>'proposal_id')::uuid,(d->>'proposal_version')::int,d->>'proposal_hash',d->>'typed_item_set_hash',d->>'final_scope_hash',d->>'expected_row_versions_hash',changed_env);raise exception 'changed-intent Apply replay succeeded';exception when unique_violation then null;end;
 select run_revision_after into rev from public.pdc_auditor_typed_runs_253 where run_id=runid;undo_scope:=jsonb_build_object('contract','pdc-auditor-undo-selection-253-v1','run_id',runid,'run_revision_after',rev);
 -- Force failure after multiple reversal writes would otherwise have happened.
 failure_before:=pg_temp.operational_state3();history_before:=jsonb_build_object('deliveries',(select count(*) from public.pdc_auditor_signed_deliveries_253),'results',(select count(*) from public.pdc_auditor_signed_delivery_results_253),'undo',(select count(*) from public.pdc_auditor_typed_undo_receipts_253),'revisions',(select count(*) from public.pdc_auditor_workshop_revisions),'run_state',(select undo_state from public.pdc_auditor_typed_runs_253 where run_id=runid));
 delete from failure_control3;insert into failure_control3 values('undo_after_reversal',0,3);
 env:=pg_temp.envelope3('Undo the selected Auditor run',undo_scope,'54100000-0000-4000-8000-000000000001','mixed-undo-injected-failure');
 begin perform public.undo_last_pdc_auditor_typed_run_253(env);raise exception 'injected Undo unexpectedly succeeded';exception when raise_exception then if sqlerrm not like 'fixture injected failure:%' then raise;end if;end;
 delete from failure_control3;failure_after:=pg_temp.operational_state3();history_after:=jsonb_build_object('deliveries',(select count(*) from public.pdc_auditor_signed_deliveries_253),'results',(select count(*) from public.pdc_auditor_signed_delivery_results_253),'undo',(select count(*) from public.pdc_auditor_typed_undo_receipts_253),'revisions',(select count(*) from public.pdc_auditor_workshop_revisions),'run_state',(select undo_state from public.pdc_auditor_typed_runs_253 where run_id=runid));
 if failure_after<>failure_before or history_after<>history_before then raise exception 'injected Undo left partial state';end if;
 -- Divergence and rejected Undo live in a nested transaction which is deliberately
 -- aborted after proving zero Undo receipt/revision/seal writes.
 begin
  update public.vehicle_workshop_line_adjustments set description=description||' diverged',version=version+1 where adjustment_id=(select adjustment_id from public.pdc_auditor_typed_change_receipts_253 where run_id=runid order by mutation_sequence limit 1);
  history_before:=jsonb_build_object('results',(select count(*) from public.pdc_auditor_signed_delivery_results_253),'undo',(select count(*) from public.pdc_auditor_typed_undo_receipts_253),'revisions',(select count(*) from public.pdc_auditor_workshop_revisions),'run_state',(select undo_state from public.pdc_auditor_typed_runs_253 where run_id=runid));
  begin perform public.undo_last_pdc_auditor_typed_run_253(pg_temp.envelope3('Undo the selected Auditor run',undo_scope,'54200000-0000-4000-8000-000000000001','mixed-undo-diverged-row'));raise exception 'diverged Undo unexpectedly succeeded';exception when serialization_failure then null;end;
  history_after:=jsonb_build_object('results',(select count(*) from public.pdc_auditor_signed_delivery_results_253),'undo',(select count(*) from public.pdc_auditor_typed_undo_receipts_253),'revisions',(select count(*) from public.pdc_auditor_workshop_revisions),'run_state',(select undo_state from public.pdc_auditor_typed_runs_253 where run_id=runid));if history_after<>history_before then raise exception 'diverged Undo left misleading history';end if;
  raise exception 'ROLLBACK_DIVERGENCE_FIXTURE';
 exception when raise_exception then if sqlerrm<>'ROLLBACK_DIVERGENCE_FIXTURE' then raise;end if;end;
 if pg_temp.operational_state3()<>failure_before then raise exception 'divergence fixture did not roll back';end if;
 undo_env:=pg_temp.envelope3('Undo the selected Auditor run',undo_scope,'54000000-0000-4000-8000-000000000001','mixed-undo-fixture');undo_result:=public.undo_last_pdc_auditor_typed_run_253(undo_env);
 if undo_result->>'code'<>'typed_run_undone_253' or pg_temp.logical_scopes3()<>before_apply then raise exception 'mixed exact logical Undo failed';end if;
 if protected_work<>(select to_jsonb(w) from public.vehicle_work_items w where notes='protected completed fixture') or protected_manual<>(select to_jsonb(a) from public.vehicle_workshop_line_adjustments a where line_key='manual:protected') then raise exception 'protected value changed by Undo';end if;
 begin perform public.undo_last_pdc_auditor_typed_run_253(pg_temp.envelope3('Undo the selected Auditor run',undo_scope,'54000000-0000-4000-8000-000000000002','mixed-second-undo-fixture'));raise exception 'second Undo succeeded';exception when no_data_found then null;end;
end$$;

select 'AI_AUDITOR_253_MIXED_BEHAVIOR_PASS' result;
