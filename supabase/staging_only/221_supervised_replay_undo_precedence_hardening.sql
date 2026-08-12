-- Staging-only migration 221: replay-safe Telegram commands, current-state-safe undo, and manual-overlay precedence.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-221-supervised-hardening',0));
select public.pdc_monitor_staging_guard();
do $guard$ begin
 if not public.pdc_monitor_staging_guard()
 or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
 or to_regclass('public.pdc_production_environment_sentinel') is not null
 or not exists(select 1 from supabase_migrations.schema_migrations where version='220' and name='supervised_active_winner_repair')
 or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::integer>220)
 or exists(select 1 from supabase_migrations.schema_migrations where version='221')
 then raise exception 'PDC_221_STAGING_OR_LEDGER_MISMATCH' using errcode='55000'; end if;
end $guard$;

create table public.pdc_supervised_telegram_responses(
 command_id uuid primary key references public.pdc_supervised_telegram_commands(command_id) on delete restrict,
 response jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_supervised_telegram_responses enable row level security;
revoke all on public.pdc_supervised_telegram_responses from public,anon,authenticated,service_role;
create trigger pdc_supervised_telegram_responses_immutable before update or delete on public.pdc_supervised_telegram_responses for each row execute function public.pdc_supervised_immutable_213();

alter function public.execute_pdc_supervised_learning_command(text,jsonb,jsonb) rename to execute_pdc_supervised_learning_command_pre221;
revoke all on function public.execute_pdc_supervised_learning_command_pre221(text,jsonb,jsonb) from public,anon,authenticated,service_role;

create function public.execute_pdc_supervised_learning_command(p_action text,p_parameters jsonb,p_telegram_evidence jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_supervised_admin_scope_213(); a uuid; e text; sender bigint; chat_id bigint; message_id bigint; expected_request jsonb; prior record; result jsonb; command_uuid uuid;
begin
 if not coalesce((s->>'ok')::boolean,false) then return public.navision_backend_response(false,'unauthorized'); end if;
 a=(s->'data'->>'actor_id')::uuid; e=s->'data'->>'actor_email'; sender=(p_telegram_evidence->>'telegram_sender_id')::bigint; chat_id=(p_telegram_evidence->>'telegram_chat_id')::bigint; message_id=(p_telegram_evidence->>'telegram_message_id')::bigint;
 if not exists(select 1 from public.pdc_supervised_telegram_identities i where i.telegram_sender_id=sender and i.auth_user_id=a and lower(i.actor_email)=e and i.active) then return public.navision_backend_response(false,'unauthorized'); end if;
 perform pg_advisory_xact_lock(hashtextextended(chat_id::text||':'||message_id::text,221));
 expected_request=jsonb_build_object('parameters',p_parameters,'telegram_evidence',p_telegram_evidence);
 select c.*,r.response into prior from public.pdc_supervised_telegram_commands c left join public.pdc_supervised_telegram_responses r using(command_id) where c.telegram_chat_id=chat_id and c.telegram_message_id=message_id;
 if found then
  if prior.actor_id is distinct from a or prior.telegram_sender_id is distinct from sender or prior.action is distinct from p_action or prior.request is distinct from expected_request then return public.navision_backend_response(false,'telegram_replay_conflict'); end if;
  return coalesce(prior.response,public.navision_backend_response(prior.result_code not in('unauthorized','invalid_request','rpc_error'),prior.result_code,jsonb_build_object('replayed',true,'command_id',prior.command_id)));
 end if;
 result=public.execute_pdc_supervised_learning_command_pre221(p_action,p_parameters,p_telegram_evidence);
 select command_id into command_uuid from public.pdc_supervised_telegram_commands where telegram_chat_id=chat_id and telegram_message_id=message_id;
 if command_uuid is null then return public.navision_backend_response(false,'command_evidence_missing'); end if;
 insert into public.pdc_supervised_telegram_responses(command_id,response) values(command_uuid,result);
 return result;
exception when unique_violation then
 select c.command_id,r.response into command_uuid,result from public.pdc_supervised_telegram_commands c left join public.pdc_supervised_telegram_responses r using(command_id) where c.telegram_chat_id=chat_id and c.telegram_message_id=message_id;
 return coalesce(result,public.navision_backend_response(false,'telegram_replay_conflict'));
when others then
 insert into public.pdc_supervised_failures(rpc_name,error_code,error_detail,actor_id,actor_email,request_context) values('execute_pdc_supervised_learning_command_221',sqlstate,sqlerrm,a,e,jsonb_build_object('action',p_action,'chat_id',chat_id,'message_id',message_id));
 return public.navision_backend_response(false,'rpc_error');
end$$;
revoke all on function public.execute_pdc_supervised_learning_command(text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.execute_pdc_supervised_learning_command(text,jsonb,jsonb) to authenticated;

create or replace function public.review_pdc_supervised_email_line_213(p_operation_line_id uuid,p_operation_code text,p_description text,p_existing_work_key text) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_supervised_admin_scope_213(); r record; d text:=lower(regexp_replace(btrim(coalesce(p_description,'')),'[^a-zA-Z0-9]+',' ','g')); locked_key text;
begin
 if not coalesce((s->>'ok')::boolean,false) then s:=public.pdc_supervised_monitor_scope_213(); end if;
 if not coalesce((s->>'ok')::boolean,false) then return s; end if;
 if p_operation_line_id is not null then
  select coalesce(public.pdc_auditor_work_key_for_stage(a.stage_code),l.work_key) into locked_key
  from public.pdc_authenticated_email_operation_lines l join public.vehicle_workshop_line_adjustments a on a.vehicle_id=l.vehicle_id and a.line_key='source:'||l.operation_line_id::text
  where l.operation_line_id=p_operation_line_id;
  if found then return public.navision_backend_response(true,'existing_mapping',jsonb_build_object('operation_line_id',p_operation_line_id,'work_key',locked_key,'precedence','manual_overlay')); end if;
 end if;
 select x.* into r from public.list_pdc_supervised_rules_213(false) x left join public.pdc_supervised_rule_aliases al on al.version_id=x.version_id
 where (x.match_kind='operation_code' and x.operation_code=upper(btrim(p_operation_code))) or (x.match_kind='exact_description' and x.normalized_description=btrim(d)) or (x.match_kind='phrase' and (btrim(d) like '%'||replace(x.phrase_category,'_',' ')||'%' or btrim(d) like '%'||al.alias||'%'))
 order by case x.match_kind when 'operation_code' then 2 when 'exact_description' then 3 when 'phrase' then 4 else 9 end,x.priority desc,x.confidence desc,x.version_no desc limit 1;
 if found then return public.navision_backend_response(true,'deterministic_match',jsonb_build_object('operation_line_id',p_operation_line_id,'work_key',r.work_key,'version_id',r.version_id,'version_no',r.version_no,'precedence',r.match_kind)); end if;
 if p_existing_work_key is not null then return public.navision_backend_response(true,'existing_mapping',jsonb_build_object('work_key',p_existing_work_key,'precedence','existing_mapping')); end if;
 return public.navision_backend_response(false,'inference_review_required');
end$$;

create or replace function public.undo_pdc_supervised_correction_batch_213(p_batch_id uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_supervised_admin_scope_213(); a uuid; e text; i record; l public.pdc_authenticated_email_operation_lines%rowtype; adj public.vehicle_workshop_line_adjustments%rowtype; prev uuid; o uuid; n int:=0; skipped int:=0;
begin
 if not coalesce((s->>'ok')::boolean,false) then return s; end if; a=(s->'data'->>'actor_id')::uuid; e=s->'data'->>'actor_email';
 for i in select ci.* from public.pdc_supervised_correction_items ci where ci.batch_id=p_batch_id and (select ar.outcome from public.pdc_supervised_apply_receipts ar where ar.batch_id=p_batch_id and ar.operation_line_id=ci.operation_line_id order by ar.created_at desc,ar.receipt_id desc limit 1)='applied' loop
  select * into l from public.pdc_authenticated_email_operation_lines where operation_line_id=i.operation_line_id for share;
  if not found then skipped=skipped+1; continue; end if;
  select * into adj from public.vehicle_workshop_line_adjustments where vehicle_id=l.vehicle_id and line_key='source:'||l.operation_line_id::text for update;
  if not found or adj.stage_code is distinct from i.target_stage_code then
   insert into public.pdc_supervised_apply_receipts(batch_id,operation_line_id,outcome,detail,before_effective,actor_id,actor_email) values(p_batch_id,i.operation_line_id,'protected','undo skipped: current effective adjustment no longer equals supervised target',to_jsonb(adj),a,e); skipped=skipped+1; continue;
  end if;
  select overlay_id into prev from public.pdc_supervised_correction_overlays where item_id=i.item_id order by created_at desc,overlay_id desc limit 1;
  insert into public.pdc_supervised_correction_overlays(item_id,operation_line_id,overlay_kind,stage_code,predecessor_overlay_id,actor_id,actor_email) values(i.item_id,i.operation_line_id,'undo',i.source_stage_code,prev,a,e) returning overlay_id into o;
  update public.vehicle_workshop_line_adjustments set stage_code=i.source_stage_code,version=version+1,updated_by=a,updated_at=clock_timestamp() where adjustment_id=adj.adjustment_id returning * into adj;
  insert into public.pdc_supervised_apply_receipts(batch_id,operation_line_id,overlay_id,outcome,detail,after_effective,actor_id,actor_email) values(p_batch_id,i.operation_line_id,o,'undone',btrim(p_reason),to_jsonb(adj),a,e); n=n+1;
 end loop;
 return public.navision_backend_response(true,'correction_batch_undone',jsonb_build_object('batch_id',p_batch_id,'undone',n,'skipped',skipped));
end$$;

revoke all on function public.review_pdc_supervised_email_line_213(uuid,text,text,text),public.undo_pdc_supervised_correction_batch_213(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.review_pdc_supervised_email_line_213(uuid,text,text,text),public.undo_pdc_supervised_correction_batch_213(uuid,text) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('221','supervised_replay_undo_precedence_hardening',array[
 'Serialize Telegram command identity and return one immutable persisted response per message',
 'Reject Telegram message reuse with mismatched action, actor, sender, or canonical request',
 'Undo only when the latest receipt is applied and current adjustment still equals supervised target',
 'Manual operation-line overlay wins before supervised rule matching']);
notify pgrst,'reload schema';
commit;
