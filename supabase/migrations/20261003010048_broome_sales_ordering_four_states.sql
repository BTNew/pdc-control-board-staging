-- STAGING ONLY. Four distinct sales ordering choices; no PDC/public vehicle fields change.
-- Existing false pairs mean Not decided; no historical requirement decision is inferred.
DO $guard$
DECLARE item record;
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  OR current_setting('app.environment',true)='production' THEN
  RAISE EXCEPTION 'Exact staging environment required';
 END IF;
 FOR item IN SELECT * FROM (VALUES
  ('pdc_sales_private.set_ordering_flag(uuid,text,boolean,integer)','ad1084a8eceb42141067a4f256ab1dcb'),
  ('pdc_sales_private.set_ordering_status(uuid,text,text,integer)','d446afcdb0d6faf188efbb9e5f1b3e0c'),
  ('pdc_sales_private.snapshot_with_ordering()','8aa5fe655234788a321c2f36f068e8c1')
 ) expected(signature,definition_md5) LOOP
  IF md5(pg_get_functiondef(item.signature::regprocedure))<>item.definition_md5 THEN
   RAISE EXCEPTION 'Live sales function changed: %',item.signature;
  END IF;
 END LOOP;
END $guard$;
ALTER TABLE pdc_sales_private.ordering_progress
 ADD COLUMN tint_not_required boolean NOT NULL DEFAULT false,
 ADD COLUMN build_not_required boolean NOT NULL DEFAULT false,
 ADD COLUMN tray_not_required boolean NOT NULL DEFAULT false,
 ADD CONSTRAINT tint_not_required_consistent CHECK (NOT tint_not_required OR NOT (tint OR tint_complete)),
 ADD CONSTRAINT build_not_required_consistent CHECK (NOT build_not_required OR NOT (build_po OR build_complete)),
 ADD CONSTRAINT tray_not_required_consistent CHECK (NOT tray_not_required OR NOT (tray_ordered OR tray_complete));

CREATE OR REPLACE FUNCTION pdc_sales_private.snapshot_with_ordering()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE base jsonb:=pdc_sales_private.snapshot(); items jsonb;
BEGIN
 SELECT coalesce(jsonb_agg(e.value||jsonb_build_object(
  'tint_complete',coalesce(p.tint_complete,false),'tint',coalesce(p.tint,false),'build_po',coalesce(p.build_po,false),'build_complete',coalesce(p.build_complete,false),
  'tray_ordered',coalesce(p.tray_ordered,false),'tray_complete',coalesce(p.tray_complete,false),
  'tint_not_required',coalesce(p.tint_not_required,false),'build_not_required',coalesce(p.build_not_required,false),'tray_not_required',coalesce(p.tray_not_required,false),
  'ordering_version',coalesce(p.version,0),'ordering_updated_at',p.updated_at
 ) ORDER BY e.ordinality),'[]'::jsonb) INTO items
 FROM jsonb_array_elements(base->'items') WITH ORDINALITY e(value,ordinality)
 LEFT JOIN pdc_sales_private.ordering_progress p ON p.tracking_id=(e.value->>'tracking_id')::uuid;
 RETURN jsonb_set(base,'{items}',items);
END $function$
;

