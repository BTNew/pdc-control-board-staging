-- Staging only: independent Karratha PDC, shared Navision read-only.
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- Must be the first SQL inside root's single REPEATABLE READ apply transaction.
-- Snapshots existing object OIDs only: additive Karratha objects are excluded.
-- Per-row hashes avoid constructing one enormous customer/source JSON array.
create temporary table karratha_protected_catalog(kind text,object_id oid,fingerprint text,
 primary key(kind,object_id)) on commit drop;
insert into pg_temp.karratha_protected_catalog
 select 'function',p.oid,md5(concat_ws('|',pg_get_functiondef(p.oid),p.proowner::text,p.proacl::text,p.proconfig::text))
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','pdc_sales_private') and p.prokind='f';
insert into pg_temp.karratha_protected_catalog
 select 'relation',c.oid,md5(to_jsonb(c)::text)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','pdc_sales_private','auth','storage') and c.relkind in ('r','p','v','m','S','i','I','f');
insert into pg_temp.karratha_protected_catalog
 select 'index',i.indexrelid,md5(to_jsonb(i)::text)
 from pg_index i join pg_class c on c.oid=i.indrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','pdc_sales_private','auth','storage');
insert into pg_temp.karratha_protected_catalog
 select 'constraint',c.oid,md5(to_jsonb(c)::text)
 from pg_constraint c join pg_namespace n on n.oid=c.connamespace
 where n.nspname in ('public','pdc_sales_private','auth','storage');
insert into pg_temp.karratha_protected_catalog
 select 'trigger',t.oid,md5(to_jsonb(t)::text)
 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','pdc_sales_private','auth','storage');
insert into pg_temp.karratha_protected_catalog
 select 'policy',p.oid,md5(to_jsonb(p)::text)
 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','pdc_sales_private','auth','storage');
insert into pg_temp.karratha_protected_catalog
 select 'namespace',n.oid,md5(to_jsonb(n)::text)
 from pg_namespace n where n.nspname in ('public','pdc_sales_private','auth','storage');
insert into pg_temp.karratha_protected_catalog
 select 'roles',r.oid,md5(to_jsonb(r)::text) from pg_roles r;
create temporary table karratha_protected_columns(object_id oid,attribute_number int,fingerprint text,
 primary key(object_id,attribute_number)) on commit drop;
insert into pg_temp.karratha_protected_columns
 select a.attrelid,a.attnum,md5(to_jsonb(a)::text||coalesce(pg_get_expr(d.adbin,d.adrelid),''))
 from pg_attribute a join pg_temp.karratha_protected_catalog p on p.kind='relation' and p.object_id=a.attrelid
 left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attnum>0 and not a.attisdropped;
create temporary table karratha_protected_role_bindings(fingerprint text) on commit drop;
insert into pg_temp.karratha_protected_role_bindings select md5(coalesce(string_agg(to_jsonb(m)::text,E'\n' order by m.roleid,m.member,m.grantor),'')) from pg_auth_members m;
create temporary table karratha_protected_defaults(object_id oid,fingerprint text,primary key(object_id)) on commit drop;
insert into pg_temp.karratha_protected_defaults
 select d.oid,md5(to_jsonb(d)::text) from pg_default_acl d where d.defaclnamespace in
 (select object_id from pg_temp.karratha_protected_catalog where kind='namespace') or d.defaclnamespace=0;
create temporary table karratha_protected_counts(kind text primary key,total bigint) on commit drop;
insert into pg_temp.karratha_protected_counts select kind,count(*) from pg_temp.karratha_protected_catalog
 where kind in ('relation','index','constraint','trigger','policy','roles','namespace') group by kind;
insert into pg_temp.karratha_protected_counts select 'defaults',count(*) from pg_temp.karratha_protected_defaults;

create temporary table karratha_protected_data(object_id oid,schema_name text,table_name text,row_count bigint,
 row_hash text,primary key(object_id)) on commit drop;
do $boundary$
declare t record;
begin
 for t in select c.oid,n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where c.relkind in ('r','p') and (
  n.nspname='pdc_sales_private' or
  (n.nspname='public' and (c.relname in ('vehicles','salespeople','navision_backend_records','navision_board_activations',
   'navision_import_batches','pdc_user_roles','pdc_importer_grants','vehicle_master_source_records','vehicle_parts_updates',
   'vehicle_work_items','vehicle_workshop_operations','vehicle_stage_estimates','vehicle_master_identity_aliases',
   'pdc_new_vehicle_reviews','pdc_tune_intake_current_v5','pdc_tune_intake_evidence_v5','pdc_tune_operation_change_reviews')
   or c.relname like 'workshop\_%' escape '\' or c.relname like 'pdc\_role\_%' escape '\'
   or c.relname like 'pdc\_user\_%' escape '\' or c.relname like 'pdc\_settings%' escape '\')))
 order by n.nspname,c.relname loop
  execute format('insert into pg_temp.karratha_protected_data select %s,%L,%L,count(*),md5(coalesce(string_agg(h,'''' order by h),'''')) from (select md5(to_jsonb(x)::text) h from %I.%I x) q',
   t.oid,t.nspname,t.relname,t.nspname,t.relname);
 end loop;
end $boundary$;

-- Additive Karratha PDC only. Root generates/applies the reviewed migration.
-- Shared Navision/Auth are read-only; no existing PMB object is changed.
DO $guard$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR current_setting('app.environment',true)='production' THEN RAISE EXCEPTION 'Exact staging project required'; END IF;
 IF to_regnamespace('karratha_pdc') IS NOT NULL THEN RAISE EXCEPTION 'Karratha namespace already exists'; END IF;
END $guard$;
CREATE SCHEMA karratha_pdc;
REVOKE ALL ON SCHEMA karratha_pdc FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE karratha_pdc.revision(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),revision bigint NOT NULL DEFAULT 1);
INSERT INTO karratha_pdc.revision VALUES(true,1);
CREATE TABLE karratha_pdc.memberships(
 id uuid PRIMARY KEY,email text NOT NULL UNIQUE,display_name text NOT NULL,
 role text NOT NULL CHECK(role IN('administrator','operator','viewer')),active boolean NOT NULL DEFAULT true,
 version integer NOT NULL DEFAULT 1,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE karratha_pdc.settings(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),key text NOT NULL UNIQUE,value jsonb NOT NULL,version integer NOT NULL DEFAULT 1,
 updated_at timestamptz NOT NULL DEFAULT now(),updated_by uuid
);
INSERT INTO karratha_pdc.settings(key,value) VALUES
 ('calendar','{"timezone":"Australia/Perth","working_week":[1,2,3,4,5],"day_start":"06:00","day_end":"16:30","scheduling_increment_minutes":15,"break_windows":[],"closures":[],"future_only":true}'),
 ('import_contract','{"mapping_verified":false,"store_code":"135","source_system":"nuvu","allowed_dealer_codes":[],"column_mapping":{}}');
CREATE TABLE karratha_pdc.stages(stage_code text PRIMARY KEY,display_name text NOT NULL,is_physical boolean NOT NULL);
INSERT INTO karratha_pdc.stages VALUES
 ('TINT','Tint',true),('HOIST','Hoist',true),('FITTING','Fitting',true),('FABRICATION','Fabrication',true),
 ('ELECTRICAL','Electrical',true),('TYRE','Tyre',true),('PARTS','Parts',false),('SUBLET','Sublet',false),
 ('REFERENCE','Reference only',false),('REVIEW','Needs review',false);
CREATE TABLE karratha_pdc.technicians(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),name text NOT NULL CHECK(length(name) BETWEEN 1 AND 120),
 active boolean NOT NULL DEFAULT true,stage_codes text[] NOT NULL,leave_dates date[] NOT NULL DEFAULT '{}',
 version integer NOT NULL DEFAULT 1,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE karratha_pdc.bays(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),stage_code text NOT NULL REFERENCES karratha_pdc.stages,
 bay_number integer NOT NULL,code text NOT NULL UNIQUE,display_name text NOT NULL,active boolean NOT NULL DEFAULT true,
 efficiency_percent integer NOT NULL DEFAULT 100 CHECK(efficiency_percent BETWEEN 10 AND 200),
 default_technician_id uuid REFERENCES karratha_pdc.technicians,version integer NOT NULL DEFAULT 1,
 UNIQUE(stage_code,bay_number)
);
CREATE INDEX bays_technician_idx ON karratha_pdc.bays(default_technician_id);
INSERT INTO karratha_pdc.bays(stage_code,bay_number,code,display_name)
 SELECT stage,n,stage||'-BAY-'||lpad(n::text,2,'0'),'Bay '||lpad(n::text,2,'0')
 FROM (VALUES('TINT',2),('HOIST',3),('FITTING',5),('FABRICATION',13),('ELECTRICAL',10),('TYRE',2)) x(stage,total)
 CROSS JOIN LATERAL generate_series(1,total) n;
CREATE TABLE karratha_pdc.import_previews(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),file_name text NOT NULL,file_sha256 text NOT NULL,request_hash text NOT NULL,
 resolution_hash text NOT NULL,contract_version integer NOT NULL,contract_hash text NOT NULL,payload_rows jsonb NOT NULL,result jsonb NOT NULL,created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(file_sha256,contract_hash,request_hash,resolution_hash)
);
CREATE INDEX previews_actor_idx ON karratha_pdc.import_previews(created_by);
CREATE TABLE karratha_pdc.import_receipts(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),preview_id uuid NOT NULL UNIQUE REFERENCES karratha_pdc.import_previews,
 result jsonb NOT NULL,created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX imports_actor_idx ON karratha_pdc.import_receipts(created_by);
CREATE TABLE karratha_pdc.vehicles(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),navision_record_id uuid UNIQUE,source_identity jsonb,source_snapshot jsonb NOT NULL DEFAULT '{}',
 stock_number text NOT NULL,location text NOT NULL DEFAULT 'incoming'
 CHECK(location IN('incoming','yard_hold','in_transit','on_site','qc','rft','collected')),
 eta date,version integer NOT NULL DEFAULT 1,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
-- Deliberate logical binding: no foreign key to Navision, PMB vehicles or Auth.
CREATE TABLE karratha_pdc.jobcards(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),vehicle_id uuid REFERENCES karratha_pdc.vehicles,
 source_system text NOT NULL DEFAULT 'nuvu' CHECK(source_system='nuvu'),store_code text NOT NULL CHECK(store_code='135'),
 job_card_number text NOT NULL,stock_number text NOT NULL,identity_status text NOT NULL CHECK(identity_status IN('matched','unmatched','conflict')),
 source_binding jsonb NOT NULL DEFAULT '{}',source_batch_id uuid NOT NULL REFERENCES karratha_pdc.import_previews,
 selected boolean NOT NULL DEFAULT false,selection_at timestamptz,selected_by uuid,
 qc_passed boolean NOT NULL DEFAULT false,qc_at timestamptz,qc_by uuid,
 source_changed boolean NOT NULL DEFAULT false,version integer NOT NULL DEFAULT 1,
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(source_system,store_code,job_card_number)
);
CREATE INDEX jobcards_vehicle_idx ON karratha_pdc.jobcards(vehicle_id);
CREATE INDEX jobcards_batch_idx ON karratha_pdc.jobcards(source_batch_id);
CREATE TABLE karratha_pdc.operations(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),job_id uuid NOT NULL REFERENCES karratha_pdc.jobcards,
 vehicle_id uuid REFERENCES karratha_pdc.vehicles,source_key text NOT NULL,
 original_line_number integer,description text NOT NULL,source_estimated_hours numeric,
 source_row jsonb NOT NULL,observed_source_row jsonb NOT NULL,observed_hash text NOT NULL,
 estimated_hours numeric CHECK(estimated_hours BETWEEN 0 AND 999.99),
 stage_code text NOT NULL DEFAULT 'REVIEW' REFERENCES karratha_pdc.stages,
 parts_required boolean,parts_ordered boolean NOT NULL DEFAULT false,parts_received boolean NOT NULL DEFAULT false,
 parts_eta date,parts_location text NOT NULL DEFAULT '',parts_notes text NOT NULL DEFAULT '',
 completed_at timestamptz,completed_by uuid,source_changed boolean NOT NULL DEFAULT false,
 version integer NOT NULL DEFAULT 1,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(job_id,source_key)
);
CREATE INDEX operations_vehicle_idx ON karratha_pdc.operations(vehicle_id);
CREATE INDEX operations_stage_idx ON karratha_pdc.operations(stage_code);
CREATE TABLE karratha_pdc.bookings(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),operation_id uuid NOT NULL REFERENCES karratha_pdc.operations,
 job_id uuid NOT NULL REFERENCES karratha_pdc.jobcards,vehicle_id uuid NOT NULL REFERENCES karratha_pdc.vehicles,
 bay_id uuid NOT NULL REFERENCES karratha_pdc.bays,technician_id uuid NOT NULL REFERENCES karratha_pdc.technicians,
 stage_code text NOT NULL,start_at timestamptz NOT NULL,end_at timestamptz NOT NULL CHECK(end_at>start_at),
 segments jsonb NOT NULL,status text NOT NULL DEFAULT 'planned' CHECK(status IN('planned','started','stopped','completed','cancelled')),
 started_at timestamptz,completed_at timestamptz,stoppage_reason text NOT NULL DEFAULT '',
 version integer NOT NULL DEFAULT 1,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX bookings_active_operation_idx ON karratha_pdc.bookings(operation_id) WHERE status IN('planned','started','stopped');
