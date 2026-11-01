-- r804 (F419): Craig 1 Nov 2026 18:33 AWST: "if a parts ETA is in the future, automatically untick parts complete and make the box red."
-- The vehicle's parts ETA (typed date first, else the latest email ETA) after today (Perth) makes the parts flags red,
-- "Parts outstanding — ETA dd/mm/yy", over the import colour and over a Parts complete tick or confirmation email made before
-- that ETA was set. A Parts complete tick (or email) made after the ETA was set still wins: the parts came early.
-- On and after the ETA day the colour goes back to the import / ticks as before. Saving an ETA now refreshes the board snapshot.
DO $r804$
DECLARE
  sig regprocedure := 'public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure;
  v_old text; v_new text; v_def text;
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 584 OR fault_id = 'F419' OR added_in = 'r804') THEN RAISE EXCEPTION 'r804: sort 584 or F419 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r804: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF strpos(v_old, 'pdc_parts_board_outstanding_803') = 0 OR strpos(v_old, 'parts_eta_future') > 0 THEN RAISE EXCEPTION 'r804: parts flags is not the r803 body'; END IF;
  v_new := $body$
DECLARE imported jsonb; c public.pdc_parts_completion_email_confirmations%rowtype; b public.pdc_parts_board_complete_747%rowtype; mark jsonb;
 v_today date := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date; v_eta date; v_eta_at timestamptz; v_eta_src text; v_future boolean;
BEGIN
 imported:=public.pdc_imported_parts_flags_vehicle_20260912(p_vehicle_id);
 -- r804 (F419): the parts ETA the board shows (typed date first, else the latest email ETA).
 SELECT s.eta_date, s.set_at, 'typed' INTO v_eta, v_eta_at, v_eta_src FROM public.pdc_parts_stoppage_564 s
 WHERE s.vehicle_id=p_vehicle_id AND s.active AND s.eta_date IS NOT NULL;
 IF v_eta IS NULL THEN
 SELECT e.eta_date, coalesce(e.message_at, e.set_at), 'email' INTO v_eta, v_eta_at, v_eta_src FROM public.pdc_parts_eta e
 WHERE e.vehicle_id=p_vehicle_id AND NOT coalesce(e.superseded,false) AND e.eta_date IS NOT NULL ORDER BY e.eta_date DESC, e.set_at DESC LIMIT 1;
 END IF;
 v_future := v_eta IS NOT NULL AND v_eta > v_today;
 SELECT * INTO c FROM public.pdc_parts_completion_email_confirmations WHERE vehicle_id=p_vehicle_id AND active;
 IF FOUND AND (NOT v_future OR c.received_at > v_eta_at) THEN
 mark:=jsonb_build_object('colour','green','label','Parts complete — person confirmed','parts_complete',true,
 'override_source','authorised_email_confirmation','person_confirmed',true,'confirmation_id',c.confirmation_id,
 'confirmed_at',c.received_at,'confirmed_by',c.sender,'confirmed_by_name',coalesce(nullif(c.authentication->>'display_name',''),c.sender),
 'meaning','A person confirmed the parts are here. This confirmation takes priority over import backorder flags; original import evidence is retained.');
 ELSE
 SELECT * INTO b FROM public.pdc_parts_board_complete_747 WHERE vehicle_id=p_vehicle_id AND active;
 IF FOUND AND (NOT v_future OR b.set_at > v_eta_at) THEN
 -- r747 (F353): the side-panel Parts complete tick.
 mark:=jsonb_build_object('colour','green','label','Parts complete — marked on the board','parts_complete',true,
 'override_source','board_parts_complete','person_confirmed',true,
 'confirmed_at',b.set_at,'confirmed_by',b.set_by_actor,'confirmed_by_name',b.set_by_actor,
 'meaning','Parts complete was ticked on the board. This takes priority over import backorder flags; original import evidence is retained.');
 ELSIF v_future THEN
 -- r804 (F419): a parts ETA in the future: parts outstanding, red.
 mark:=jsonb_build_object('colour','red','label','Parts outstanding — ETA '||to_char(v_eta,'DD/MM/YY'),'parts_complete',false,
 'override_source','parts_eta_future','eta_date',v_eta,'eta_source',v_eta_src,'confirmed_at',v_eta_at,
 'job_label','Parts ETA '||to_char(v_eta,'DD/MM/YY'),
 'meaning','A parts ETA is in the future, so the parts are outstanding. Tick Parts complete if they arrive early; original import evidence is retained.');
 ELSE
 -- r803 (F418): Parts complete unticked over a green import: parts outstanding, red.
 SELECT o.set_at, o.set_by_actor INTO b.set_at, b.set_by_actor FROM public.pdc_parts_board_outstanding_803 o WHERE o.vehicle_id=p_vehicle_id AND o.active;
 IF NOT FOUND THEN RETURN imported; END IF;
 mark:=jsonb_build_object('colour','red','label','Parts outstanding — marked on the board','parts_complete',false,
 'override_source','board_parts_outstanding','person_confirmed',true,
 'confirmed_at',b.set_at,'confirmed_by',b.set_by_actor,'confirmed_by_name',b.set_by_actor,'job_label','Parts marked outstanding on the board',
 'meaning','Parts complete was unticked on the board. Parts are outstanding until it is ticked again; original import evidence is retained.');
 END IF;
 END IF;
 RETURN coalesce(imported,'{}')||mark||jsonb_build_object('import_status',imported,
 'jobs',(SELECT coalesce(jsonb_agg(j||mark||jsonb_build_object('import_status',j)),'[]') FROM jsonb_array_elements(coalesce(imported->'jobs','[]')) j),
 'operations',(SELECT coalesce(jsonb_object_agg(key,value||mark||jsonb_build_object('import_status',value,'job_label',coalesce(mark->>'job_label','A person confirmed parts complete for this vehicle'))),'{}') FROM jsonb_each(coalesce(imported->'operations','{}'))));
