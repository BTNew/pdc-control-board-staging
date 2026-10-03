-- Karratha-only logical recovery envelope. Run through the authenticated
-- administration connection, then save the result to a PRIVATE local file.
-- Never publish this envelope or its rows in GitHub Pages/source control.
-- Deliberately excludes Auth credentials, sessions, passwords and secrets.
-- It does not claim to replace a complete project database/roles backup.
-- PostgreSQL requires a writable transaction for temporary-table creation.
-- Only pg_temp is written; all persistent relations are read and the transaction rolls back.
begin isolation level repeatable read;
set local statement_timeout = '90s';
do $$
begin
 if to_regnamespace('karratha_pdc') is null then
  raise exception 'Karratha schema is not installed';
 end if;
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='karratha_pdc' and c.relkind in ('r','p')
           and (not c.relrowsecurity or not c.relforcerowsecurity)) then
  raise exception 'Karratha recovery export requires enabled and forced RLS';
 end if;
end $$;

create temporary table karratha_recovery_rows(table_name text primary key,
 row_count bigint not null, rows jsonb not null) on commit drop;
do $$
declare t record;
begin
 for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
          where n.nspname='karratha_pdc' and c.relkind in ('r','p') order by c.relname
 loop
  execute format('insert into pg_temp.karratha_recovery_rows select %L,count(*),coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from %I.%I x',
       t.relname,'karratha_pdc',t.relname);
 end loop;
end $$;

select jsonb_build_object(
 'format','karratha-pdc-logical-envelope-v1',
 'project_ref','cdsmnqxtyyoeoznmbidd',
 'schema','karratha_pdc',
 'captured_at',clock_timestamp(),
 'schema_security',(select jsonb_build_object('owner',pg_get_userbyid(n.nspowner),'acl',n.nspacl)
   from pg_namespace n where n.nspname='karratha_pdc'),
 'default_acl',(select coalesce(jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),
   'object_type',d.defaclobjtype,'acl',d.defaclacl) order by d.defaclrole,d.defaclobjtype),'[]'::jsonb)
   from pg_default_acl d where d.defaclnamespace='karratha_pdc'::regnamespace),
 'enum_types',(select coalesce(jsonb_agg(jsonb_build_object('type',t.typname,
   'values',(select jsonb_agg(e.enumlabel order by e.enumsortorder) from pg_enum e where e.enumtypid=t.oid)) order by t.typname),'[]'::jsonb)
   from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='karratha_pdc' and t.typtype='e'),
 'scope',jsonb_build_object('private_schema_rows',true,'private_schema_definitions',true,
  'prefixed_public_rpc_definitions',true,'centre_memberships',true,
  'source_evidence',true,'navision_master_rows',false,'auth_accounts',false,
  'auth_credentials_or_sessions',false,'project_roles',false,'storage_object_bytes',false),
 'tables',(select jsonb_agg(jsonb_build_object('name',r.table_name,'row_count',r.row_count,'rows',r.rows,
   'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
     'not_null',a.attnotnull,'generated',a.attgenerated,'identity',a.attidentity,
     'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
     from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
     where a.attrelid=format('%I.%I','karratha_pdc',r.table_name)::regclass and a.attnum>0 and not a.attisdropped),
   'rls',(select jsonb_build_object('enabled',c.relrowsecurity,'forced',c.relforcerowsecurity,
     'owner',pg_get_userbyid(c.relowner),'acl',c.relacl) from pg_class c where c.oid=format('%I.%I','karratha_pdc',r.table_name)::regclass)
  ) order by r.table_name) from pg_temp.karratha_recovery_rows r),
 'constraints',(select coalesce(jsonb_agg(jsonb_build_object('table',c.conrelid::regclass::text,
   'name',c.conname,'kind',c.contype,'definition',pg_get_constraintdef(c.oid,true),
   'referenced_table',nullif(c.confrelid,0)::regclass::text,'deferrable',c.condeferrable,
   'initially_deferred',c.condeferred) order by c.conrelid::regclass::text,c.conname),'[]'::jsonb)
   from pg_constraint c join pg_namespace n on n.oid=c.connamespace where n.nspname='karratha_pdc'),
 'indexes',(select coalesce(jsonb_agg(jsonb_build_object('table',tablename,'name',indexname,
   'definition',indexdef) order by tablename,indexname),'[]'::jsonb) from pg_indexes where schemaname='karratha_pdc'),
 'policies',(select coalesce(jsonb_agg(to_jsonb(p) order by p.tablename,p.policyname),'[]'::jsonb)
   from pg_policies p where p.schemaname='karratha_pdc'),
 'functions',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,
   'arguments',pg_get_function_identity_arguments(p.oid),'owner',pg_get_userbyid(p.proowner),
   'security_definer',p.prosecdef,'acl',p.proacl,'settings',p.proconfig,
   'definition',pg_get_functiondef(p.oid)) order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),'[]'::jsonb)
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='karratha_pdc' or (n.nspname='public' and
    (p.proname like '%\_karratha\_%' escape '\' or p.proname like 'karratha\_%' escape '\'))),
 'sequences',(select coalesce(jsonb_agg(to_jsonb(s) order by s.sequencename),'[]'::jsonb)
   from pg_sequences s where s.schemaname='karratha_pdc'),
 'triggers',(select coalesce(jsonb_agg(jsonb_build_object('table',c.relname,'name',t.tgname,
   'definition',pg_get_triggerdef(t.oid,true),'enabled',t.tgenabled) order by c.relname,t.tgname),'[]'::jsonb)
   from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='karratha_pdc' and not t.tgisinternal),
 'restore_limits',jsonb_build_array('Restore only into an isolated rehearsal environment, never over live staging.',
  'The shared Navision master and Auth user identities must be restored separately and reconciled before writes are enabled.',
  'Retained Navision snapshots do not prove that the original master binding still exists.',
  'This recovery envelope contains no Storage bytes. Any future photo/file feature requires an object-byte archive.',
  'Full project restore affects PMB and Karratha together. This envelope is only a Karratha logical recovery copy.')
) as recovery_envelope;
rollback;