CREATE INDEX bookings_operation_idx ON karratha_pdc.bookings(operation_id);
CREATE INDEX bookings_job_idx ON karratha_pdc.bookings(job_id);
CREATE INDEX bookings_vehicle_idx ON karratha_pdc.bookings(vehicle_id);
CREATE INDEX bookings_bay_idx ON karratha_pdc.bookings(bay_id,start_at);
CREATE INDEX bookings_tech_idx ON karratha_pdc.bookings(technician_id,start_at);
CREATE TABLE karratha_pdc.history(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),entity_type text NOT NULL,entity_id uuid NOT NULL,
 action text NOT NULL,details jsonb NOT NULL,actor_id uuid NOT NULL,actor_name text NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX history_actor_idx ON karratha_pdc.history(actor_id);
CREATE INDEX history_entity_idx ON karratha_pdc.history(entity_type,entity_id,created_at DESC);
CREATE TABLE karratha_pdc.request_receipts(
 actor_id uuid NOT NULL,request_id uuid NOT NULL,request_hash text NOT NULL,result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(actor_id,request_id)
);
CREATE FUNCTION karratha_pdc.immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
 BEGIN RAISE EXCEPTION 'Immutable Karratha evidence'; END $f$;
CREATE TRIGGER immutable_preview BEFORE UPDATE OR DELETE ON karratha_pdc.import_previews FOR EACH ROW EXECUTE FUNCTION karratha_pdc.immutable();
CREATE TRIGGER immutable_import_receipt BEFORE UPDATE OR DELETE ON karratha_pdc.import_receipts FOR EACH ROW EXECUTE FUNCTION karratha_pdc.immutable();
CREATE TRIGGER immutable_history BEFORE UPDATE OR DELETE ON karratha_pdc.history FOR EACH ROW EXECUTE FUNCTION karratha_pdc.immutable();
CREATE TRIGGER immutable_request BEFORE UPDATE OR DELETE ON karratha_pdc.request_receipts FOR EACH ROW EXECUTE FUNCTION karratha_pdc.immutable();
CREATE FUNCTION karratha_pdc.preserve_source() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
 BEGIN
 IF NEW.source_key IS DISTINCT FROM OLD.source_key OR NEW.source_row IS DISTINCT FROM OLD.source_row
 OR NEW.original_line_number IS DISTINCT FROM OLD.original_line_number OR NEW.description IS DISTINCT FROM OLD.description
 OR NEW.source_estimated_hours IS DISTINCT FROM OLD.source_estimated_hours OR NEW.job_id IS DISTINCT FROM OLD.job_id THEN
 RAISE EXCEPTION 'Original NuVu operation evidence cannot change'; END IF; RETURN NEW;
 END $f$;