END $body$;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r804: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);
END $r804$;

-- Saving a typed ETA, or an email ETA arriving, refreshes the Vehicle Locations snapshot so the box colour follows.
CREATE OR REPLACE FUNCTION public.pdc_parts_eta_revision_804() RETURNS trigger LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'public' AS $f$
BEGIN
  UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE singleton;
  RETURN NULL;
END $f$;
REVOKE ALL ON FUNCTION public.pdc_parts_eta_revision_804() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER pdc_parts_eta_revision_804 AFTER INSERT OR UPDATE OR DELETE ON public.pdc_parts_stoppage_564
  FOR EACH STATEMENT EXECUTE FUNCTION public.pdc_parts_eta_revision_804();
CREATE TRIGGER pdc_parts_eta_revision_804 AFTER INSERT OR UPDATE OR DELETE ON public.pdc_parts_eta
  FOR EACH STATEMENT EXECUTE FUNCTION public.pdc_parts_eta_revision_804();
UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE singleton;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('future_eta_parts_red_804', 'F419',
  'Parts (r804): a parts ETA after today makes the parts box red over the import and over a tick made before the ETA; saving an ETA refreshes the board.',
  $chk$
SELECT strpos(f.src, 'parts_eta_future') > 0 AND strpos(f.src, 'pdc_parts_stoppage_564') > 0 AND strpos(f.src, 'b.set_at > v_eta_at') > 0
   AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'pdc_parts_eta_revision_804' AND tgrelid = 'public.pdc_parts_stoppage_564'::regclass)
   AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'pdc_parts_eta_revision_804' AND tgrelid = 'public.pdc_parts_eta'::regclass) AS ok,
 'future parts ETA reads red' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('public.pdc_parts_flags_vehicle_20260911(uuid)')) f
$chk$, true, 584, 'r804');
