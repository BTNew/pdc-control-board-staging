-- r744 rollback: the board reader stops carrying import_progress; the progress function and check go. Staging cdsmnqxtyyoeoznmbidd only.
DO $down744$
DECLARE v_old text; v_new text; v_def text;
  a1 text := $a$, 'import_progress', public.pdc_import_progress_744());$a$;
  b1 text := ');';
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)'::regprocedure;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 3 THEN RAISE EXCEPTION 'r744 down: anchors not found three times'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef('public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)'::regprocedure)) <> '5347811a3b138b67126da2fb023578bf' THEN RAISE EXCEPTION 'r744 down: body is not the pre-r744 body'; END IF;
END $down744$;
DROP FUNCTION public.pdc_import_progress_744();
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'import_progress_on_the_board_744';
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261030093000';
