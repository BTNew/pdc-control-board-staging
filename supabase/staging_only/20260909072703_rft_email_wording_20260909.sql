-- STAGING only. Preserve saved drafts and immutable evidence; correct new email
-- wording and the downloadable presentation of already-created unsent drafts.
DO $migration$
DECLARE d text; patched text;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
    OR current_setting('app.environment',true)='production' THEN
  RAISE EXCEPTION 'STAGING required';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:rft-email-wording:20260909',0));
 SELECT pg_get_functiondef('public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)'::regprocedure) INTO d;
 IF md5(d)<>'a357acaf7bd20f3fc7c3adc0f6fe6be2' THEN RAISE EXCEPTION 'Draft writer changed since review'; END IF;
 patched:=replace(d,'The QC completion photo is attached. Please arrange transport.','The QC completion photo is attached.');
 IF patched=d THEN RAISE EXCEPTION 'Draft wording not found'; END IF;
 EXECUTE patched;

 SELECT pg_get_functiondef('public.read_rft_transport_draft_739(uuid)'::regprocedure) INTO d;
 IF md5(d)<>'fac53b98af3dc592107d79a56e2f99b5' THEN RAISE EXCEPTION 'Draft reader changed since review'; END IF;
 patched:=replace(d,'d public.pdc_rft_transport_email_drafts_739%rowtype;',
  'd public.pdc_rft_transport_email_drafts_739%rowtype; rendered bytea; body_text text; old_encoded text; new_encoded text; mime_text text; crlf text:=chr(13)||chr(10);');
 patched:=replace(patched,
  '  RETURN jsonb_build_object(''ok'',true,''code'',''rft_transport_draft'',''data'',jsonb_build_object(',
 $render$
  -- Validate source bytes before deriving a revised unsent presentation. Stored
  -- evidence is never rewritten, and the attachment part is left byte-identical.
  IF d.mime_byte_length<>octet_length(d.mime_bytes)
     OR d.mime_sha256<>encode(extensions.digest(d.mime_bytes,'sha256'),'hex') THEN
    RETURN jsonb_build_object('ok',false,'code','rft_draft_integrity_failed');
  END IF;
  rendered:=d.mime_bytes;
  body_text:=d.response#>>'{data,text_body}';
  IF position(' Please arrange transport.' IN coalesce(body_text,''))>0
     OR position(' Please book for transport.' IN coalesce(body_text,''))>0 THEN
    old_encoded:=replace(encode(convert_to(body_text,'UTF8'),'base64'),chr(10),crlf);
    body_text:=replace(replace(body_text,' Please arrange transport.',''),' Please book for transport.','');
    new_encoded:=replace(encode(convert_to(body_text,'UTF8'),'base64'),chr(10),crlf);
    mime_text:=convert_from(d.mime_bytes,'UTF8');
    IF position(crlf||crlf||old_encoded||crlf IN mime_text)=0 THEN
      RETURN jsonb_build_object('ok',false,'code','rft_draft_body_encoding_unrecognized');
    END IF;
    rendered:=convert_to(replace(mime_text,crlf||crlf||old_encoded||crlf,crlf||crlf||new_encoded||crlf),'UTF8');
  END IF;
  RETURN jsonb_build_object('ok',true,'code','rft_transport_draft','data',jsonb_build_object(
$render$);
 patched:=replace(patched,'''text_body'',d.response#>>''{data,text_body}''','''text_body'',body_text');
 patched:=replace(patched,
  '''mime_byte_length'',d.mime_byte_length,''mime_sha256'',d.mime_sha256,''mime_base64'',encode(d.mime_bytes,''base64'')',
  '''mime_byte_length'',octet_length(rendered),''mime_sha256'',encode(extensions.digest(rendered,''sha256''),''hex''),''mime_base64'',encode(rendered,''base64''),''source_mime_sha256'',d.mime_sha256,''presentation_version'',''20260909-pmb-transport''');
 IF patched=d OR position('rendered:=d.mime_bytes' IN patched)=0 OR position('octet_length(rendered)' IN patched)=0 THEN RAISE EXCEPTION 'Draft presentation repair mismatch'; END IF;
 EXECUTE patched;
END $migration$;
