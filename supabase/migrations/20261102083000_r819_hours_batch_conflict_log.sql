-- r819 (F458): log what a refused hours save sent and why (applied 2 Nov 08:30 to find the 13109751 cause).
CREATE TABLE IF NOT EXISTS pdc_ops.hours_batch_conflicts_819 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor uuid, vehicle_id uuid, code text, request jsonb, detail jsonb);
REVOKE ALL ON pdc_ops.hours_batch_conflicts_819 FROM PUBLIC, anon, authenticated;
DO $r819$
DECLARE sig regprocedure := 'public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure;
  v_old text; v_new text; v_def text;
  a1 text := $a$  IF jsonb_array_length(v_conflicts)>0 THEN
    RETURN$a$;
  b1 text := $b$  IF jsonb_array_length(v_conflicts)>0 THEN
    -- r819 (F458): keep what was sent and why it conflicted, to find the cause.
    INSERT INTO pdc_ops.hours_batch_conflicts_819(actor,vehicle_id,code,request,detail)
    VALUES (v_actor,p_vehicle_id,'line_version_conflict',jsonb_build_object('rows',v_rows,'job_card',p_job_card_number,'vehicle_version',p_expected_vehicle_version),jsonb_build_object('conflicts',v_conflicts,'current_rows',v_current_rows));
    RETURN$b$;
  a2 text := $a$  IF v_vehicle.version<>p_expected_vehicle_version THEN
    RETURN$a$;
  b2 text := $b$  IF v_vehicle.version<>p_expected_vehicle_version THEN
    INSERT INTO pdc_ops.hours_batch_conflicts_819(actor,vehicle_id,code,request,detail)
    VALUES (v_actor,p_vehicle_id,'vehicle_version_conflict',jsonb_build_object('rows',v_rows,'job_card',p_job_card_number,'vehicle_version',p_expected_vehicle_version),jsonb_build_object('current_vehicle_version',v_vehicle.version));
    RETURN$b$;
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r819: anchor 1 not found once'; END IF;
  IF (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 1 THEN RAISE EXCEPTION 'r819: anchor 2 not found once'; END IF;
  v_new := replace(replace(v_old, a1, b1), a2, b2);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r819: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);
END $r819$;