CREATE FUNCTION karratha_pdc.save(p_action text,p_id uuid,p_expected_version integer,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,karratha_pdc AS $f$
DECLARE v_ctx jsonb:=karratha_pdc.context();v_nonce uuid;v_hash text;v_receipt karratha_pdc.request_receipts;
v_job karratha_pdc.jobcards;v_op karratha_pdc.operations;v_vehicle karratha_pdc.vehicles;v_booking karratha_pdc.bookings;
v_tech karratha_pdc.technicians;v_bay karratha_pdc.bays;v_setting karratha_pdc.settings;v_member karratha_pdc.memberships;
v_record jsonb;v_before jsonb;v_result jsonb;v_revision bigint;v_entity text;v_id uuid;v_stage text;v_hours numeric;
v_bool boolean;v_parts boolean;v_start timestamptz;v_plan jsonb;v_value jsonb;v_key text;v_email text;v_role text;v_user record;
v_codes text[];v_dates date[];v_location text;v_item jsonb;v_last time;
BEGIN
IF NOT(v_ctx->>'can_edit')::boolean THEN RAISE EXCEPTION 'Karratha editor approval required' USING errcode='42501';END IF;
IF jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR octet_length(p_data::text)>32768 OR nullif(p_data->>'request_id','') IS NULL
OR p_expected_version IS NULL OR p_expected_version<0 THEN RAISE EXCEPTION 'Bounded versioned request and request UUID required';END IF;
v_nonce:=(p_data->>'request_id')::uuid;
v_hash:=encode(extensions.digest(convert_to(jsonb_build_array(p_action,p_id,p_expected_version,p_data)::text,'UTF8'),'sha256'),'hex');
PERFORM pg_advisory_xact_lock(hashtextextended('karratha_pdc:mutation',0));v_ctx:=karratha_pdc.context();
IF NOT(v_ctx->>'can_edit')::boolean THEN RAISE EXCEPTION 'Karratha editor approval required' USING errcode='42501';END IF;
SELECT * INTO v_receipt FROM karratha_pdc.request_receipts WHERE actor_id=auth.uid() AND request_id=v_nonce;
IF v_receipt.request_id IS NOT NULL THEN
IF v_receipt.request_hash<>v_hash THEN RAISE EXCEPTION 'Request UUID was reused with different data';END IF;
RETURN v_receipt.result||jsonb_build_object('replay',true);END IF;
IF p_action IN('technician','bay','setting','membership') AND NOT(v_ctx->>'can_admin')::boolean THEN RAISE EXCEPTION 'Karratha administrator approval required' USING errcode='42501';END IF;
CASE p_action
WHEN 'job_selection' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','selected']);
SELECT * INTO v_job FROM karratha_pdc.jobcards WHERE id=p_id FOR UPDATE;
IF v_job.id IS NULL OR v_job.version<>p_expected_version THEN RAISE EXCEPTION 'Job card changed; refresh before saving';END IF;
IF jsonb_typeof(p_data->'selected') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Selection must be explicit';END IF;
v_bool:=(p_data->>'selected')::boolean;
IF v_bool THEN PERFORM karratha_pdc.ready_job(v_job.id,false);
ELSIF EXISTS(SELECT 1 FROM karratha_pdc.bookings WHERE job_id=v_job.id AND status IN('planned','started','stopped')) THEN
RAISE EXCEPTION 'Cancel planned work and resolve protected bookings before deselection';END IF;
v_before:=to_jsonb(v_job);
UPDATE karratha_pdc.jobcards SET selected=v_bool,selection_at=CASE WHEN v_bool THEN now() END,selected_by=CASE WHEN v_bool THEN auth.uid() END,
version=version+1,updated_at=now() WHERE id=v_job.id RETURNING to_jsonb(jobcards) INTO v_record;v_entity:='job';
WHEN 'operation' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','stage_code','estimated_hours','parts_required']);
SELECT * INTO v_op FROM karratha_pdc.operations WHERE id=p_id FOR UPDATE;
IF v_op.id IS NULL OR v_op.version<>p_expected_version THEN RAISE EXCEPTION 'Operation changed; refresh before saving';END IF;
v_stage:=upper(karratha_pdc.text_value(p_data->>'stage_code',30,true));
IF NOT EXISTS(SELECT 1 FROM karratha_pdc.stages WHERE stage_code=v_stage AND stage_code<>'REVIEW') THEN RAISE EXCEPTION 'Choose a supported Karratha stage';END IF;
v_hours:=nullif(p_data->>'estimated_hours','')::numeric;
IF v_hours IS NOT NULL AND (v_hours<0 OR v_hours>999.99) THEN RAISE EXCEPTION 'Invalid approved hours';END IF;
IF EXISTS(SELECT 1 FROM karratha_pdc.stages WHERE stage_code=v_stage AND is_physical) AND (v_hours IS NULL OR v_hours<=0) THEN RAISE EXCEPTION 'Physical work needs supported positive hours';END IF;
IF v_stage='REFERENCE' AND coalesce(v_hours,0)<>0 THEN RAISE EXCEPTION 'Reference-only lines do not contain workshop labour';END IF;
IF jsonb_typeof(p_data->'parts_required') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Confirm whether parts are required';END IF;
v_parts:=(p_data->>'parts_required')::boolean;
IF (v_op.completed_at IS NOT NULL OR EXISTS(SELECT 1 FROM karratha_pdc.bookings WHERE operation_id=v_op.id AND status IN('planned','started','stopped')))
AND (v_stage IS DISTINCT FROM v_op.stage_code OR v_hours IS DISTINCT FROM v_op.estimated_hours OR v_parts IS DISTINCT FROM v_op.parts_required) THEN
RAISE EXCEPTION 'Retained booked/completed scope cannot be overwritten';END IF;
v_before:=to_jsonb(v_op);
UPDATE karratha_pdc.operations SET stage_code=v_stage,estimated_hours=v_hours,parts_required=v_parts,source_changed=false,version=version+1,updated_at=now()
WHERE id=v_op.id RETURNING to_jsonb(operations) INTO v_record;
UPDATE karratha_pdc.jobcards SET source_changed=EXISTS(SELECT 1 FROM karratha_pdc.operations WHERE job_id=v_op.job_id AND source_changed),version=version+1,updated_at=now() WHERE id=v_op.job_id;
v_entity:='operation';
WHEN 'parts' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','received','ordered','eta','location','notes']);
SELECT * INTO v_op FROM karratha_pdc.operations WHERE id=p_id FOR UPDATE;
IF v_op.id IS NULL OR v_op.version<>p_expected_version THEN RAISE EXCEPTION 'Operation changed; refresh parts first';END IF;
IF NOT EXISTS(SELECT 1 FROM karratha_pdc.jobcards WHERE id=v_op.job_id AND selected) THEN RAISE EXCEPTION 'Selected job card required for parts updates';END IF;
IF jsonb_typeof(p_data->'received') IS DISTINCT FROM 'boolean' OR jsonb_typeof(p_data->'ordered') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Parts confirmation must be explicit';END IF;
IF NOT(p_data->>'received')::boolean AND EXISTS(SELECT 1 FROM karratha_pdc.bookings WHERE operation_id=v_op.id AND status IN('started','stopped')) THEN RAISE EXCEPTION 'Parts cannot be withdrawn from protected work';END IF;
IF (p_data->>'ordered')::boolean AND NOT(p_data->>'received')::boolean AND karratha_pdc.date_value(p_data->>'eta') IS NULL THEN RAISE EXCEPTION 'Ordered outstanding parts need an ETA';END IF;
v_before:=to_jsonb(v_op);
UPDATE karratha_pdc.operations SET parts_received=(p_data->>'received')::boolean,parts_ordered=(p_data->>'ordered')::boolean,
parts_eta=karratha_pdc.date_value(p_data->>'eta'),parts_location=karratha_pdc.text_value(p_data->>'location',120),parts_notes=karratha_pdc.text_value(p_data->>'notes',4000),
version=version+1,updated_at=now() WHERE id=v_op.id RETURNING to_jsonb(operations) INTO v_record;
IF NOT(p_data->>'received')::boolean AND v_op.parts_required THEN UPDATE karratha_pdc.jobcards SET qc_passed=false,qc_at=NULL,qc_by=NULL,version=version+1,updated_at=now() WHERE id=v_op.job_id;END IF;
v_entity:='operation';
WHEN 'vehicle_location' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','location','eta']);
SELECT * INTO v_vehicle FROM karratha_pdc.vehicles WHERE id=p_id FOR UPDATE;
IF v_vehicle.id IS NULL OR v_vehicle.version<>p_expected_version THEN RAISE EXCEPTION 'Vehicle changed; refresh its location';END IF;
IF NOT EXISTS(SELECT 1 FROM karratha_pdc.jobcards WHERE vehicle_id=v_vehicle.id AND selected) THEN RAISE EXCEPTION 'Selected Karratha job card required';END IF;
v_location:=p_data->>'location';
IF v_location IS NULL OR v_location NOT IN('incoming','yard_hold','in_transit','on_site','qc','rft','collected') THEN RAISE EXCEPTION 'Unknown workshop location';END IF;
IF v_vehicle.location='collected' AND v_location<>'collected' THEN RAISE EXCEPTION 'Collected work needs a separately reviewed return process';END IF;
IF v_location<>'on_site' AND EXISTS(SELECT 1 FROM karratha_pdc.bookings WHERE vehicle_id=v_vehicle.id AND status IN('started','stopped')) THEN RAISE EXCEPTION 'Vehicle has protected workshop work';END IF;
IF v_location IN('qc','rft','collected') AND EXISTS(SELECT 1 FROM karratha_pdc.operations o JOIN karratha_pdc.jobcards j ON j.id=o.job_id
WHERE j.vehicle_id=v_vehicle.id AND j.selected AND o.stage_code<>'REFERENCE' AND o.completed_at IS NULL) THEN RAISE EXCEPTION 'Finish all selected work before release';END IF;
IF v_location IN('rft','collected') AND EXISTS(SELECT 1 FROM karratha_pdc.jobcards WHERE vehicle_id=v_vehicle.id AND selected AND NOT qc_passed) THEN RAISE EXCEPTION 'Each selected job needs QC inspection';END IF;
IF v_location='collected' AND v_vehicle.location NOT IN('rft','collected') THEN RAISE EXCEPTION 'Record RFT before collection';END IF;
IF v_location='in_transit' AND karratha_pdc.date_value(p_data->>'eta') IS NULL THEN RAISE EXCEPTION 'In-transit work requires an ETA';END IF;
IF v_location IN('incoming','in_transit') AND EXISTS(SELECT 1 FROM karratha_pdc.bookings WHERE vehicle_id=v_vehicle.id AND status='planned') THEN RAISE EXCEPTION 'Resolve planned bookings before changing planning readiness';END IF;
v_before:=to_jsonb(v_vehicle);
UPDATE karratha_pdc.vehicles SET location=v_location,eta=CASE WHEN p_data ? 'eta' THEN karratha_pdc.date_value(p_data->>'eta') ELSE eta END,
version=version+1,updated_at=now() WHERE id=v_vehicle.id RETURNING to_jsonb(vehicles) INTO v_record;v_entity:='vehicle';
WHEN 'booking' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','operation_id','bay_id','technician_id','start_at']);
IF p_id IS NOT NULL THEN SELECT * INTO v_booking FROM karratha_pdc.bookings WHERE id=p_id FOR UPDATE;END IF;
IF v_booking.id IS NULL AND p_expected_version<>0 THEN RAISE EXCEPTION 'Booking not found or stale';END IF;
IF v_booking.id IS NOT NULL AND (v_booking.version<>p_expected_version OR v_booking.status<>'planned' OR v_booking.operation_id IS DISTINCT FROM (p_data->>'operation_id')::uuid) THEN RAISE EXCEPTION 'Only the same current planned booking can move';END IF;
v_start:=(p_data->>'start_at')::timestamptz;
v_plan:=karratha_pdc.validate_booking(v_booking.id,(p_data->>'operation_id')::uuid,(p_data->>'bay_id')::uuid,(p_data->>'technician_id')::uuid,v_start);
SELECT * INTO v_op FROM karratha_pdc.operations WHERE id=(p_data->>'operation_id')::uuid;v_before:=to_jsonb(v_booking);
IF v_booking.id IS NULL THEN
INSERT INTO karratha_pdc.bookings(id,operation_id,job_id,vehicle_id,bay_id,technician_id,stage_code,start_at,end_at,segments)
VALUES(coalesce(p_id,gen_random_uuid()),v_op.id,v_op.job_id,v_op.vehicle_id,(p_data->>'bay_id')::uuid,(p_data->>'technician_id')::uuid,v_op.stage_code,
v_start,(v_plan->>'end_at')::timestamptz,v_plan->'segments') RETURNING to_jsonb(bookings) INTO v_record;
ELSE UPDATE karratha_pdc.bookings SET bay_id=(p_data->>'bay_id')::uuid,technician_id=(p_data->>'technician_id')::uuid,start_at=v_start,
end_at=(v_plan->>'end_at')::timestamptz,segments=v_plan->'segments',version=version+1,updated_at=now() WHERE id=v_booking.id RETURNING to_jsonb(bookings) INTO v_record;END IF;
v_record:=v_record||jsonb_build_object('parts_warning',v_plan->'parts_warning');v_entity:='booking';
WHEN 'start','stop','resume','complete','cancel' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','reason']);
SELECT * INTO v_booking FROM karratha_pdc.bookings WHERE id=p_id FOR UPDATE;
IF v_booking.id IS NULL OR v_booking.version<>p_expected_version THEN RAISE EXCEPTION 'Booking changed; refresh before its action';END IF;
IF NOT EXISTS(SELECT 1 FROM karratha_pdc.jobcards WHERE id=v_booking.job_id AND selected) THEN RAISE EXCEPTION 'Selected Karratha job scope required';END IF;
SELECT * INTO v_op FROM karratha_pdc.operations WHERE id=v_booking.operation_id;
SELECT * INTO v_vehicle FROM karratha_pdc.vehicles WHERE id=v_booking.vehicle_id;v_before:=to_jsonb(v_booking);
IF p_action IN('start','resume') THEN
IF (p_action='start' AND v_booking.status<>'planned') OR (p_action='resume' AND v_booking.status<>'stopped') THEN RAISE EXCEPTION 'Booking state does not permit this action';END IF;
IF v_vehicle.location<>'on_site' OR (v_op.parts_required AND NOT v_op.parts_received) THEN RAISE EXCEPTION 'Physically on-site vehicle and confirmed required parts are needed to Start';END IF;
v_start:=clock_timestamp();v_plan:=karratha_pdc.validate_booking(v_booking.id,v_op.id,v_booking.bay_id,v_booking.technician_id,v_start,false);
UPDATE karratha_pdc.bookings SET status='started',start_at=v_start,end_at=(v_plan->>'end_at')::timestamptz,segments=v_plan->'segments',
started_at=coalesce(started_at,v_start),stoppage_reason='',version=version+1,updated_at=now() WHERE id=v_booking.id RETURNING to_jsonb(bookings) INTO v_record;
ELSIF p_action='stop' THEN
IF v_booking.status<>'started' THEN RAISE EXCEPTION 'Only running work can stop';END IF;
UPDATE karratha_pdc.bookings SET status='stopped',stoppage_reason=karratha_pdc.text_value(p_data->>'reason',500,true),version=version+1,updated_at=now()
WHERE id=v_booking.id RETURNING to_jsonb(bookings) INTO v_record;
ELSIF p_action='complete' THEN
IF v_booking.status<>'started' THEN RAISE EXCEPTION 'Only started work can be completed';END IF;
IF v_op.parts_required AND NOT v_op.parts_received THEN RAISE EXCEPTION 'Required parts are not confirmed';END IF;
UPDATE karratha_pdc.operations SET completed_at=clock_timestamp(),completed_by=auth.uid(),version=version+1,updated_at=now() WHERE id=v_op.id;
UPDATE karratha_pdc.bookings SET status='completed',completed_at=clock_timestamp(),version=version+1,updated_at=now()
WHERE id=v_booking.id RETURNING to_jsonb(bookings) INTO v_record;
ELSE
IF v_booking.status<>'planned' THEN RAISE EXCEPTION 'Only planned work can cancel';END IF;
UPDATE karratha_pdc.bookings SET status='cancelled',version=version+1,updated_at=now() WHERE id=v_booking.id RETURNING to_jsonb(bookings) INTO v_record;END IF;
v_entity:='booking';
WHEN 'external_complete' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','verified','notes']);
SELECT * INTO v_op FROM karratha_pdc.operations WHERE id=p_id FOR UPDATE;
IF v_op.id IS NULL OR v_op.version<>p_expected_version THEN RAISE EXCEPTION 'Operation changed; refresh first';END IF;
PERFORM karratha_pdc.ready_job(v_op.job_id);
IF v_op.stage_code NOT IN('PARTS','SUBLET') OR p_data->'verified' IS DISTINCT FROM 'true'::jsonb OR (v_op.parts_required AND NOT v_op.parts_received) THEN RAISE EXCEPTION 'Reviewed external work needs physical verification';END IF;
IF v_op.completed_at IS NOT NULL THEN RAISE EXCEPTION 'External operation is already complete';END IF;v_before:=to_jsonb(v_op);
UPDATE karratha_pdc.operations SET completed_at=now(),completed_by=auth.uid(),parts_notes=karratha_pdc.text_value(p_data->>'notes',4000),version=version+1,updated_at=now()
WHERE id=v_op.id RETURNING to_jsonb(operations) INTO v_record;v_entity:='operation';
WHEN 'qc' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','checks','notes']);PERFORM karratha_pdc.keys(p_data->'checks',ARRAY['work_verified','parts_verified']);
SELECT * INTO v_job FROM karratha_pdc.jobcards WHERE id=p_id FOR UPDATE;
IF v_job.id IS NULL OR v_job.version<>p_expected_version THEN RAISE EXCEPTION 'Job card changed; refresh its QC scope';END IF;
PERFORM karratha_pdc.ready_job(v_job.id);
IF p_data#>'{checks,work_verified}' IS DISTINCT FROM 'true'::jsonb OR p_data#>'{checks,parts_verified}' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'Explicit physical work and parts inspection required';END IF;
IF NOT EXISTS(SELECT 1 FROM karratha_pdc.vehicles WHERE id=v_job.vehicle_id AND location IN('on_site','qc')) THEN RAISE EXCEPTION 'QC requires the physical vehicle on site';END IF;
IF EXISTS(SELECT 1 FROM karratha_pdc.operations WHERE job_id=v_job.id AND ((stage_code<>'REFERENCE' AND completed_at IS NULL) OR (parts_required AND NOT parts_received)))
OR EXISTS(SELECT 1 FROM karratha_pdc.bookings WHERE job_id=v_job.id AND status IN('planned','started','stopped')) THEN RAISE EXCEPTION 'Finish and verify all selected job work before QC';END IF;
PERFORM karratha_pdc.text_value(p_data->>'notes',4000);v_before:=to_jsonb(v_job);
UPDATE karratha_pdc.jobcards SET qc_passed=true,qc_at=now(),qc_by=auth.uid(),version=version+1,updated_at=now()
WHERE id=v_job.id RETURNING to_jsonb(jobcards) INTO v_record;v_entity:='job';
WHEN 'technician' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','name','active','stage_codes','leave_dates']);
IF p_id IS NOT NULL THEN SELECT * INTO v_tech FROM karratha_pdc.technicians WHERE id=p_id FOR UPDATE;END IF;
IF coalesce(v_tech.version,0)<>p_expected_version THEN RAISE EXCEPTION 'Technician changed; refresh first';END IF;
IF jsonb_typeof(p_data->'active') IS DISTINCT FROM 'boolean' OR jsonb_typeof(p_data->'stage_codes') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Explicit technician activity and stages required';END IF;
SELECT array_agg(DISTINCT value) INTO v_codes FROM jsonb_array_elements_text(p_data->'stage_codes');
IF cardinality(v_codes) IS NULL OR cardinality(v_codes)>6 OR EXISTS(SELECT 1 FROM unnest(v_codes) c WHERE NOT EXISTS(SELECT 1 FROM karratha_pdc.stages s WHERE s.stage_code=c AND s.is_physical)) THEN RAISE EXCEPTION 'Choose physical technician stages';END IF;
SELECT coalesce(array_agg(karratha_pdc.date_value(value)),'{}'::date[]) INTO v_dates FROM jsonb_array_elements_text(coalesce(p_data->'leave_dates','[]'));
IF cardinality(v_dates)>366 THEN RAISE EXCEPTION 'Too many leave dates';END IF;
IF v_tech.id IS NOT NULL AND EXISTS(SELECT 1 FROM karratha_pdc.bookings b WHERE b.technician_id=v_tech.id AND b.status IN('planned','started','stopped')
AND (NOT(p_data->>'active')::boolean OR NOT(b.stage_code=ANY(v_codes)) OR EXISTS(SELECT 1 FROM jsonb_array_elements(b.segments) s WHERE ((s->>'start_at')::timestamptz AT TIME ZONE 'Australia/Perth')::date=ANY(v_dates)))) THEN RAISE EXCEPTION 'Technician change conflicts with live bookings';END IF;
v_before:=to_jsonb(v_tech);
IF v_tech.id IS NULL THEN INSERT INTO karratha_pdc.technicians(id,name,active,stage_codes,leave_dates)
VALUES(coalesce(p_id,gen_random_uuid()),karratha_pdc.text_value(p_data->>'name',120,true),(p_data->>'active')::boolean,v_codes,v_dates)
RETURNING to_jsonb(technicians) INTO v_record;
ELSE UPDATE karratha_pdc.technicians SET name=karratha_pdc.text_value(p_data->>'name',120,true),active=(p_data->>'active')::boolean,stage_codes=v_codes,leave_dates=v_dates,
version=version+1,updated_at=now() WHERE id=v_tech.id RETURNING to_jsonb(technicians) INTO v_record;END IF;v_entity:='technician';
WHEN 'bay' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','active','efficiency_percent','default_technician_id']);
SELECT * INTO v_bay FROM karratha_pdc.bays WHERE id=p_id FOR UPDATE;
IF v_bay.id IS NULL OR v_bay.version<>p_expected_version THEN RAISE EXCEPTION 'Bay changed; refresh first';END IF;
IF jsonb_typeof(p_data->'active') IS DISTINCT FROM 'boolean' OR nullif(p_data->>'efficiency_percent','') IS NULL OR (p_data->>'efficiency_percent')::integer NOT BETWEEN 10 AND 200 THEN RAISE EXCEPTION 'Invalid bay capacity';END IF;
IF EXISTS(SELECT 1 FROM karratha_pdc.bookings WHERE bay_id=v_bay.id AND status IN('planned','started','stopped')) AND
(NOT(p_data->>'active')::boolean OR (p_data->>'efficiency_percent')::integer<>v_bay.efficiency_percent) THEN RAISE EXCEPTION 'Live bay capacity cannot change';END IF;
v_id:=nullif(p_data->>'default_technician_id','')::uuid;
IF v_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM karratha_pdc.technicians WHERE id=v_id AND active AND v_bay.stage_code=ANY(stage_codes)) THEN RAISE EXCEPTION 'Default technician is not suitable';END IF;
v_before:=to_jsonb(v_bay);
UPDATE karratha_pdc.bays SET active=(p_data->>'active')::boolean,efficiency_percent=(p_data->>'efficiency_percent')::integer,
default_technician_id=v_id,version=version+1 WHERE id=v_bay.id RETURNING to_jsonb(bays) INTO v_record;v_entity:='bay';
WHEN 'setting' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','key','value']);v_key:=p_data->>'key';v_value:=p_data->'value';
SELECT * INTO v_setting FROM karratha_pdc.settings WHERE key=v_key FOR UPDATE;
IF v_setting.id IS NULL OR v_setting.version<>p_expected_version OR (p_id IS NOT NULL AND p_id<>v_setting.id) THEN RAISE EXCEPTION 'Setting changed or is unknown';END IF;
IF v_key='calendar' THEN
PERFORM karratha_pdc.keys(v_value,ARRAY['timezone','working_week','day_start','day_end','scheduling_increment_minutes','break_windows','closures','future_only']);
IF NOT(v_value ?& ARRAY['timezone','working_week','day_start','day_end','scheduling_increment_minutes','break_windows','closures','future_only'])
OR v_value->>'timezone'<>'Australia/Perth' OR jsonb_typeof(v_value->'working_week') IS DISTINCT FROM 'array' OR jsonb_array_length(v_value->'working_week') NOT BETWEEN 1 AND 7
OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(v_value->'working_week') d WHERE d !~ '^[1-7]$')
OR v_value->>'day_start' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' OR v_value->>'day_end' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
OR (v_value->>'day_end')::time<=(v_value->>'day_start')::time OR (v_value->>'scheduling_increment_minutes')::integer NOT IN(5,10,15,30,60)
OR v_value->'future_only' IS DISTINCT FROM 'true'::jsonb OR jsonb_typeof(v_value->'break_windows') IS DISTINCT FROM 'array' OR jsonb_typeof(v_value->'closures') IS DISTINCT FROM 'array'
OR jsonb_array_length(v_value->'break_windows')>10 OR jsonb_array_length(v_value->'closures')>366 THEN RAISE EXCEPTION 'Invalid independent calendar';END IF;
v_last:=NULL;
FOR v_item IN SELECT value FROM jsonb_array_elements(v_value->'break_windows') ORDER BY value->>'start' LOOP
PERFORM karratha_pdc.keys(v_item,ARRAY['start','end']);
IF NOT(v_item ?& ARRAY['start','end']) OR v_item->>'start' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' OR v_item->>'end' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
OR (v_item->>'start')::time<(v_value->>'day_start')::time OR (v_item->>'end')::time>(v_value->>'day_end')::time
OR (v_item->>'end')::time<=(v_item->>'start')::time OR (v_last IS NOT NULL AND (v_item->>'start')::time<v_last) THEN RAISE EXCEPTION 'Invalid overlapping break';END IF;
v_last:=(v_item->>'end')::time;END LOOP;
PERFORM karratha_pdc.date_value(value) FROM jsonb_array_elements_text(v_value->'closures');
IF EXISTS(SELECT 1 FROM karratha_pdc.bookings WHERE status IN('planned','started','stopped')) THEN RAISE EXCEPTION 'Resolve live bookings before changing the calendar';END IF;
ELSIF v_key='import_contract' THEN
PERFORM karratha_pdc.keys(v_value,ARRAY['mapping_verified','store_code','source_system','allowed_dealer_codes','column_mapping']);
IF NOT(v_value ?& ARRAY['mapping_verified','store_code','source_system','allowed_dealer_codes','column_mapping']) OR v_value->>'store_code'<>'135' OR v_value->>'source_system'<>'nuvu'
OR jsonb_typeof(v_value->'mapping_verified') IS DISTINCT FROM 'boolean' OR jsonb_typeof(v_value->'allowed_dealer_codes') IS DISTINCT FROM 'array'
OR jsonb_array_length(v_value->'allowed_dealer_codes') NOT BETWEEN 1 AND 4 OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(v_value->'allowed_dealer_codes') c WHERE c NOT IN('14450','37047','001234','002345'))
OR jsonb_typeof(v_value->'column_mapping') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Confirm store135 source and explicit permitted Navision dealer scope';END IF;
PERFORM karratha_pdc.keys(v_value->'column_mapping',ARRAY['stock_number','repair_order_number','original_line_number','operation_description','source_estimated_hours','store_code','stage_code','parts_required','dealer_code','vin','toyota_order_number','sheet_name','header_row','hours_unit']);
FOR v_key,v_item IN SELECT key,value FROM jsonb_each(v_value->'column_mapping') LOOP
IF v_key='header_row' THEN IF jsonb_typeof(v_item)<>'number' OR v_item::text !~ '^[0-9]{1,4}$' OR v_item::text::integer NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'Invalid header row';END IF;
ELSIF v_key='hours_unit' THEN IF v_item#>>'{}'<>'decimal' THEN RAISE EXCEPTION 'Confirm decimal source hours';END IF;
ELSE IF jsonb_typeof(v_item)<>'string' OR length(v_item#>>'{}') NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Explicit bounded source header required';END IF;END IF;END LOOP;v_key:='import_contract';
IF (v_value->>'mapping_verified')::boolean AND NOT((v_value->'column_mapping') ?& ARRAY['stock_number','repair_order_number','original_line_number','operation_description','source_estimated_hours','store_code']) THEN RAISE EXCEPTION 'Map original stock, job card, line, description, hours and store headers';END IF;
IF EXISTS(SELECT 1 FROM karratha_pdc.jobcards WHERE selected) AND EXISTS(SELECT 1 FROM jsonb_array_elements_text(v_setting.value->'allowed_dealer_codes') c WHERE NOT(v_value->'allowed_dealer_codes' ? c)) THEN RAISE EXCEPTION 'Selected work prevents removing its master dealer scope';END IF;
ELSE RAISE EXCEPTION 'Unknown Karratha setting';END IF;
v_before:=to_jsonb(v_setting);
UPDATE karratha_pdc.settings SET value=v_value,version=version+1,updated_at=now(),updated_by=auth.uid() WHERE id=v_setting.id
RETURNING jsonb_build_object('id',id,'key',key,'value',value,'version',version) INTO v_record;v_entity:='setting';
WHEN 'membership' THEN
PERFORM karratha_pdc.keys(p_data,ARRAY['request_id','email','role','active']);
v_email:=lower(karratha_pdc.text_value(p_data->>'email',254));v_role:=p_data->>'role';
IF v_role IS NULL OR v_role NOT IN('administrator','operator','viewer') OR jsonb_typeof(p_data->'active') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Explicit supported membership role/activity required';END IF;
IF p_id IS NOT NULL THEN SELECT * INTO v_member FROM karratha_pdc.memberships WHERE id=p_id FOR UPDATE;END IF;
IF coalesce(v_member.version,0)<>p_expected_version THEN RAISE EXCEPTION 'Membership changed; refresh first';END IF;
IF v_member.id IS NULL THEN
IF v_email='' THEN RAISE EXCEPTION 'Provide the existing work account email';END IF;
SELECT u.id,lower(u.email) email,coalesce(nullif(u.raw_user_meta_data->>'full_name',''),nullif(u.raw_user_meta_data->>'name',''),lower(u.email)) display_name INTO STRICT v_user
FROM auth.users u WHERE lower(u.email)=v_email AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false) AND (u.banned_until IS NULL OR u.banned_until<=now());
IF p_id IS NOT NULL AND p_id<>v_user.id THEN RAISE EXCEPTION 'Membership identity conflicts with work email';END IF;
IF EXISTS(SELECT 1 FROM karratha_pdc.memberships WHERE id=v_user.id OR email=v_user.email) THEN RAISE EXCEPTION 'Account already has Karratha membership';END IF;
v_before:=NULL;
INSERT INTO karratha_pdc.memberships(id,email,display_name,role,active)
VALUES(v_user.id,v_user.email,left(v_user.display_name,200),v_role,(p_data->>'active')::boolean) RETURNING to_jsonb(memberships) INTO v_record;
ELSE
IF v_email<>'' AND v_email<>v_member.email THEN RAISE EXCEPTION 'Membership email cannot be reassigned';END IF;
IF v_member.id=auth.uid() AND (v_role<>v_member.role OR NOT(p_data->>'active')::boolean) THEN RAISE EXCEPTION 'Another administrator must change your own access';END IF;
IF v_member.role='administrator' AND v_member.active AND (v_role<>'administrator' OR NOT(p_data->>'active')::boolean)
AND (SELECT count(*) FROM karratha_pdc.memberships WHERE active AND role='administrator')<=1 THEN RAISE EXCEPTION 'Keep an active Karratha administrator';END IF;
v_before:=to_jsonb(v_member);
UPDATE karratha_pdc.memberships SET role=v_role,active=(p_data->>'active')::boolean,version=version+1,updated_at=now()
WHERE id=v_member.id RETURNING to_jsonb(memberships) INTO v_record;END IF;v_entity:='membership';
ELSE RAISE EXCEPTION 'Unknown Karratha action';
END CASE;
v_id:=(v_record->>'id')::uuid;
v_revision:=karratha_pdc.touch(v_entity,v_id,p_action,jsonb_build_object('before',v_before,'after',v_record,'notes',p_data->>'notes','reason',p_data->>'reason'));
v_result:=jsonb_build_object('record',v_record,'revision',v_revision,'centre','KARRATHA','replay',false);
INSERT INTO karratha_pdc.request_receipts(actor_id,request_id,request_hash,result) VALUES(auth.uid(),v_nonce,v_hash,v_result);
RETURN v_result;
END $f$;



