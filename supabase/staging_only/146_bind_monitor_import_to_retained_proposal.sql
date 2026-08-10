begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-146-monitor-source-binding',0));

do $guard$
begin
 if to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='145' and name='explicit_receipt_only_monitor_importer_and_parts_normalization')
    or exists(select 1 from supabase_migrations.schema_migrations where version='146') then
   raise exception 'PDC_MONITOR_146_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end
$guard$;

do $bind$
declare
 v_definition text;
 v_old text:=$old$ perform 1 from public.pdc_email_source_claims c where c.source_hash=v_source_hash and c.contract_name='pdc_ai_intake_063' for update;
 if not found then return public.navision_backend_response(false,'source_not_observed'); end if;$old$;
 v_new text:=$new$ perform 1
 from public.pdc_email_source_claims c
 join public.pdc_ai_intake_proposals p on p.proposal_id::text=c.proposal_ref
 where c.source_hash=v_source_hash and c.contract_name='pdc_ai_intake_063'
   and p.source_hash=v_source_hash and lower(p.evidence_hash)=v_evidence_hash and p.source_uid=v_source_uid
   and lower(p.sender_address)=v_sender and p.authentication=v_auth and p.source_received_at=p_source_received_at
   and p.subject=v_subject and public.normalize_vehicle_stock_number(p.stock_number)=v_stock
   and jsonb_typeof(p.observations->'required_work')='array'
   and jsonb_array_length(p.observations->'required_work')=jsonb_array_length(v_required_work)
   and not exists(
     select 1 from jsonb_array_elements_text(p.observations->'required_work') x
     cross join lateral (select case lower(btrim(x)) when 'bus4x4' then 'bus4x4' when 'tint' then 'tint' when 'hoist' then 'hoist'
       when 'fitting' then 'fitting' when 'fabrication' then 'fabrication' when 'electrical' then 'electrical' when 'tyre' then 'tyre'
       when 'sublet' then 'sublet' when 'pitinspection' then 'pitInspection' else null end as work_key) m
     where m.work_key is null or not (v_required_work ? m.work_key)
   )
 for update of c,p;
 if not found then return public.navision_backend_response(false,'source_proposal_binding_mismatch'); end if;$new$;
begin
 select pg_get_functiondef('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure) into v_definition;
 if obj_description('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure,'pg_proc')
      not like 'Staging v4 Monitor importer:%'
    or position(v_old in v_definition)=0
    or position($cv4$'contract_version',4$cv4$ in v_definition)=0
    or position('pdc_monitor_canonical_stock_import_145' in v_definition)=0
    or position('insert into public.vehicles' in lower(v_definition))>0
    or position('insert into public.navision_board_activations' in lower(v_definition))>0
    or position('update public.navision_board_activations' in lower(v_definition))>0
    or position('vehicle_parts_updates' in lower(v_definition))>0
    or position('workshop_bookings' in lower(v_definition))>0
    or position('pdc_ai_intake_history' in lower(v_definition))>0 then
   raise exception 'PDC_MONITOR_146_EXPLICIT_V4_DRIFT' using errcode='55000';
 end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_definition:=replace(v_definition,$cv4$'contract_version',4$cv4$,$cv5$'contract_version',5$cv5$);
 v_definition:=replace(v_definition,'pdc_monitor_canonical_stock_import_145','pdc_monitor_canonical_stock_import_146');
 execute v_definition;
end
$bind$;

revoke all on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) to authenticated;
comment on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) is
 'Staging v5 Monitor importer: v4 explicit existing-link/JC/receipt/work contract plus exact retained proposal binding for source, evidence, sender/authentication, received time, subject, Stock and required work.';

do $assert$
declare v_definition text;
begin
 select pg_get_functiondef('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure) into v_definition;
 if position('source_proposal_binding_mismatch' in v_definition)=0
    or position($cv5$'contract_version',5$cv5$ in v_definition)=0
    or position('pdc_monitor_canonical_stock_import_146' in v_definition)=0
    or position('insert into public.vehicles' in lower(v_definition))>0
    or position('insert into public.navision_board_activations' in lower(v_definition))>0
    or position('update public.navision_board_activations' in lower(v_definition))>0
    or position('vehicle_parts_updates' in lower(v_definition))>0
    or position('workshop_bookings' in lower(v_definition))>0
    or position('pdc_ai_intake_history' in lower(v_definition))>0 then
   raise exception 'PDC_MONITOR_146_POSTCONDITION_FAILED' using errcode='55000';
 end if;
end
$assert$;

insert into supabase_migrations.schema_migrations(version,name,statements) values('146','bind_monitor_import_to_retained_proposal',array[
 'bind claimed source hash to referenced retained proposal','require exact evidence sender authentication time subject Stock and normalized required work','retain explicit v4 mutation and ACL limits']);
commit;