CREATE OR REPLACE FUNCTION pdc_sales_private.set_ordering_status(p_tracking_id uuid, p_item text, p_status text, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE base jsonb:=pdc_sales_private.snapshot(); target jsonb; result jsonb; raised boolean; finished boolean; not_required boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 SELECT e INTO target FROM jsonb_array_elements(base->'items') e WHERE e->>'tracking_id'=p_tracking_id::text;
 IF target IS NULL OR coalesce((target->>'identity_conflict')::boolean,false) THEN RAISE EXCEPTION 'This order is not available for your ordering status' USING errcode='42501'; END IF;
 IF p_item IS NULL OR p_item NOT IN ('tint','build','tray') OR p_status IS NULL OR p_status NOT IN ('not_decided','not_needed','orders_raised','completed') THEN RAISE EXCEPTION 'Choose TINT, BUILD or TRAY and one valid ordering status'; END IF;
 IF p_expected_version IS NULL OR p_expected_version<0 OR coalesce((SELECT version FROM pdc_sales_private.ordering_progress WHERE tracking_id=p_tracking_id),0)<>p_expected_version THEN RAISE EXCEPTION 'Ordering status changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
 raised:=p_status IN ('orders_raised','completed'); finished:=p_status='completed'; not_required:=p_status='not_needed';
 INSERT INTO pdc_sales_private.ordering_progress AS current(tracking_id,tint,tint_complete,build_po,build_complete,tray_ordered,tray_complete,tint_not_required,build_not_required,tray_not_required,updated_by)
 VALUES(p_tracking_id,p_item='tint' AND raised,p_item='tint' AND finished,p_item='build' AND raised,p_item='build' AND finished,p_item='tray' AND raised,p_item='tray' AND finished,p_item='tint' AND not_required,p_item='build' AND not_required,p_item='tray' AND not_required,auth.uid())
 ON CONFLICT(tracking_id) DO UPDATE SET
 tint=CASE WHEN p_item='tint' THEN raised ELSE current.tint END,
 tint_complete=CASE WHEN p_item='tint' THEN finished ELSE current.tint_complete END,
 build_po=CASE WHEN p_item='build' THEN raised ELSE current.build_po END,
 build_complete=CASE WHEN p_item='build' THEN finished ELSE current.build_complete END,
 tray_ordered=CASE WHEN p_item='tray' THEN raised ELSE current.tray_ordered END,
 tray_complete=CASE WHEN p_item='tray' THEN finished ELSE current.tray_complete END,
 tint_not_required=CASE WHEN p_item='tint' THEN not_required ELSE current.tint_not_required END,
 build_not_required=CASE WHEN p_item='build' THEN not_required ELSE current.build_not_required END,
 tray_not_required=CASE WHEN p_item='tray' THEN not_required ELSE current.tray_not_required END,
 version=current.version+1,updated_at=now(),updated_by=auth.uid()
 WHERE current.version=p_expected_version
 RETURNING jsonb_build_object('tracking_id',tracking_id,'tint',tint,'tint_complete',tint_complete,'build_po',build_po,'build_complete',build_complete,'tray_ordered',tray_ordered,'tray_complete',tray_complete,'tint_not_required',tint_not_required,'build_not_required',build_not_required,'tray_not_required',tray_not_required,'ordering_version',version,'ordering_updated_at',updated_at) INTO result;
 IF result IS NULL THEN RAISE EXCEPTION 'Ordering status changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
 RETURN result;
END $function$
;

CREATE OR REPLACE FUNCTION pdc_sales_private.set_ordering_flag(p_tracking_id uuid, p_flag text, p_checked boolean, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE base jsonb:=pdc_sales_private.snapshot(); target jsonb; result jsonb;
BEGIN
 -- The existing approved-account snapshot enforces dealer, current salesperson,
 -- manual assignments, disabled account/scope and deletion authority on every write.
 SELECT e INTO target FROM jsonb_array_elements(base->'items') e WHERE e->>'tracking_id'=p_tracking_id::text;
 IF target IS NULL OR coalesce((target->>'identity_conflict')::boolean,false) THEN RAISE EXCEPTION 'This order is not available for your ordering checklist' USING errcode='42501'; END IF;
 IF p_flag IS NULL OR p_flag NOT IN ('tint','build_po','build_complete','tray_ordered','tray_complete') OR p_checked IS NULL THEN RAISE EXCEPTION 'Choose one valid ordering checkbox'; END IF;
 IF p_expected_version IS NULL OR p_expected_version<0 OR coalesce((SELECT version FROM pdc_sales_private.ordering_progress WHERE tracking_id=p_tracking_id),0)<>p_expected_version THEN RAISE EXCEPTION 'Checklist changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
 INSERT INTO pdc_sales_private.ordering_progress AS current(
  tracking_id,tint,build_po,build_complete,tray_ordered,tray_complete,updated_by)
 VALUES(p_tracking_id,
  CASE WHEN p_flag='tint' THEN p_checked ELSE false END,
  CASE WHEN p_flag='build_po' THEN p_checked ELSE false END,
  CASE WHEN p_flag='build_complete' THEN p_checked ELSE false END,
  CASE WHEN p_flag='tray_ordered' THEN p_checked ELSE false END,
  CASE WHEN p_flag='tray_complete' THEN p_checked ELSE false END,auth.uid())
 ON CONFLICT(tracking_id) DO UPDATE SET
  tint=CASE WHEN p_flag='tint' THEN p_checked ELSE current.tint END,
  tint_complete=CASE WHEN p_flag='tint' AND NOT p_checked THEN false ELSE current.tint_complete END,
  build_po=CASE WHEN p_flag='build_po' THEN p_checked ELSE current.build_po END,
  build_complete=CASE WHEN p_flag='build_complete' THEN p_checked ELSE current.build_complete END,
  tray_ordered=CASE WHEN p_flag='tray_ordered' THEN p_checked ELSE current.tray_ordered END,
  tray_complete=CASE WHEN p_flag='tray_complete' THEN p_checked ELSE current.tray_complete END,
  tint_not_required=CASE WHEN p_flag='tint' THEN false ELSE current.tint_not_required END,
  build_not_required=CASE WHEN p_flag IN ('build_po','build_complete') THEN false ELSE current.build_not_required END,
  tray_not_required=CASE WHEN p_flag IN ('tray_ordered','tray_complete') THEN false ELSE current.tray_not_required END,
  version=current.version+1,updated_at=now(),updated_by=auth.uid()
 WHERE current.version=p_expected_version
 RETURNING jsonb_build_object('tracking_id',tracking_id,'tint_complete',tint_complete,'tint',tint,'build_po',build_po,'build_complete',build_complete,
  'tray_ordered',tray_ordered,'tray_complete',tray_complete,'tint_not_required',tint_not_required,'build_not_required',build_not_required,'tray_not_required',tray_not_required,'ordering_version',version,'ordering_updated_at',updated_at) INTO result;
 IF result IS NULL THEN RAISE EXCEPTION 'Checklist changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
 RETURN result;
END $function$
;
-- Replacing the existing private functions preserves OIDs, owners, SECURITY DEFINER gates and ACLs.
-- The public invoker wrappers, current-source/visibility projection and PDC tables are untouched.
DO $post$
DECLARE item record;
BEGIN
 FOR item IN SELECT * FROM (VALUES
  ('pdc_sales_private.snapshot_with_ordering()'),
  ('pdc_sales_private.set_ordering_status(uuid,text,text,integer)'),
  ('pdc_sales_private.set_ordering_flag(uuid,text,boolean,integer)'),
  ('public.set_broome_sales_ordering_status(uuid,text,text,integer)'),
  ('public.set_broome_sales_ordering_flag(uuid,text,boolean,integer)')
 ) functions(signature) LOOP
  IF (SELECT proacl::text FROM pg_proc WHERE oid=item.signature::regprocedure)<>'{postgres=X/postgres,authenticated=X/postgres}'
   OR has_function_privilege('anon',item.signature,'execute')
   OR has_function_privilege('service_role',item.signature,'execute') THEN
   RAISE EXCEPTION 'Sales function ACL changed: %',item.signature;
  END IF;
 END LOOP;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='pdc_sales_private.ordering_progress'::regclass)
  OR (SELECT relacl::text FROM pg_class WHERE oid='pdc_sales_private.ordering_progress'::regclass)<>'{postgres=arwdDxtm/postgres}' THEN
  RAISE EXCEPTION 'Private ordering table grants or RLS changed';
 END IF;
END $post$;
NOTIFY pgrst,'reload schema';