CREATE FUNCTION karratha_pdc.snapshot(p_date_from date,p_date_to date) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,karratha_pdc AS $f$
DECLARE v_ctx jsonb:=karratha_pdc.context();v_edit boolean:=(v_ctx->>'can_edit')::boolean;v_result jsonb;
BEGIN
 IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_to<p_date_from OR p_date_to-p_date_from>92 THEN RAISE EXCEPTION 'Select at most 93 calendar days'; END IF;
 SELECT jsonb_build_object('context',v_ctx,'revision',v_ctx->'revision',
 'vehicles',coalesce((SELECT jsonb_agg(to_jsonb(v)||coalesce(m.data,v.source_snapshot)||jsonb_build_object('id',v.id,'version',v.version,'location',v.location,'eta',v.eta,
 'source_current',coalesce((m.data->>'source_current')::boolean,false) AND coalesce((m.data->>'latest_export')::boolean,false),'source_conflict',m.data IS NULL,'source_snapshot',v.source_snapshot,'source_identity',v.source_identity) ORDER BY v.stock_number)
 FROM karratha_pdc.vehicles v LEFT JOIN LATERAL(SELECT karratha_pdc.master(v.navision_record_id,v.source_identity) data) m ON true
 WHERE EXISTS(SELECT 1 FROM karratha_pdc.jobcards j WHERE j.vehicle_id=v.id AND (j.selected OR v_edit))),'[]'::jsonb),
 'jobs',coalesce((SELECT jsonb_agg(to_jsonb(j) ORDER BY j.job_card_number) FROM karratha_pdc.jobcards j WHERE j.selected OR v_edit),'[]'::jsonb),
 'operations',coalesce((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.job_id,o.original_line_number,o.id) FROM karratha_pdc.operations o
 JOIN karratha_pdc.jobcards j ON j.id=o.job_id WHERE j.selected OR v_edit),'[]'::jsonb),
 'bookings',coalesce((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.start_at,b.id) FROM karratha_pdc.bookings b JOIN karratha_pdc.jobcards j ON j.id=b.job_id
 WHERE j.selected AND (b.start_at AT TIME ZONE 'Australia/Perth')::date<=p_date_to AND (b.end_at AT TIME ZONE 'Australia/Perth')::date>=p_date_from),'[]'::jsonb),
 'bays',(SELECT jsonb_agg(to_jsonb(b) ORDER BY b.stage_code,b.bay_number) FROM karratha_pdc.bays b),
 'technicians',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.name) FROM karratha_pdc.technicians t),'[]'::jsonb),
 'settings',(SELECT jsonb_agg(jsonb_build_object('id',s.id,'key',s.key,'value',s.value,'version',s.version) ORDER BY s.key) FROM karratha_pdc.settings s),
 'history',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.created_at DESC,h.id) FROM(
 SELECT h.* FROM karratha_pdc.history h WHERE v_edit OR EXISTS(SELECT 1 FROM karratha_pdc.jobcards j
 WHERE j.selected AND (h.entity_id=j.id OR h.entity_id=j.vehicle_id OR EXISTS(SELECT 1 FROM karratha_pdc.operations o WHERE o.job_id=j.id AND o.id=h.entity_id)
 OR EXISTS(SELECT 1 FROM karratha_pdc.bookings b WHERE b.job_id=j.id AND b.id=h.entity_id))) ORDER BY h.created_at DESC,h.id LIMIT 500) h),'[]'::jsonb),
 'memberships',CASE WHEN (v_ctx->>'can_admin')::boolean THEN coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.email) FROM karratha_pdc.memberships m),'[]'::jsonb) ELSE '[]'::jsonb END
 ) INTO v_result;
 RETURN v_result;
