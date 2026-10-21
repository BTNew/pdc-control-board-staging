-- r426 (F39, Craig 21 Oct, roles matrix): the Board's sales-prep ticks (Tint / Build PO / Tray) are controller/admin only. Staging only.
-- Before: update_pdc_vehicle_sales_preparation accepted viewer, operator and administrator, so a viewer (meant to be read-only)
-- could save the ticks; importers were refused but the screen still offered them the ticks (frontend fix in app.js, same release).
-- After: operator (controller) and administrator only. Everything else in the function is byte for byte unchanged.
-- Not touched: the Pit/Weigh tick (no restrictions for now), the hidden Karratha 135 copy, the clock tick.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r426: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r426: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r426: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r426: clock tick changed'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.update_pdc_vehicle_sales_preparation(uuid,integer,text,boolean)') AND md5(p.prosrc)='8b6b7ae47fb0656679aeb539c262bc21' AND md5(coalesce(p.proacl::text,'')||p.prosecdef::text||p.provolatile::text||p.proowner::regrole::text||coalesce(array_to_string(p.proconfig,'|'),''))='47d2ee6f05f51cc587634ba8b0604205')<>1 THEN RAISE EXCEPTION 'r426: function is not the expected version'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r426' OR signature='public.update_pdc_vehicle_sales_preparation(uuid,integer,text,boolean)')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sales_prep_ticks_role_guard' OR added_in='r426') THEN RAISE EXCEPTION 'r426: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=226) THEN RAISE EXCEPTION 'r426: sort_order 226 taken'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.update_pdc_vehicle_sales_preparation(p_vehicle_id uuid, p_expected_version integer, p_field text, p_value boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_role text := coalesce(public.current_pdc_user_role()::text, '');
  v_actor uuid := auth.uid();
  v_actor_email text;
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_field text := lower(btrim(coalesce(p_field, '')));
begin
  -- r426 (F39): controller (operator) and administrator only; viewers and importers are read-only.
  if v_actor is null or v_role not in ('operator', 'administrator') then
    return jsonb_build_object('ok', false, 'code', 'not_authorized');
  end if;
  if v_field not in ('tint_raised', 'build_po_raised', 'build_complete', 'tray_ordered', 'tray_complete') then
    return jsonb_build_object('ok', false, 'code', 'invalid_field');
  end if;

  select * into v_before from public.vehicles where id = p_vehicle_id for update;
  if not found or v_before.deleted_at is not null then
    return jsonb_build_object('ok', false, 'code', 'vehicle_not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'code', 'version_conflict', 'data',
      jsonb_build_object('vehicle_id', v_before.id, 'vehicle_version', v_before.version));
  end if;

  update public.vehicles
  set sales_tint_raised = case when v_field = 'tint_raised' then p_value else sales_tint_raised end,
      sales_build_po_raised = case when v_field = 'build_po_raised' then p_value else sales_build_po_raised end,
      sales_build_complete = case when v_field = 'build_complete' then p_value else sales_build_complete end,
      sales_tray_ordered = case when v_field = 'tray_ordered' then p_value else sales_tray_ordered end,
      sales_tray_complete = case when v_field = 'tray_complete' then p_value else sales_tray_complete end,
      sales_preparation_updated_at = clock_timestamp(),
      sales_preparation_updated_by = v_actor,
      updated_at = clock_timestamp(),
      updated_by = v_actor,
      version = version + 1
  where id = p_vehicle_id
  returning * into v_after;

  select email into v_actor_email
  from public.pdc_user_roles
  where auth_user_id = v_actor and active and account_status::text = 'approved'
  order by updated_at desc limit 1;

  insert into public.audit_events(
    action, table_name, row_id, vehicle_id, actor_id, actor_email,
    before_data, after_data, metadata
  ) values (
    'sales_preparation_updated', 'vehicles', v_after.id, v_after.id, v_actor, v_actor_email,
    jsonb_build_object('field', v_field, 'value', case v_field
      when 'tint_raised' then v_before.sales_tint_raised
      when 'build_po_raised' then v_before.sales_build_po_raised
      when 'build_complete' then v_before.sales_build_complete
      when 'tray_ordered' then v_before.sales_tray_ordered
      else v_before.sales_tray_complete end),
    jsonb_build_object('field', v_field, 'value', p_value),
    jsonb_build_object('scope', 'staging_sales_dashboard')
  );

  return jsonb_build_object(
    'ok', true,
    'code', 'sales_preparation_updated',
    'data', jsonb_build_object(
      'vehicle_id', v_after.id,
      'vehicle_version', v_after.version,
      'sales_preparation', public.pdc_vehicle_sales_dashboard_json(v_after.id)->'sales_preparation'
    )
  );
end
$function$
;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.update_pdc_vehicle_sales_preparation(uuid,integer,text,boolean)','21c28f7dbf99e22f0c47e0f735b732ac','r426','sales-prep ticks controller/admin only (was 8b6b7ae47fb0656679aeb539c262bc21)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('sales_prep_ticks_role_guard','F39','The Board sales-prep ticks (Tint / Build PO / Tray) save only for controllers (operator) and administrators; viewers and importers are refused; the hidden Karratha 135 copy is untouched.',
 $chk$WITH f AS (
 SELECT
  (SELECT position('v_role not in (''operator'', ''administrator'')' IN p.prosrc)>0 AND position('''viewer''' IN p.prosrc)=0 AND position('''importer''' IN p.prosrc)=0 AND p.prosecdef
     FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.update_pdc_vehicle_sales_preparation(uuid,integer,text,boolean)')) gate_ok,
  (SELECT md5(p.prosrc)='17fd0851ec1ec248bdc686efe133f11a' FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('karratha135_pdc.update_pdc_vehicle_sales_preparation(uuid,integer,text,boolean)')) k135_kept
)
SELECT coalesce(gate_ok AND k135_kept,false) AS ok,
 'Board sales-prep ticks (Tint / Build PO / Tray) save for controllers and administrators only: '||CASE WHEN coalesce(gate_ok,false) THEN 'yes' ELSE 'NO (viewer or importer allowed, or function missing)' END
 ||'; hidden Karratha 135 copy untouched: '||CASE WHEN coalesce(k135_kept,false) THEN 'yes' ELSE 'NO' END AS detail
FROM f$chk$,true,226,'r426');

DO $p$ DECLARE r record; BEGIN
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.update_pdc_vehicle_sales_preparation(uuid,integer,text,boolean)') AND md5(p.prosrc)='21c28f7dbf99e22f0c47e0f735b732ac' AND md5(coalesce(p.proacl::text,'')||p.prosecdef::text||p.provolatile::text||p.proowner::regrole::text||coalesce(array_to_string(p.proconfig,'|'),''))='47d2ee6f05f51cc587634ba8b0604205')<>1 THEN RAISE EXCEPTION 'r426: new function body or attributes are not as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r426')<>1 THEN RAISE EXCEPTION 'r426: pin not written'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='sales_prep_ticks_role_guard') INTO r;
 IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r426: sales_prep_ticks_role_guard not ok: %', r.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO r;
 IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r426: protected_function_md5s not ok: %', r.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
