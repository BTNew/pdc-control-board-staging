-- Three sales-only ordering states; preserve legacy ticks and all PDC records.
DO $$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'STAGING required'; END IF;
END $$;
ALTER TABLE pdc_sales_private.ordering_progress ADD COLUMN tint_complete boolean NOT NULL DEFAULT false;
CREATE OR REPLACE FUNCTION pdc_sales_private.snapshot_with_ordering()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pdc_sales_private AS $$
DECLARE base jsonb:=pdc_sales_private.snapshot(); items jsonb;
BEGIN
 SELECT coalesce(jsonb_agg(e.value||jsonb_build_object(
  'tint_complete',coalesce(p.tint_complete,false),'tint',coalesce(p.tint,false),'build_po',coalesce(p.build_po,false),'build_complete',coalesce(p.build_complete,false),
  'tray_ordered',coalesce(p.tray_ordered,false),'tray_complete',coalesce(p.tray_complete,false),
  'ordering_version',coalesce(p.version,0),'ordering_updated_at',p.updated_at
 ) ORDER BY e.ordinality),'[]'::jsonb) INTO items
 FROM jsonb_array_elements(base->'items') WITH ORDINALITY e(value,ordinality)
 LEFT JOIN pdc_sales_private.ordering_progress p ON p.tracking_id=(e.value->>'tracking_id')::uuid;
 RETURN jsonb_set(base,'{items}',items);
END $$;

CREATE OR REPLACE FUNCTION pdc_sales_private.set_ordering_flag(p_tracking_id uuid,p_flag text,p_checked boolean,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,pdc_sales_private AS $$
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
  version=current.version+1,updated_at=now(),updated_by=auth.uid()
 WHERE current.version=p_expected_version
 RETURNING jsonb_build_object('tracking_id',tracking_id,'tint_complete',tint_complete,'tint',tint,'build_po',build_po,'build_complete',build_complete,
  'tray_ordered',tray_ordered,'tray_complete',tray_complete,'ordering_version',version,'ordering_updated_at',updated_at) INTO result;
 IF result IS NULL THEN RAISE EXCEPTION 'Checklist changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
 RETURN result;
END $$;


CREATE FUNCTION pdc_sales_private.set_ordering_status(p_tracking_id uuid,p_item text,p_status text,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $$
DECLARE base jsonb:=pdc_sales_private.snapshot(); target jsonb; result jsonb; raised boolean; finished boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 SELECT e INTO target FROM jsonb_array_elements(base->'items') e WHERE e->>'tracking_id'=p_tracking_id::text;
 IF target IS NULL OR coalesce((target->>'identity_conflict')::boolean,false) THEN RAISE EXCEPTION 'This order is not available for your ordering status' USING errcode='42501'; END IF;
 IF p_item IS NULL OR p_item NOT IN ('tint','build','tray') OR p_status IS NULL OR p_status NOT IN ('not_needed','orders_raised','completed') THEN RAISE EXCEPTION 'Choose TINT, BUILD or TRAY and one valid ordering status'; END IF;
 IF p_expected_version IS NULL OR p_expected_version<0 OR coalesce((SELECT version FROM pdc_sales_private.ordering_progress WHERE tracking_id=p_tracking_id),0)<>p_expected_version THEN RAISE EXCEPTION 'Ordering status changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
 raised:=p_status<>'not_needed'; finished:=p_status='completed';
 INSERT INTO pdc_sales_private.ordering_progress AS current(tracking_id,tint,tint_complete,build_po,build_complete,tray_ordered,tray_complete,updated_by)
 VALUES(p_tracking_id,p_item='tint' AND raised,p_item='tint' AND finished,p_item='build' AND raised,p_item='build' AND finished,p_item='tray' AND raised,p_item='tray' AND finished,auth.uid())
 ON CONFLICT(tracking_id) DO UPDATE SET
 tint=CASE WHEN p_item='tint' THEN raised ELSE current.tint END,
 tint_complete=CASE WHEN p_item='tint' THEN finished ELSE current.tint_complete END,
 build_po=CASE WHEN p_item='build' THEN raised ELSE current.build_po END,
 build_complete=CASE WHEN p_item='build' THEN finished ELSE current.build_complete END,
 tray_ordered=CASE WHEN p_item='tray' THEN raised ELSE current.tray_ordered END,
 tray_complete=CASE WHEN p_item='tray' THEN finished ELSE current.tray_complete END,
 version=current.version+1,updated_at=now(),updated_by=auth.uid()
 WHERE current.version=p_expected_version
 RETURNING jsonb_build_object('tracking_id',tracking_id,'tint',tint,'tint_complete',tint_complete,'build_po',build_po,'build_complete',build_complete,'tray_ordered',tray_ordered,'tray_complete',tray_complete,'ordering_version',version,'ordering_updated_at',updated_at) INTO result;
 IF result IS NULL THEN RAISE EXCEPTION 'Ordering status changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
 RETURN result;
END $$;
CREATE FUNCTION public.set_broome_sales_ordering_status(p_tracking_id uuid,p_item text,p_status text,p_expected_version integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog
AS $$ SELECT pdc_sales_private.set_ordering_status(p_tracking_id,p_item,p_status,p_expected_version); $$;
REVOKE ALL ON FUNCTION pdc_sales_private.set_ordering_status(uuid,text,text,integer),public.set_broome_sales_ordering_status(uuid,text,text,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.set_ordering_status(uuid,text,text,integer),public.set_broome_sales_ordering_status(uuid,text,text,integer) TO authenticated;
NOTIFY pgrst,'reload schema';