END $f$;
CREATE FUNCTION karratha_pdc.preview(p_file_name text,p_file_sha256 text,p_rows jsonb) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,karratha_pdc AS $f$
DECLARE v_ctx jsonb:=karratha_pdc.context();v_name text;v_hash text;v_request text;v_resolution text;v_pre karratha_pdc.import_previews;
 v_row jsonb;v_n integer:=0;v_group record;v_cards jsonb:='[]';v_good jsonb:='[]';v_warnings jsonb:='[]';v_ro text;v_store text;v_card jsonb;v_line text;v_result jsonb;v_contract karratha_pdc.settings;v_contract_hash text;
BEGIN
 IF NOT (v_ctx->>'can_import')::boolean THEN RAISE EXCEPTION 'Karratha import permission required' USING errcode='42501'; END IF;
 v_name:=karratha_pdc.text_value(p_file_name,240,true);v_hash:=lower(btrim(p_file_sha256));
 IF v_hash !~ '^[a-f0-9]{64}$' OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 10000 OR octet_length(p_rows::text)>8000000 THEN RAISE EXCEPTION 'Provide a bounded NuVu file and its SHA256'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('karratha_pdc:mutation',0));
 v_ctx:=karratha_pdc.context();
 SELECT * INTO v_contract FROM karratha_pdc.settings WHERE key='import_contract';
 v_contract_hash:=encode(extensions.digest(convert_to(v_contract.value::text,'UTF8'),'sha256'),'hex');
 v_request:=encode(extensions.digest(convert_to(p_rows::text,'UTF8'),'sha256'),'hex');
 IF EXISTS(SELECT 1 FROM karratha_pdc.import_previews WHERE file_sha256=v_hash AND contract_hash=v_contract_hash AND request_hash<>v_request) THEN RAISE EXCEPTION 'File digest was reused with different source rows under the same mapping'; END IF;
 FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
 v_n:=v_n+1;
 PERFORM karratha_pdc.keys(v_row,ARRAY['stock_number','repair_order_number','original_line_number','operation_description','source_estimated_hours','store_code','stage_code','parts_required','raw_row','dealer_code','vin','toyota_order_number']);
 IF jsonb_typeof(v_row->'raw_row') IS DISTINCT FROM 'object' OR octet_length((v_row->'raw_row')::text)>65536 THEN RAISE EXCEPTION 'Each NuVu row needs bounded original evidence'; END IF;
 v_ro:=upper(karratha_pdc.text_value(v_row->>'repair_order_number',80));v_store:=karratha_pdc.text_value(v_row->>'store_code',40);
 PERFORM karratha_pdc.text_value(v_row->>'stock_number',80);
 PERFORM karratha_pdc.text_value(v_row->>'operation_description',16000);
 PERFORM karratha_pdc.text_value(v_row->>'dealer_code',20);
 PERFORM karratha_pdc.text_value(v_row->>'vin',40);
 PERFORM karratha_pdc.text_value(v_row->>'toyota_order_number',80);
 v_line:=nullif(v_row->>'original_line_number','');
 IF v_line IS NOT NULL AND (v_line !~ '^[0-9]{1,7}$' OR v_line::integer<1) THEN RAISE EXCEPTION 'Operation line must be a positive original integer'; END IF;
 IF nullif(v_row->>'source_estimated_hours','') IS NOT NULL AND (jsonb_typeof(v_row->'source_estimated_hours')<>'number' OR (v_row->>'source_estimated_hours')::numeric NOT BETWEEN 0 AND 999.99) THEN RAISE EXCEPTION 'Invalid source hours'; END IF;
 IF v_row ? 'parts_required' AND jsonb_typeof(v_row->'parts_required') NOT IN('boolean','null') THEN RAISE EXCEPTION 'Parts requirement must be explicit or unknown'; END IF;
 IF v_store<>'135' OR v_ro='' THEN v_warnings:=v_warnings||jsonb_build_array('Row '||v_n||': original store135 and job-card identity required');
 ELSE v_good:=v_good||jsonb_build_array(v_row||jsonb_build_object('repair_order_number',v_ro,'store_code','135')); END IF;
 END LOOP;
 FOR v_group IN SELECT upper(btrim(value->>'repair_order_number')) ro,jsonb_agg(value ORDER BY ord) rows
 FROM jsonb_array_elements(v_good) WITH ORDINALITY x(value,ord) GROUP BY upper(btrim(value->>'repair_order_number')) ORDER BY ro LOOP
 v_card:=karratha_pdc.resolve_card(v_group.rows);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_group.rows) r GROUP BY r->>'original_line_number',lower(btrim(r->>'operation_description'))
 HAVING count(DISTINCT jsonb_build_array(r->'source_estimated_hours',r->'stage_code',r->'parts_required'))>1) THEN
 v_card:=v_card||jsonb_build_object('identity_status','conflict','navision_record_id',NULL,'reason','Conflicting duplicate operation scope');
 END IF;
 v_cards:=v_cards||jsonb_build_array(v_card);
 IF v_card->>'identity_status'<>'matched' THEN v_warnings:=v_warnings||jsonb_build_array(v_group.ro||': '||coalesce(v_card->>'reason','Identity review required')); END IF;
 END LOOP;
 v_resolution:=encode(extensions.digest(convert_to(v_cards::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO v_pre FROM karratha_pdc.import_previews WHERE file_sha256=v_hash AND contract_hash=v_contract_hash AND request_hash=v_request AND resolution_hash=v_resolution;
 IF v_pre.id IS NOT NULL THEN RETURN v_pre.result||jsonb_build_object('replay',true); END IF;
 v_pre.id:=gen_random_uuid();
 v_result:=jsonb_build_object('preview_id',v_pre.id,'version',1,'contract_version',v_contract.version,'source_hash',v_hash,'file_name',v_name,'rows',p_rows,'jobcards',v_cards,'warnings',v_warnings,'replay',false);
 INSERT INTO karratha_pdc.import_previews(id,file_name,file_sha256,request_hash,resolution_hash,contract_version,contract_hash,payload_rows,result,created_by)
 VALUES(v_pre.id,v_name,v_hash,v_request,v_resolution,v_contract.version,v_contract_hash,p_rows,v_result,auth.uid());
 RETURN v_result;
END $f$;
CREATE FUNCTION karratha_pdc.apply_import(p_preview_id uuid,p_expected_version integer) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,karratha_pdc AS $f$
DECLARE v_ctx jsonb:=karratha_pdc.context();v_pre karratha_pdc.import_previews;v_receipt karratha_pdc.import_receipts;
 v_card jsonb;v_current jsonb;v_row jsonb;v_job karratha_pdc.jobcards;v_op karratha_pdc.operations;
 v_vehicle karratha_pdc.vehicles;v_stock text;v_key text;v_semantic text;v_stage text;v_hours numeric;v_parts boolean;
 v_changed boolean;v_count integer:=0;v_same integer:=0;v_jobs jsonb:='[]';v_result jsonb;v_revision bigint;
BEGIN
 IF NOT (v_ctx->>'can_import')::boolean THEN RAISE EXCEPTION 'Karratha import permission required' USING errcode='42501'; END IF;
 IF p_expected_version IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'Stale NuVu preview version'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('karratha_pdc:mutation',0));v_ctx:=karratha_pdc.context();
 SELECT * INTO v_pre FROM karratha_pdc.import_previews WHERE id=p_preview_id;
 IF v_pre.id IS NULL THEN RAISE EXCEPTION 'NuVu preview not found'; END IF;
 IF NOT EXISTS(SELECT 1 FROM karratha_pdc.settings s WHERE s.key='import_contract' AND s.version=v_pre.contract_version
 AND encode(extensions.digest(convert_to(s.value::text,'UTF8'),'sha256'),'hex')=v_pre.contract_hash) THEN RAISE EXCEPTION 'Source header mapping or dealer scope changed; refresh the preview';END IF;
 SELECT * INTO v_receipt FROM karratha_pdc.import_receipts WHERE preview_id=p_preview_id;
 IF v_receipt.id IS NOT NULL THEN RETURN v_receipt.result||jsonb_build_object('replay',true); END IF;
 FOR v_card IN SELECT value FROM jsonb_array_elements(v_pre.result->'jobcards') LOOP
 v_current:=karratha_pdc.resolve_card(v_card->'operations');
 IF v_current IS DISTINCT FROM v_card THEN
 -- Duplicate source conflict remains an explicit unresolved card.
 IF v_card->>'reason' IS DISTINCT FROM 'Conflicting duplicate operation scope' THEN RAISE EXCEPTION 'Navision identity changed since preview; refresh the file preview'; END IF;
 END IF;
 SELECT * INTO v_job FROM karratha_pdc.jobcards WHERE store_code='135' AND job_card_number=v_card->>'job_card_number' FOR UPDATE;
 v_stock:=v_card->>'stock_number';v_vehicle:=NULL;
 IF v_card->>'identity_status'='matched' THEN
 SELECT * INTO v_vehicle FROM karratha_pdc.vehicles WHERE navision_record_id=(v_card->>'navision_record_id')::uuid;
 IF v_vehicle.id IS NULL THEN
 INSERT INTO karratha_pdc.vehicles(navision_record_id,source_identity,source_snapshot,stock_number)
 VALUES((v_card->>'navision_record_id')::uuid,v_card->'source_identity',v_card->'source_snapshot',v_stock) RETURNING * INTO v_vehicle;
 ELSIF v_vehicle.source_identity IS DISTINCT FROM v_card->'source_identity' THEN RAISE EXCEPTION 'Shared master identity changed; reviewed rebind required'; END IF;
 END IF;
 IF v_job.id IS NULL THEN
 INSERT INTO karratha_pdc.jobcards(vehicle_id,store_code,job_card_number,stock_number,identity_status,source_binding,source_batch_id)
 VALUES(v_vehicle.id,'135',v_card->>'job_card_number',v_stock,v_card->>'identity_status',v_card,p_preview_id) RETURNING * INTO v_job;v_count:=v_count+1;
 ELSE
 IF v_job.selected AND (v_job.vehicle_id IS DISTINCT FROM v_vehicle.id OR v_job.stock_number IS DISTINCT FROM v_stock) THEN
 RAISE EXCEPTION 'Selected job-card identity changed; do not rebind active work'; END IF;
 IF (v_job.vehicle_id IS DISTINCT FROM v_vehicle.id OR v_job.stock_number IS DISTINCT FROM v_stock
 OR v_job.source_binding->'source_identity' IS DISTINCT FROM v_card->'source_identity')
 AND (EXISTS(SELECT 1 FROM karratha_pdc.bookings WHERE job_id=v_job.id AND status<>'cancelled')
 OR EXISTS(SELECT 1 FROM karratha_pdc.operations WHERE job_id=v_job.id AND completed_at IS NOT NULL)) THEN
 RAISE EXCEPTION 'Job-card vehicle or source identity conflicts with retained work'; END IF;
 UPDATE karratha_pdc.jobcards SET vehicle_id=coalesce(v_vehicle.id,vehicle_id),stock_number=v_stock,identity_status=v_card->>'identity_status',
 source_binding=v_card,source_batch_id=p_preview_id,version=version+1,updated_at=now() WHERE id=v_job.id RETURNING * INTO v_job;v_same:=v_same+1;
 END IF;
 FOR v_row IN SELECT value FROM jsonb_array_elements(v_card->'operations') LOOP
 v_key:=encode(extensions.digest(convert_to(jsonb_build_array(v_row->>'original_line_number',lower(regexp_replace(btrim(coalesce(v_row->>'operation_description','')),'\s+',' ','g')))::text,'UTF8'),'sha256'),'hex');
 v_semantic:=encode(extensions.digest(convert_to(jsonb_build_array(v_key,v_row->'source_estimated_hours',v_row->'stage_code',v_row->'parts_required')::text,'UTF8'),'sha256'),'hex');
 v_stage:=upper(btrim(coalesce(v_row->>'stage_code','REVIEW')));
 IF NOT EXISTS(SELECT 1 FROM karratha_pdc.stages WHERE stage_code=v_stage) THEN v_stage:='REVIEW'; END IF;
 IF nullif(v_row->>'original_line_number','') IS NULL OR btrim(coalesce(v_row->>'operation_description',''))='' THEN v_stage:='REVIEW'; END IF;
 v_hours:=nullif(v_row->>'source_estimated_hours','')::numeric;v_parts:=CASE WHEN jsonb_typeof(v_row->'parts_required')='boolean' THEN (v_row->>'parts_required')::boolean END;
 SELECT * INTO v_op FROM karratha_pdc.operations WHERE job_id=v_job.id AND source_key=v_key FOR UPDATE;
 IF v_op.id IS NULL THEN
 INSERT INTO karratha_pdc.operations(job_id,vehicle_id,source_key,original_line_number,description,source_estimated_hours,source_row,observed_source_row,observed_hash,estimated_hours,stage_code,parts_required,source_changed)
 VALUES(v_job.id,v_job.vehicle_id,v_key,nullif(v_row->>'original_line_number','')::integer,coalesce(v_row->>'operation_description',''),v_hours,v_row,v_row,v_semantic,v_hours,v_stage,v_parts,v_job.selected);
 ELSE
 v_changed:=v_op.observed_hash<>v_semantic;
 UPDATE karratha_pdc.operations SET vehicle_id=v_job.vehicle_id,observed_source_row=v_row,observed_hash=v_semantic,
 source_changed=source_changed OR v_changed,version=version+CASE WHEN v_changed THEN 1 ELSE 0 END,updated_at=CASE WHEN v_changed THEN now() ELSE updated_at END WHERE id=v_op.id;
 END IF;
 END LOOP;
 UPDATE karratha_pdc.jobcards SET source_changed=EXISTS(SELECT 1 FROM karratha_pdc.operations WHERE job_id=v_job.id AND source_changed),
 qc_passed=CASE WHEN EXISTS(SELECT 1 FROM karratha_pdc.operations WHERE job_id=v_job.id AND source_changed) THEN false ELSE qc_passed END WHERE id=v_job.id;
 v_revision:=karratha_pdc.touch('job',v_job.id,'import_review',jsonb_build_object('preview_id',p_preview_id,'job_card_number',v_job.job_card_number));
 v_jobs:=v_jobs||jsonb_build_array(v_job.id);
 END LOOP;
 v_result:=jsonb_build_object('record',jsonb_build_object('id',p_preview_id,'version',1),'revision',coalesce(v_revision,(v_ctx->>'revision')::bigint),'imported',v_count,'unchanged',v_same,'jobs',v_jobs,'replay',false);
 INSERT INTO karratha_pdc.import_receipts(preview_id,result,created_by) VALUES(p_preview_id,v_result,auth.uid());
 RETURN v_result;
END $f$;
CREATE FUNCTION karratha_pdc.ready_job(p_job_id uuid,p_selected boolean DEFAULT true) RETURNS void
 LANGUAGE plpgsql STABLE SET search_path=pg_catalog,karratha_pdc AS $f$
DECLARE v_job karratha_pdc.jobcards;v_vehicle karratha_pdc.vehicles;v_master jsonb;v_scope jsonb;v_count integer;
BEGIN
 SELECT * INTO v_job FROM karratha_pdc.jobcards WHERE id=p_job_id;
 IF v_job.id IS NULL OR (p_selected AND NOT v_job.selected) THEN RAISE EXCEPTION 'Selected Karratha job card required'; END IF;
 SELECT value INTO v_scope FROM karratha_pdc.settings WHERE key='import_contract';
 IF NOT coalesce((v_scope->>'mapping_verified')::boolean,false) THEN RAISE EXCEPTION 'Administrator must verify the NuVu store135 header mapping and dealer scope'; END IF;
 SELECT * INTO v_vehicle FROM karratha_pdc.vehicles WHERE id=v_job.vehicle_id;
 v_master:=karratha_pdc.master(v_vehicle.navision_record_id,v_vehicle.source_identity);
 IF v_job.identity_status<>'matched' OR v_master IS NULL OR NOT coalesce((v_master->>'source_current')::boolean,false) OR NOT coalesce((v_master->>'latest_export')::boolean,false) THEN RAISE EXCEPTION 'Current uniquely bound Navision identity in the latest dealer export required'; END IF;
 SELECT count(*) INTO v_count FROM public.navision_backend_records n WHERE n.source_system='microsoft_navision' AND n.is_current AND n.record_status='current'
 AND btrim(coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',''))=v_master->>'stock_number';
 IF v_count<>1 THEN RAISE EXCEPTION 'Current source stock is ambiguous'; END IF;
 IF NOT EXISTS(SELECT 1 FROM karratha_pdc.operations WHERE job_id=v_job.id) OR EXISTS(SELECT 1 FROM karratha_pdc.operations o
 JOIN karratha_pdc.stages s ON s.stage_code=o.stage_code WHERE o.job_id=v_job.id AND
 (o.stage_code='REVIEW' OR o.parts_required IS NULL OR o.source_changed OR (s.is_physical AND (o.estimated_hours IS NULL OR o.estimated_hours<=0))
 OR o.original_line_number IS NULL OR btrim(o.description)='')) THEN RAISE EXCEPTION 'Review every operation identity, stage, usable hours and parts requirement first'; END IF;
END $f$;
CREATE FUNCTION karratha_pdc.segments(p_start timestamptz,p_minutes integer,p_strict boolean DEFAULT true) RETURNS jsonb
 LANGUAGE plpgsql STABLE SET search_path=pg_catalog,karratha_pdc AS $f$
DECLARE v_calendar jsonb;v_local timestamp:=p_start AT TIME ZONE 'Australia/Perth';v_date date:=v_local::date;v_cursor timestamp:=v_local;
 v_open timestamp;v_close timestamp;v_until timestamp;v_break jsonb;v_next_break timestamp;v_break_end timestamp;
 v_left integer:=p_minutes;v_available integer;v_steps integer:=0;v_segments jsonb:='[]';v_increment integer;
BEGIN
 SELECT value INTO v_calendar FROM karratha_pdc.settings WHERE key='calendar';v_increment:=(v_calendar->>'scheduling_increment_minutes')::integer;
 IF p_start IS NULL OR p_minutes NOT BETWEEN 1 AND 60000 OR v_date<current_date-366 OR v_date>current_date+366 THEN RAISE EXCEPTION 'Invalid bounded booking period'; END IF;
 IF p_strict AND (coalesce((v_calendar->>'future_only')::boolean,true) AND p_start<=clock_timestamp()) THEN RAISE EXCEPTION 'Book a future time'; END IF;
 IF p_strict AND (extract(minute FROM v_local)::integer%v_increment<>0 OR extract(second FROM v_local)<>0) THEN RAISE EXCEPTION 'Start must use the calendar increment'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(v_calendar->'working_week') d WHERE d::integer=extract(isodow FROM v_date)::integer)
 OR v_calendar->'closures' ? v_date::text OR v_local::time<(v_calendar->>'day_start')::time OR v_local::time>=(v_calendar->>'day_end')::time
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_calendar->'break_windows') b WHERE v_local::time>=(b->>'start')::time AND v_local::time<(b->>'end')::time)
 THEN RAISE EXCEPTION 'Start is outside the working calendar'; END IF;
 LOOP
 v_steps:=v_steps+1;IF v_steps>1000 THEN RAISE EXCEPTION 'Booking continuation exceeds supported calendar'; END IF;
 v_open:=v_date+(v_calendar->>'day_start')::time;v_close:=v_date+(v_calendar->>'day_end')::time;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(v_calendar->'working_week') d WHERE d::integer=extract(isodow FROM v_date)::integer) AND NOT(v_calendar->'closures' ? v_date::text) THEN
 v_cursor:=greatest(v_cursor,v_open);v_next_break:=NULL;v_break_end:=NULL;
 FOR v_break IN SELECT value FROM jsonb_array_elements(v_calendar->'break_windows') ORDER BY value->>'start' LOOP
 IF v_cursor>=v_date+(v_break->>'start')::time AND v_cursor<v_date+(v_break->>'end')::time THEN v_cursor:=v_date+(v_break->>'end')::time; END IF;
 IF v_date+(v_break->>'start')::time>v_cursor THEN v_next_break:=v_date+(v_break->>'start')::time;v_break_end:=v_date+(v_break->>'end')::time;EXIT;END IF;
 END LOOP;
 v_until:=least(v_close,coalesce(v_next_break,v_close));
 v_available:=greatest(0,floor(extract(epoch FROM (v_until-v_cursor))/60)::integer);
 IF v_available>0 THEN
 v_until:=v_cursor+make_interval(mins=>least(v_left,v_available));
 v_segments:=v_segments||jsonb_build_array(jsonb_build_object('start_at',v_cursor AT TIME ZONE 'Australia/Perth','end_at',v_until AT TIME ZONE 'Australia/Perth'));
 v_left:=v_left-least(v_left,v_available);v_cursor:=v_until;
 IF v_left=0 THEN RETURN v_segments; END IF;
 END IF;
 IF v_next_break IS NOT NULL AND v_cursor>=v_next_break AND v_cursor<v_close THEN v_cursor:=v_break_end;CONTINUE;END IF;
 END IF;
 v_date:=v_date+1;v_cursor:=v_date+(v_calendar->>'day_start')::time;
 IF v_date>current_date+732 THEN RAISE EXCEPTION 'Booking continuation exceeds supported year'; END IF;
 END LOOP;
