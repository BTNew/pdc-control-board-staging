-- Staging-only administrator review of an exact full Navision profile export.
DO $guard$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF; END $guard$;
CREATE TABLE pdc_navision_upload_private.complete_snapshot_reviews (
 actor_id uuid NOT NULL, profile text NOT NULL CHECK(profile IN('broome','pilbara')),
 dealer_code text NOT NULL, source_system text NOT NULL CHECK(source_system='microsoft_navision'),
 source_name text NOT NULL, rows_hash text NOT NULL, scope_hash text NOT NULL,
 preview_hash text NOT NULL, base_revision bigint NOT NULL, reviewed_email text NOT NULL,
 reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp(), expires_at timestamptz NOT NULL,
 PRIMARY KEY(actor_id,profile,dealer_code)
);
ALTER TABLE pdc_navision_upload_private.complete_snapshot_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_navision_upload_private.complete_snapshot_reviews FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION pdc_navision_upload_private.current_scope_hash(p_dealer_code text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path='pg_catalog' AS $fn$
 SELECT encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(n) ORDER BY n.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
 FROM public.navision_backend_records n
 WHERE n.source_system='microsoft_navision' AND n.dealer_code=p_dealer_code
   AND n.is_current AND n.record_status='current'
$fn$;
REVOKE ALL ON FUNCTION pdc_navision_upload_private.current_scope_hash(text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.navision_import_safety_assessment(p_rows jsonb, p_source_system text, p_dealer_code text, p_source_name text, p_preview_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_result jsonb;
  v_reason text;
  v_selected text:=public.navision_canonical_dealer_code(p_dealer_code);
  v_incoming integer:=0;
  v_valid_rows integer:=0;
  v_declared_selected integer:=0;
begin
  v_result:=public.navision_import_safety_assessment_pre079(p_rows,p_source_system,p_dealer_code,p_source_name,p_preview_data);
  v_reason:=coalesce(v_result->>'reason','');
  v_incoming:=coalesce((v_result->>'incoming_valid_count')::integer,0);

  if v_reason='cross_dealer_identity_overlap'
     and lower(btrim(coalesce(p_source_system,'')))='microsoft_navision'
     and v_selected in ('14450','37047','002345','001234')
     and v_incoming>0
     and jsonb_typeof(p_rows)='array' then
    with valid_rows as materialized(
      select public.navision_row_declared_dealer_code(e.value) declared_dealer
      from jsonb_array_elements(p_rows)e(value)
      where jsonb_typeof(e.value)='object'
        and not public.navision_backend_row_has_forbidden_fields(e.value)
        and public.navision_backend_source_record_id(e.value) is not null
    )
    select count(*)::integer,count(*) filter(where declared_dealer=v_selected)::integer
      into v_valid_rows,v_declared_selected from valid_rows;

    if v_valid_rows=v_incoming and v_declared_selected=v_incoming then
      v_result:=jsonb_set(v_result,'{blocking}','false'::jsonb,true);
      v_result:=jsonb_set(v_result,'{reason}','null'::jsonb,true);
      v_result:=jsonb_set(v_result,'{authority}',to_jsonb('navision_original_dealer_column_v2'::text),true);
      v_result:=jsonb_set(v_result,'{declared_dealer_release}',jsonb_build_object(
        'released',true,'selected_dealer_code',v_selected,'valid_rows',v_valid_rows,
        'declared_selected_rows',v_declared_selected,'minimum_incoming',1,'hard_delete',false
      ),true);
    end if;
  end if;

  -- Only a separately reviewed, exact profile snapshot can release a large
  -- omission. Identity/row errors and every other safety reason stay blocking.
  if v_reason='suspicious_partial_snapshot'
     and coalesce((p_preview_data#>>'{counts,invalid}')::integer,0)=0
     and coalesce((p_preview_data#>>'{counts,conflict}')::integer,0)=0
     and v_incoming>0
     and exists (
       select 1 from pdc_navision_upload_private.complete_snapshot_reviews a
       where a.actor_id=auth.uid()
         and a.dealer_code=v_selected
         and a.source_system=lower(btrim(coalesce(p_source_system,'')))
         and a.source_name=p_source_name
         and a.rows_hash=encode(extensions.digest(convert_to(p_rows::text,'UTF8'),'sha256'),'hex')
         and a.scope_hash=pdc_navision_upload_private.current_scope_hash(v_selected)
         and a.expires_at>clock_timestamp()
         and exists(select 1 from public.pdc_user_roles u
           where u.auth_user_id=auth.uid() and u.email=lower(coalesce(auth.jwt()->>'email',''))
           and u.active and u.account_status='approved' and u.role='administrator')
     ) then
    v_result:=v_result||jsonb_build_object('blocking',false,'reason',null,
      'authority','navision_complete_snapshot_exact_review_v1',
      'complete_snapshot_review',jsonb_build_object('approved',true,'content_bound',true,
        'scope_bound',true,'user_bound',true,'expires',true,'hard_delete',false));
  end if;

  return v_result;
end
$function$
;

CREATE FUNCTION pdc_navision_upload_private.review_complete_snapshot(
 p_profile text,p_rows jsonb,p_source_name text,p_source_timestamp timestamptz,
 p_source_hash text,p_preview_hash text,p_expected_revision bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','public','extensions' SET statement_timeout='60s' AS $fn$
DECLARE p jsonb; split jsonb; g record; rows jsonb; reviewed jsonb:='[]'; r jsonb; reason text; rev bigint;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles u WHERE u.auth_user_id=auth.uid()
    AND u.email=lower(coalesce(auth.jwt()->>'email','')) AND u.active AND u.account_status='approved' AND u.role='administrator')
 THEN RETURN public.navision_backend_response(false,'administrator_required'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 SELECT revision INTO rev FROM public.navision_backend_revision WHERE singleton FOR UPDATE;
 IF rev IS DISTINCT FROM p_expected_revision THEN RETURN public.navision_backend_response(false,'stale_revision'); END IF;
 p:=pdc_navision_upload_private.preview_profile(p_profile,p_rows,p_source_name,p_source_timestamp);
 IF p->>'ok' IS DISTINCT FROM 'true' THEN RETURN p; END IF;
 IF p_source_hash IS DISTINCT FROM p#>>'{data,source_hash}' THEN RETURN public.navision_backend_response(false,'source_changed'); END IF;
 IF p_preview_hash IS DISTINCT FROM p#>>'{data,preview_hash}' THEN RETURN public.navision_backend_response(false,'preview_changed'); END IF;
 IF coalesce((p#>>'{data,counts,invalid}')::int,0)>0 OR coalesce((p#>>'{data,counts,conflict}')::int,0)>0
 THEN RETURN public.navision_backend_response(false,'rows_need_attention'); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p#>'{data,dealer_groups}') x
   WHERE x->>'blocking'='true' AND coalesce(x#>>'{safety,reason}','') NOT IN('suspicious_partial_snapshot','unproven_empty_dealer_scope'))
 THEN RETURN public.navision_backend_response(false,'snapshot_not_reviewable'); END IF;
 split:=pdc_navision_upload_private.split_profile(p_rows,p_profile);
 FOR g IN SELECT key,value FROM jsonb_each(split->'groups') ORDER BY key LOOP
  SELECT jsonb_agg(e->'row' ORDER BY (e->>'index')::int) INTO rows FROM jsonb_array_elements(g.value) e;
  SELECT x#>>'{safety,reason}' INTO reason FROM jsonb_array_elements(p#>'{data,dealer_groups}') x WHERE x->>'dealer_code'=g.key;
  IF reason='unproven_empty_dealer_scope' THEN
   r:=public.approve_navision_initial_scope(rows,'microsoft_navision',g.key);
   IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Initial dealer review failed: %',r->>'code'; END IF;
   reviewed:=reviewed||jsonb_build_array(g.key);
  ELSIF reason='suspicious_partial_snapshot' THEN
   -- Zero-row exports are never approved. split_profile/preview already validate
   -- the original dealer columns, stable Toyota Order identity and duplicates.
   IF jsonb_array_length(rows)=0 THEN RAISE EXCEPTION 'Empty snapshot'; END IF;
   INSERT INTO pdc_navision_upload_private.complete_snapshot_reviews(
    actor_id,profile,dealer_code,source_system,source_name,rows_hash,scope_hash,
    preview_hash,base_revision,reviewed_email,expires_at)
   VALUES(auth.uid(),p_profile,g.key,'microsoft_navision',p_profile||' Navision dealer '||g.key,
    encode(extensions.digest(convert_to(rows::text,'UTF8'),'sha256'),'hex'),
    pdc_navision_upload_private.current_scope_hash(g.key),p_preview_hash,rev,
    lower(auth.jwt()->>'email'),clock_timestamp()+interval '2 hours')
   ON CONFLICT(actor_id,profile,dealer_code) DO UPDATE SET
    source_name=excluded.source_name,rows_hash=excluded.rows_hash,scope_hash=excluded.scope_hash,
    preview_hash=excluded.preview_hash,base_revision=excluded.base_revision,
    reviewed_email=excluded.reviewed_email,reviewed_at=clock_timestamp(),expires_at=excluded.expires_at;
   reviewed:=reviewed||jsonb_build_array(g.key);
  END IF;
 END LOOP;
 RETURN public.navision_backend_response(true,'complete_snapshot_reviewed',
   jsonb_build_object('dealers',reviewed,'expires_at',clock_timestamp()+interval '2 hours','imported',false));
END $fn$;
REVOKE ALL ON FUNCTION pdc_navision_upload_private.review_complete_snapshot(text,jsonb,text,timestamptz,text,text,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION pdc_navision_upload_private.review_complete_snapshot(text,jsonb,text,timestamptz,text,text,bigint) TO authenticated;
CREATE FUNCTION public.review_navision_complete_snapshot(
 p_profile text,p_rows jsonb,p_source_name text,p_source_timestamp timestamptz,
 p_source_hash text,p_preview_hash text,p_expected_revision bigint)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog' AS $fn$
 SELECT pdc_navision_upload_private.review_complete_snapshot(p_profile,p_rows,p_source_name,p_source_timestamp,p_source_hash,p_preview_hash,p_expected_revision)
$fn$;
REVOKE ALL ON FUNCTION public.review_navision_complete_snapshot(text,jsonb,text,timestamptz,text,text,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.review_navision_complete_snapshot(text,jsonb,text,timestamptz,text,text,bigint) TO authenticated;
