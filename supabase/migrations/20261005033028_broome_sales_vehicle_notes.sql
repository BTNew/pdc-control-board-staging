-- Staff notes follow the stable sales tracking identity, including Toyota-order-only vehicles.
DO $guard$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF; END $guard$;

CREATE TABLE pdc_sales_private.vehicle_notes (
 tracking_id uuid PRIMARY KEY,
 notes text NOT NULL DEFAULT '' CHECK(length(notes)<=4000),
 custom_information text NOT NULL DEFAULT '' CHECK(length(custom_information)<=4000),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 created_by uuid NOT NULL REFERENCES auth.users(id),
 updated_by uuid NOT NULL REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE pdc_sales_private.vehicle_notes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_sales_private.vehicle_notes FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_sales_private.vehicle_notes_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','public','pdc_sales_private'
AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); items jsonb; result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in to view vehicle notes' USING errcode='42501'; END IF;
 items:=pdc_sales_private.visibility_source_snapshot(false)->'items';
 SELECT coalesce(jsonb_agg(jsonb_build_object('tracking_id',n.tracking_id,'notes',n.notes,
 'custom_information',n.custom_information,'version',n.version,'updated_at',n.updated_at) ORDER BY n.tracking_id),'[]'::jsonb)
 INTO result FROM pdc_sales_private.vehicle_notes n
 WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(items) e WHERE e->>'tracking_id'=n.tracking_id::text
 AND NOT coalesce((e->>'identity_conflict')::boolean,false));
 RETURN result;
END $fn$;

CREATE FUNCTION pdc_sales_private.save_vehicle_notes(p_tracking_id uuid,p_notes text,p_custom_information text,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path='pg_catalog','public','pdc_sales_private'
AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.crm_context(); items jsonb; prior pdc_sales_private.vehicle_notes; saved pdc_sales_private.vehicle_notes;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in to save vehicle notes' USING errcode='42501'; END IF;
 IF p_tracking_id IS NULL OR p_expected_version IS NULL OR p_expected_version<0
 OR p_notes IS NULL OR p_custom_information IS NULL OR length(p_notes)>4000 OR length(p_custom_information)>4000 THEN
  RAISE EXCEPTION 'Provide vehicle notes and custom information of up to 4000 characters each';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-vehicle-notes:'||p_tracking_id::text,0));
 items:=pdc_sales_private.visibility_source_snapshot(false)->'items';
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(items) e WHERE e->>'tracking_id'=p_tracking_id::text
 AND NOT coalesce((e->>'identity_conflict')::boolean,false)) THEN
  RAISE EXCEPTION 'Vehicle is outside your current sales access' USING errcode='42501';
 END IF;
 SELECT * INTO prior FROM pdc_sales_private.vehicle_notes WHERE tracking_id=p_tracking_id FOR UPDATE;
 -- An identical retry after a lost response does not duplicate the change or audit.
 IF prior.tracking_id IS NOT NULL AND prior.notes=p_notes AND prior.custom_information=p_custom_information
 AND p_expected_version IN (prior.version,prior.version-1) THEN saved:=prior;
 ELSE
  IF p_expected_version<>coalesce(prior.version,0) THEN
   RAISE EXCEPTION 'Notes changed elsewhere. Reload the saved notes before updating them' USING errcode='40001';
  END IF;
  IF prior.tracking_id IS NULL THEN
   INSERT INTO pdc_sales_private.vehicle_notes(tracking_id,notes,custom_information,created_by,updated_by)
   VALUES(p_tracking_id,p_notes,p_custom_information,auth.uid(),auth.uid()) RETURNING * INTO saved;
  ELSE
   UPDATE pdc_sales_private.vehicle_notes SET notes=p_notes,custom_information=p_custom_information,version=version+1,
   updated_at=clock_timestamp(),updated_by=auth.uid() WHERE tracking_id=p_tracking_id RETURNING * INTO saved;
  END IF;
  INSERT INTO pdc_sales_private.crm_audit(record_id,kind,actor_id,before_data,after_data)
  VALUES(p_tracking_id,'vehicle_notes',auth.uid(),CASE WHEN prior.tracking_id IS NULL THEN NULL ELSE
  jsonb_build_object('notes',prior.notes,'custom_information',prior.custom_information,'version',prior.version) END,
  jsonb_build_object('notes',saved.notes,'custom_information',saved.custom_information,'version',saved.version));
 END IF;
 RETURN jsonb_build_object('tracking_id',saved.tracking_id,'notes',saved.notes,'custom_information',saved.custom_information,
 'version',saved.version,'updated_at',saved.updated_at);
END $fn$;

CREATE FUNCTION public.get_broome_sales_vehicle_notes()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path='pg_catalog','pdc_sales_private'
AS $fn$ SELECT pdc_sales_private.vehicle_notes_snapshot(); $fn$;
CREATE FUNCTION public.save_broome_sales_vehicle_notes(p_tracking_id uuid,p_notes text,p_custom_information text,p_expected_version integer)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path='pg_catalog','pdc_sales_private'
AS $fn$ SELECT pdc_sales_private.save_vehicle_notes(p_tracking_id,p_notes,p_custom_information,p_expected_version); $fn$;
REVOKE ALL ON FUNCTION pdc_sales_private.vehicle_notes_snapshot(),pdc_sales_private.save_vehicle_notes(uuid,text,text,integer),
 public.get_broome_sales_vehicle_notes(),public.save_broome_sales_vehicle_notes(uuid,text,text,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.vehicle_notes_snapshot(),pdc_sales_private.save_vehicle_notes(uuid,text,text,integer),
 public.get_broome_sales_vehicle_notes(),public.save_broome_sales_vehicle_notes(uuid,text,text,integer) TO authenticated;
NOTIFY pgrst,'reload schema';