END $f$;
CREATE FUNCTION karratha_pdc.validate_booking(p_id uuid,p_operation uuid,p_bay uuid,p_technician uuid,p_start timestamptz,p_strict boolean DEFAULT true) RETURNS jsonb
 LANGUAGE plpgsql STABLE SET search_path=pg_catalog,karratha_pdc AS $f$
DECLARE v_op karratha_pdc.operations;v_job karratha_pdc.jobcards;v_vehicle karratha_pdc.vehicles;v_bay karratha_pdc.bays;v_tech karratha_pdc.technicians;
 v_segments jsonb;v_minutes integer;v_end timestamptz;
BEGIN
 SELECT * INTO v_op FROM karratha_pdc.operations WHERE id=p_operation;PERFORM karratha_pdc.ready_job(v_op.job_id);
 SELECT * INTO v_job FROM karratha_pdc.jobcards WHERE id=v_op.job_id;SELECT * INTO v_vehicle FROM karratha_pdc.vehicles WHERE id=v_job.vehicle_id;
 IF v_op.completed_at IS NOT NULL THEN RAISE EXCEPTION 'Completed work cannot be rebooked'; END IF;
 SELECT * INTO v_bay FROM karratha_pdc.bays WHERE id=p_bay;SELECT * INTO v_tech FROM karratha_pdc.technicians WHERE id=p_technician;
 IF v_bay.id IS NULL OR NOT v_bay.active OR v_bay.stage_code<>v_op.stage_code OR v_tech.id IS NULL OR NOT v_tech.active OR NOT(v_op.stage_code=ANY(v_tech.stage_codes)) THEN RAISE EXCEPTION 'Active suitable bay and technician required'; END IF;
 IF v_vehicle.location NOT IN('on_site','yard_hold','in_transit') THEN RAISE EXCEPTION 'Vehicle location is not eligible for planning'; END IF;
 IF v_vehicle.location='in_transit' AND (v_vehicle.eta IS NULL OR (p_start AT TIME ZONE 'Australia/Perth')::date<v_vehicle.eta+7) THEN RAISE EXCEPTION 'In-transit planning requires ETA plus seven calendar days'; END IF;
 v_minutes:=ceil(v_op.estimated_hours*60*100/v_bay.efficiency_percent)::integer;v_segments:=karratha_pdc.segments(p_start,v_minutes,p_strict);
 v_end:=((v_segments->(jsonb_array_length(v_segments)-1))->>'end_at')::timestamptz;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_segments) s WHERE ((s->>'start_at')::timestamptz AT TIME ZONE 'Australia/Perth')::date=ANY(v_tech.leave_dates)) THEN RAISE EXCEPTION 'Technician is on leave'; END IF;
 IF EXISTS(SELECT 1 FROM karratha_pdc.bookings b WHERE b.id IS DISTINCT FROM p_id AND b.status IN('planned','started','stopped')
 AND ((b.status IN('started','stopped') AND (b.bay_id=p_bay OR b.technician_id=p_technician OR b.vehicle_id=v_vehicle.id))
 OR ((b.bay_id=p_bay OR b.technician_id=p_technician) AND EXISTS(SELECT 1 FROM jsonb_array_elements(v_segments) a CROSS JOIN jsonb_array_elements(b.segments) z
 WHERE (a->>'start_at')::timestamptz<(z->>'end_at')::timestamptz AND (z->>'start_at')::timestamptz<(a->>'end_at')::timestamptz))
 OR (b.vehicle_id=v_vehicle.id AND NOT(v_end+interval '1 hour'<=b.start_at OR b.end_at+interval '1 hour'<=p_start)))) THEN RAISE EXCEPTION 'Booking conflicts with a bay, technician, protected work or one-hour vehicle handover'; END IF;
 IF EXISTS(SELECT 1 FROM karratha_pdc.bookings b WHERE b.operation_id=p_operation AND b.id IS DISTINCT FROM p_id AND b.status IN('planned','started','stopped')) THEN RAISE EXCEPTION 'Operation already has a live booking'; END IF;
 IF EXISTS(SELECT 1 FROM karratha_pdc.bookings b WHERE b.id IS DISTINCT FROM p_id AND b.vehicle_id=v_vehicle.id AND b.status='completed'
 AND b.completed_at IS NOT NULL AND p_start>=coalesce(b.started_at,b.start_at) AND p_start<b.completed_at+interval '1 hour') THEN
 RAISE EXCEPTION 'Completed work requires one elapsed hour before the next vehicle job';END IF;
 RETURN jsonb_build_object('segments',v_segments,'end_at',v_end,'minutes',v_minutes,'parts_warning',v_op.parts_required AND NOT v_op.parts_received);
