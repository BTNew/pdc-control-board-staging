-- Each approved Sublet operation owns an independent provider booking.
ALTER TABLE public.pdc_sublet_booking_instances
 ADD COLUMN operation_line_identity text,
 ADD COLUMN operation_description text;
ALTER TABLE public.pdc_sublet_booking_instances ADD CONSTRAINT sublet_operation_identity_format
 CHECK (operation_line_identity IS NULL OR operation_line_identity ~ '^(source|manual):[0-9a-f-]{36}$');
CREATE UNIQUE INDEX sublet_one_booking_per_operation
 ON public.pdc_sublet_booking_instances(vehicle_id,operation_line_identity)
 WHERE operation_line_identity IS NOT NULL AND status <> 'cancelled';

DO $migration$
DECLARE original text; revised text; name text;
BEGIN
 original:=pg_get_functiondef('public.create_pdc_sublet_booking(uuid,bigint,uuid,date,date,text,text)'::regprocedure);
 revised:=replace(original,'public.create_pdc_sublet_booking(', 'public.create_pdc_sublet_operation_booking(');
 revised:=replace(revised,'p_notes text DEFAULT ''''::text)', 'p_notes text DEFAULT ''''::text, p_operation_line_identity text DEFAULT NULL)');
 revised:=replace(revised,'v_revision bigint;', 'v_revision bigint; v_operation jsonb;');
 revised:=replace(revised,'  select * into v_vehicle', $sql$
  perform public.pdc_lock_canonical_sublet_vehicle(p_vehicle_id);
  select * into v_vehicle$sql$);
 revised:=replace(revised,'  select * into v_provider', $sql$
  select l into v_operation
  from jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
  where l->>'line_identity'=p_operation_line_identity and l->>'stage_code'='SUBLET'
    and (l->>'active')::boolean is true and (l->>'completed')::boolean is not true;
  if v_operation is null then return public.navision_backend_response(false,'sublet_operation_not_available'); end if;
  if exists(select 1 from public.pdc_new_vehicle_reviews where vehicle_id=p_vehicle_id and status<>'approved') then
    return public.navision_backend_response(false,'vehicle_review_not_approved');
  end if;
  if exists(select 1 from public.pdc_sublet_booking_instances where vehicle_id=p_vehicle_id
    and operation_line_identity=p_operation_line_identity and status<>'cancelled') then
    return public.navision_backend_response(false,'sublet_operation_already_booked');
  end if;
  select * into v_provider$sql$);
 revised:=replace(revised,'notes,created_by,updated_by)', 'notes,created_by,updated_by,operation_line_identity,operation_description)');
 revised:=replace(revised,'v_user,v_user) returning', 'v_user,v_user,p_operation_line_identity,v_operation->>''description'') returning');
 IF revised=original OR position('p_operation_line_identity text DEFAULT NULL' in revised)=0
  OR position('v_operation->>''description'') returning' in revised)=0 THEN RAISE EXCEPTION 'create_booking_contract_changed'; END IF;
 EXECUTE revised;

 -- Keep all snapshot producers consistent, including the existing special vehicle projection.
 FOREACH name IN ARRAY ARRAY['get_pdc_email_vehicle_location_snapshot_pre_169','get_pdc_email_vehicle_location_snapshot_pre_693','get_pdc_email_vehicle_location_snapshot_pre_734'] LOOP
  original:=pg_get_functiondef((('public.'||name||'()')::regprocedure));
  revised:=replace(original,'''notes'',b.notes', '''notes'',b.notes,''operation_line_identity'',b.operation_line_identity,''operation_description'',b.operation_description');
  IF revised=original THEN RAISE EXCEPTION 'snapshot_contract_changed: %',name; END IF;
  EXECUTE revised;
 END LOOP;

 original:=pg_get_functiondef('public.return_pdc_sublet_booking(uuid,bigint,timestamp with time zone)'::regprocedure);
 revised:=replace(original,'v_active_count integer:=0;', 'v_active_count integer:=0; v_pending_count integer:=0;');
 revised:=replace(revised,'  if v_active_count=0 then', $sql$
  -- Returning a trip must not finish other requirements still waiting to be booked.
  if exists(select 1 from public.pdc_sublet_booking_instances where vehicle_id=v_vehicle_id and operation_line_identity is not null) then
    select count(*) into v_pending_count
    from jsonb_array_elements(public.pdc_qc_operation_lines_379(v_vehicle_id)) l
    where l->>'stage_code'='SUBLET' and (l->>'active')::boolean is true
      and (l->>'completed')::boolean is not true
      and not exists(select 1 from public.pdc_sublet_booking_instances b
        where b.vehicle_id=v_vehicle_id and b.operation_line_identity=l->>'line_identity' and b.status='returned');
  end if;
  if v_active_count=0 and v_pending_count=0 then$sql$);
 revised:=replace(revised,'''sublet_station_completed'',v_active_count=0 and v_required_count>0', '''remaining_sublet_requirements'',v_pending_count,''sublet_station_completed'',v_active_count=0 and v_pending_count=0 and v_required_count>0');
 IF revised=original OR position('if v_active_count=0 and v_pending_count=0 then' in revised)=0 THEN RAISE EXCEPTION 'return_booking_contract_changed'; END IF;
 EXECUTE revised;
END $migration$;
REVOKE ALL ON FUNCTION public.create_pdc_sublet_operation_booking(uuid,bigint,uuid,date,date,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_pdc_sublet_operation_booking(uuid,bigint,uuid,date,date,text,text,text) TO authenticated;