END $f$;

CREATE TRIGGER original_source_guard BEFORE UPDATE ON karratha_pdc.operations FOR EACH ROW EXECUTE FUNCTION karratha_pdc.preserve_source();
DO $security$ DECLARE v_table record; BEGIN
 FOR v_table IN SELECT tablename FROM pg_tables WHERE schemaname='karratha_pdc' LOOP
 EXECUTE format('ALTER TABLE karratha_pdc.%I ENABLE ROW LEVEL SECURITY',v_table.tablename);
 EXECUTE format('ALTER TABLE karratha_pdc.%I FORCE ROW LEVEL SECURITY',v_table.tablename);
 END LOOP;
END $security$;
REVOKE ALL ON ALL TABLES IN SCHEMA karratha_pdc FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA karratha_pdc FROM PUBLIC,anon,authenticated,service_role;
-- Seed only Craig's independently confirmed existing approved identity.
DO $owner$ DECLARE v_actor uuid; v_email text; BEGIN
 SELECT u.id,lower(u.email) INTO STRICT v_actor,v_email FROM auth.users u
 JOIN public.pdc_user_roles r ON r.auth_user_id=u.id AND lower(r.email)=lower(u.email)
 WHERE lower(u.email)='craig.watson@broometoyota.com.au' AND r.active AND r.account_status='approved' AND r.role::text='administrator'
 AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false) AND (u.banned_until IS NULL OR u.banned_until<=now());
 INSERT INTO karratha_pdc.memberships(id,email,display_name,role) VALUES(v_actor,v_email,'Craig Watson','administrator');
END $owner$;
CREATE FUNCTION karratha_pdc.context() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path=pg_catalog,karratha_pdc AS $f$
DECLARE v_member karratha_pdc.memberships; v_uid uuid:=auth.uid(); v_session text:=auth.jwt()->>'session_id';
BEGIN
 IF v_uid IS NULL OR auth.jwt()->>'role' IS DISTINCT FROM 'authenticated' OR coalesce(auth.jwt()->>'is_anonymous','false')='true' THEN RAISE EXCEPTION 'Karratha sign-in required' USING errcode='42501'; END IF;
 SELECT m.* INTO v_member FROM karratha_pdc.memberships m JOIN auth.users u ON u.id=m.id
 WHERE m.id=v_uid AND m.active AND lower(m.email)=lower(u.email)
 AND lower(u.email)=lower(coalesce(auth.jwt()->>'email',''))
 AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false) AND (u.banned_until IS NULL OR u.banned_until<=now());
 IF v_member.id IS NULL THEN RAISE EXCEPTION 'Karratha access is not approved' USING errcode='42501'; END IF;
 IF v_session IS NULL OR v_session !~ '^[0-9a-fA-F-]{36}$' THEN RAISE EXCEPTION 'Karratha session is no longer active' USING errcode='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.id=v_session::uuid AND s.user_id=v_uid AND (s.not_after IS NULL OR s.not_after>now())) THEN
 RAISE EXCEPTION 'Karratha session is no longer active' USING errcode='42501'; END IF;
 RETURN jsonb_build_object('centre','KARRATHA','user_id',v_uid,'display_name',v_member.display_name,'role',v_member.role,
 'membership_version',v_member.version,'can_edit',v_member.role IN('operator','administrator'),'can_import',v_member.role IN('operator','administrator'),
 'can_admin',v_member.role='administrator','revision',(SELECT revision FROM karratha_pdc.revision WHERE singleton));
END $f$;
CREATE FUNCTION karratha_pdc.text_value(p_value text,p_max integer,p_required boolean DEFAULT false) RETURNS text
 LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $f$ DECLARE v_text text:=btrim(coalesce(p_value,'')); BEGIN
 IF length(v_text)>p_max OR (p_required AND v_text='') OR v_text~'[\x00-\x08\x0B\x0C\x0E-\x1F]' THEN RAISE EXCEPTION 'Invalid bounded text field'; END IF; RETURN v_text;
END $f$;
CREATE FUNCTION karratha_pdc.date_value(p_value text) RETURNS date LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $f$
 DECLARE v_date date; BEGIN IF nullif(p_value,'') IS NULL THEN RETURN NULL; END IF;
 IF p_value !~ '^\d{4}-\d{2}-\d{2}$' THEN RAISE EXCEPTION 'Use an ISO calendar date'; END IF;
 v_date:=p_value::date; IF v_date<'2000-01-01' OR v_date>current_date+3660 THEN RAISE EXCEPTION 'Date is outside supported range'; END IF; RETURN v_date;
 END $f$;
CREATE FUNCTION karratha_pdc.keys(p_data jsonb,p_allowed text[]) RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $f$
 BEGIN IF jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_data) k WHERE NOT(k=ANY(p_allowed))) THEN RAISE EXCEPTION 'Unapproved Karratha field'; END IF; END $f$;
CREATE FUNCTION karratha_pdc.touch(p_type text,p_id uuid,p_action text,p_details jsonb) RETURNS bigint
 LANGUAGE plpgsql SET search_path=pg_catalog,karratha_pdc AS $f$
 DECLARE v_ctx jsonb:=karratha_pdc.context(); v_revision bigint; BEGIN
 INSERT INTO karratha_pdc.history(entity_type,entity_id,action,details,actor_id,actor_name)
 VALUES(p_type,p_id,p_action,p_details,auth.uid(),v_ctx->>'display_name');
 UPDATE karratha_pdc.revision SET revision=revision+1 WHERE singleton RETURNING revision INTO v_revision; RETURN v_revision;
 END $f$;
CREATE FUNCTION karratha_pdc.source_vin(p_data jsonb) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 WITH raw(priority,value) AS(VALUES
 (1,p_data->>'vin'),(2,p_data->>'fullVin'),(3,p_data->>'frameVin'),
 (4,coalesce(p_data->>'wmi','')||coalesce(p_data->>'vdsNumber',p_data->>'vds','')||coalesce(p_data->>'frame',''))),
 cleaned AS(SELECT priority,upper(regexp_replace(coalesce(value,''),'[^a-zA-Z0-9]','','g')) value FROM raw)
 SELECT value FROM cleaned WHERE value~'^[A-HJ-NPR-Z0-9]{17}$' ORDER BY priority LIMIT 1 $f$;
CREATE FUNCTION karratha_pdc.original_column(p_data jsonb,p_header text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT nullif(btrim(c->>'value'),'') FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data#>'{navisionRawEvidence,columns}')='array' THEN p_data#>'{navisionRawEvidence,columns}' ELSE '[]'::jsonb END) c
 WHERE lower(regexp_replace(coalesce(c->>'header',''),'[^a-zA-Z0-9]','','g'))=lower(regexp_replace(p_header,'[^a-zA-Z0-9]','','g')) ORDER BY c->>'header' LIMIT 1 $f$;
CREATE FUNCTION karratha_pdc.master(p_id uuid,p_identity jsonb DEFAULT NULL) RETURNS jsonb
 LANGUAGE sql STABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('navision_record_id',n.id,'source_identity',jsonb_build_object('source_system',n.source_system,'dealer_code',n.dealer_code,'source_record_id',n.source_record_id_normalized),
 'source_version',n.version,'source_updated_at',n.updated_at,'source_hash',n.row_hash,'source_current',n.is_current AND n.record_status='current',
 'stock_number',coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',''),
 'customer_name',coalesce(n.normalized_data->>'client',n.normalized_data->>'customer_name',''),
 'model',coalesce(n.normalized_data->>'vehicle',n.normalized_data->>'model',n.normalized_data->>'model_description',''),
 'vin',coalesce(karratha_pdc.source_vin(n.normalized_data),''),'toyota_order_number',coalesce(nullif(n.normalized_data->>'order',''),karratha_pdc.original_column(n.normalized_data,'Order'),''),
 'dealer_code',n.dealer_code,'source_location',coalesce(n.normalized_data->>'navisionSubLocationDescription',n.normalized_data->>'toyotaStatus',''),
 'kewdale_eta',coalesce(n.normalized_data->>'navisionKewdaleEta',''),'dealer_eta',coalesce(n.normalized_data->>'navisionEtaAtDealerBB',''),'navision_notes',coalesce(n.normalized_data->>'navisionDealerComments',''),
 'latest_export',EXISTS(SELECT 1 FROM public.navision_import_batches b WHERE b.id=n.last_seen_batch_id AND b.status='applied' AND b.rolled_back_at IS NULL
 AND b.id=(SELECT x.id FROM public.navision_import_batches x WHERE x.source_system=n.source_system AND x.dealer_code=n.dealer_code AND x.status='applied' AND x.rolled_back_at IS NULL ORDER BY x.result_revision DESC,x.applied_at DESC,x.id DESC LIMIT 1)))
 FROM public.navision_backend_records n WHERE n.id=p_id AND n.source_system='microsoft_navision'
 AND n.dealer_code IN(SELECT jsonb_array_elements_text(value->'allowed_dealer_codes') FROM karratha_pdc.settings WHERE key='import_contract')
 AND (p_identity IS NULL OR p_identity=jsonb_build_object('source_system',n.source_system,'dealer_code',n.dealer_code,'source_record_id',n.source_record_id_normalized))
 $f$;
CREATE FUNCTION karratha_pdc.dealer_code(p_value text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT CASE btrim(p_value) WHEN '014450' THEN '14450' WHEN '037047' THEN '37047' ELSE btrim(p_value) END $f$;
CREATE FUNCTION karratha_pdc.resolve_card(p_rows jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog,karratha_pdc AS $f$
 DECLARE v_first jsonb:=p_rows->0; v_stock text:=btrim(coalesce(v_first->>'stock_number','')); v_nid uuid; v_matches integer; v_master jsonb; v_reason text; v_status text:='unmatched';
 BEGIN
 IF (SELECT count(DISTINCT btrim(coalesce(x->>'stock_number',''))) FROM jsonb_array_elements(p_rows) x)<>1 THEN v_reason:='Conflicting stock numbers in the same job card';v_status:='conflict';
 ELSIF v_stock='' THEN v_reason:='Stock number is missing; identity review required';
 ELSE
 SELECT count(*),min(n.id::text)::uuid INTO v_matches,v_nid FROM public.navision_backend_records n
 WHERE n.source_system='microsoft_navision' AND n.is_current AND n.record_status='current'
 AND btrim(coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',''))=v_stock;
 IF v_matches<>1 THEN v_reason:=CASE WHEN v_matches=0 THEN 'No current exact Navision stock match' ELSE 'More than one current stock match' END;v_nid:=NULL;
 ELSE v_master:=karratha_pdc.master(v_nid);
 IF v_master IS NULL THEN v_reason:='Confirm the permitted Navision dealer scope';v_nid:=NULL;
 ELSIF EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE nullif(btrim(x->>'dealer_code'),'') IS NOT NULL AND karratha_pdc.dealer_code(x->>'dealer_code')<>v_master->>'dealer_code')
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE nullif(btrim(x->>'vin'),'') IS NOT NULL AND upper(btrim(x->>'vin'))<>upper(v_master->>'vin'))
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE nullif(btrim(x->>'toyota_order_number'),'') IS NOT NULL AND upper(btrim(x->>'toyota_order_number'))<>upper(btrim(v_master->>'toyota_order_number'))) THEN
 v_reason:='Source dealer, VIN or Toyota order conflicts with Navision'; v_status:='conflict';v_nid:=NULL;
 ELSE v_status:='matched'; END IF;
 END IF;
 END IF;
 RETURN jsonb_build_object('job_card_number',upper(btrim(v_first->>'repair_order_number')),'store_code','135','stock_number',v_stock,
 'navision_record_id',v_nid,'source_identity',CASE WHEN v_nid IS NOT NULL THEN v_master->'source_identity' END,
 'source_snapshot',CASE WHEN v_nid IS NOT NULL THEN v_master ELSE '{}'::jsonb END,'source_version',CASE WHEN v_nid IS NOT NULL THEN v_master->'source_version' END,
 'source_updated_at',CASE WHEN v_nid IS NOT NULL THEN v_master->'source_updated_at' END,'identity_status',v_status,'operations',p_rows,
 'declared_dealers',coalesce((SELECT jsonb_agg(jsonb_build_object('raw',x->>'dealer_code','normalized',karratha_pdc.dealer_code(x->>'dealer_code')))
 FROM jsonb_array_elements(p_rows) x WHERE nullif(btrim(x->>'dealer_code'),'') IS NOT NULL),'[]'::jsonb),'reason',v_reason);
 END $f$;
CREATE FUNCTION public.get_karratha_pdc_context() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $f$ SELECT karratha_pdc.context() $f$;
CREATE FUNCTION public.get_karratha_pdc_snapshot(p_date_from date,p_date_to date) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $f$ SELECT karratha_pdc.snapshot(p_date_from,p_date_to) $f$;
CREATE FUNCTION public.preview_karratha_nuvu_import(p_file_name text,p_file_sha256 text,p_rows jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $f$ SELECT karratha_pdc.preview(p_file_name,p_file_sha256,p_rows) $f$;
CREATE FUNCTION public.apply_karratha_nuvu_import(p_preview_id uuid,p_expected_version integer) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $f$ SELECT karratha_pdc.apply_import(p_preview_id,p_expected_version) $f$;
CREATE FUNCTION public.save_karratha_pdc(p_action text,p_id uuid,p_expected_version integer,p_data jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $f$ SELECT karratha_pdc.save(p_action,p_id,p_expected_version,p_data) $f$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA karratha_pdc FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA karratha_pdc TO authenticated;
GRANT EXECUTE ON FUNCTION karratha_pdc.context(),karratha_pdc.snapshot(date,date),karratha_pdc.preview(text,text,jsonb),karratha_pdc.apply_import(uuid,integer),karratha_pdc.save(text,uuid,integer,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.get_karratha_pdc_context(),public.get_karratha_pdc_snapshot(date,date),public.preview_karratha_nuvu_import(text,text,jsonb),public.apply_karratha_nuvu_import(uuid,integer),public.save_karratha_pdc(text,uuid,integer,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_karratha_pdc_context(),public.get_karratha_pdc_snapshot(date,date),public.preview_karratha_nuvu_import(text,text,jsonb),public.apply_karratha_nuvu_import(uuid,integer),public.save_karratha_pdc(text,uuid,integer,jsonb) TO authenticated;

-- Last SQL before COMMIT. Any protected mutation aborts the entire migration.
do $boundary$
declare p record; v_hash text;v_count bigint;v_role_hash text;
begin
 for p in select * from pg_temp.karratha_protected_catalog loop
  v_hash:=null;
  case p.kind
  when 'function' then select md5(concat_ws('|',pg_get_functiondef(x.oid),x.proowner::text,x.proacl::text,x.proconfig::text)) into v_hash from pg_proc x where x.oid=p.object_id;
  when 'relation' then select md5(to_jsonb(x)::text) into v_hash from pg_class x where x.oid=p.object_id;
  when 'index' then select md5(to_jsonb(x)::text) into v_hash from pg_index x where x.indexrelid=p.object_id;
  when 'constraint' then select md5(to_jsonb(x)::text) into v_hash from pg_constraint x where x.oid=p.object_id;
  when 'trigger' then select md5(to_jsonb(x)::text) into v_hash from pg_trigger x where x.oid=p.object_id;
  when 'policy' then select md5(to_jsonb(x)::text) into v_hash from pg_policy x where x.oid=p.object_id;
  when 'namespace' then select md5(to_jsonb(x)::text) into v_hash from pg_namespace x where x.oid=p.object_id;
  when 'roles' then select md5(to_jsonb(x)::text) into v_hash from pg_roles x where x.oid=p.object_id;
  else raise exception 'Unknown protected catalog kind';
  end case;
  if v_hash is distinct from p.fingerprint then raise exception 'Existing protected % object % changed',p.kind,p.object_id;end if;
 end loop;
 -- New private Karratha objects/RPCs are allowed; new shared-table state objects
 -- or global/default role privileges are not part of this additive boundary.
 for p in select * from pg_temp.karratha_protected_counts loop
  case p.kind
  when 'relation' then select count(*) into v_count from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('public','pdc_sales_private','auth','storage') and c.relkind in ('r','p','v','m','S','i','I','f');
  when 'index' then select count(*) into v_count from pg_index x join pg_class c on c.oid=x.indrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('public','pdc_sales_private','auth','storage');
  when 'constraint' then select count(*) into v_count from pg_constraint x join pg_namespace n on n.oid=x.connamespace
   where n.nspname in ('public','pdc_sales_private','auth','storage');
  when 'trigger' then select count(*) into v_count from pg_trigger x join pg_class c on c.oid=x.tgrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('public','pdc_sales_private','auth','storage');
  when 'policy' then select count(*) into v_count from pg_policy x join pg_class c on c.oid=x.polrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('public','pdc_sales_private','auth','storage');
  when 'namespace' then select count(*) into v_count from pg_namespace n where n.nspname in ('public','pdc_sales_private','auth','storage');
  when 'roles' then select count(*) into v_count from pg_roles;
  when 'defaults' then select count(*) into v_count from pg_default_acl x where x.defaclnamespace in
   (select object_id from pg_temp.karratha_protected_catalog where kind='namespace') or x.defaclnamespace=0;
  end case;
  if v_count is distinct from p.total then raise exception 'Shared protected % inventory changed',p.kind;end if;
 end loop;
 for p in select * from pg_temp.karratha_protected_columns loop
  select md5(to_jsonb(a)::text||coalesce(pg_get_expr(d.adbin,d.adrelid),'')) into v_hash from pg_attribute a
   left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
   where a.attrelid=p.object_id and a.attnum=p.attribute_number and not a.attisdropped;
  if v_hash is distinct from p.fingerprint then raise exception 'Existing protected column %/% changed',p.object_id,p.attribute_number;end if;
 end loop;
 for p in select * from pg_temp.karratha_protected_defaults loop
  select md5(to_jsonb(d)::text) into v_hash from pg_default_acl d where d.oid=p.object_id;
  if v_hash is distinct from p.fingerprint then raise exception 'Existing shared default privilege object % changed',p.object_id;end if;
 end loop;
 select md5(coalesce(string_agg(to_jsonb(m)::text,E'\n' order by m.roleid,m.member,m.grantor),'')) into v_role_hash from pg_auth_members m;
 if v_role_hash is distinct from (select fingerprint from pg_temp.karratha_protected_role_bindings) then raise exception 'Existing role memberships changed';end if;
 for p in select * from pg_temp.karratha_protected_data order by schema_name,table_name loop
  execute format('select count(*),md5(coalesce(string_agg(h,'''' order by h),'''')) from (select md5(to_jsonb(x)::text) h from %I.%I x) q',p.schema_name,p.table_name) into v_count,v_hash;
  if v_count is distinct from p.row_count or v_hash is distinct from p.row_hash then raise exception 'Existing protected %.% data changed',p.schema_name,p.table_name;end if;
 end loop;
 raise notice 'Existing PMB/shared catalog and scoped data unchanged: % objects, % columns, % data tables',
  (select count(*) from pg_temp.karratha_protected_catalog),(select count(*) from pg_temp.karratha_protected_columns),
  (select count(*) from pg_temp.karratha_protected_data);
end $boundary$;
