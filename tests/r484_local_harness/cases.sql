-- r484 (F97) gate cases through the real (unchanged) parts import: public.pdc_import_job_parts_csv_20260912.
-- Synthetic ids only. One row with Dept 999 makes the import stop at its department rule right after the sign-in gate, so
-- 'department_138_139_scope_required' means "signed in", and nothing is ever written.
-- Prints: phase|name|code  (the run script compares the codes per phase)
WITH base AS (SELECT jsonb_build_object(
  'source_kind','revolution_automated_parts_workbook','authority','explicit_user_request',
  'user_instruction','Synthetic harness envelope for the r484 sign-in check; not a real report.',
  'mailbox','pmbcontroller@gmail.com','sender','noreply@revolutionsoftware.com.au','sender_verified',true,
  'authentication_results','mx.google.com;       spf=pass (google.com: domain of noreply@revolutionsoftware.com.au designates 192.0.2.10 as permitted sender) smtp.mailfrom=noreply@revolutionsoftware.com.au;       dmarc=pass (p=QUARANTINE sp=QUARANTINE dis=NONE) header.from=revolutionsoftware.com.au',
  'gmail_message_id','c484c484c484c484','subject','PMG PD Parts Status Complete - Pilbara','source_file','PMG PD Parts Status Complete.xls',
  'attachment_sha256',repeat('ab',32),'source_system','tune_pmg','company','01','division','1','source_format','ooxml_workbook',
  'snapshot_at',(now()-interval '10 minutes')::text,'received_at',(now()-interval '8 minutes')::text) e),
auth AS (SELECT jsonb_build_object('gmail_message_id','c484c484c484c484','from_address','noreply@revolutionsoftware.com.au','mailbox','pmbcontroller@gmail.com',
  'to_address','pdc@pmgwa.com.au','cc_addresses',jsonb_build_array('craig.watson@broometoyota.com.au'),'verified_by','gmail_receiving_provider',
  'header_from','revolutionsoftware.com.au','reply_to','noreply@revolutionsoftware.com.au','authentication_results',(SELECT e->>'authentication_results' FROM base)) a),
env AS (SELECT (SELECT e FROM base)||jsonb_build_object('authentication',(SELECT a FROM auth)) e),
cases(name, e) AS (
  SELECT 'new To pdc + CC Craig', (SELECT e FROM env) UNION ALL
  SELECT 'old To pmbcontroller', jsonb_set((SELECT e FROM env),'{authentication}',(SELECT a FROM auth)||'{"to_address":"pmbcontroller@gmail.com","cc_addresses":[]}') UNION ALL
  SELECT 'old To Craig + CC pmbcontroller', jsonb_set((SELECT e FROM env),'{authentication}',(SELECT a FROM auth)||'{"to_address":"craig.watson@broometoyota.com.au","cc_addresses":["pmbcontroller@gmail.com"]}') UNION ALL
  SELECT 'To pdc without CC', jsonb_set((SELECT e FROM env),'{authentication}',(SELECT a FROM auth)-'cc_addresses') UNION ALL
  SELECT 'To pdc + CC someone else', jsonb_set((SELECT e FROM env),'{authentication}',(SELECT a FROM auth)||'{"cc_addresses":["parts@pmgwa.com.au"]}') UNION ALL
  SELECT 'To other domain + CC Craig', jsonb_set((SELECT e FROM env),'{authentication}',(SELECT a FROM auth)||'{"to_address":"pdc@example.com.au"}') UNION ALL
  SELECT 'wrong sender (auth)', jsonb_set((SELECT e FROM env),'{authentication}',(SELECT a FROM auth)||'{"from_address":"someone@revolutionsoftware.com.au"}') UNION ALL
  SELECT 'wrong sender (envelope)', (SELECT e FROM env)||'{"sender":"someone@revolutionsoftware.com.au"}' UNION ALL
  SELECT 'SPF fail', (SELECT e FROM env)||jsonb_build_object('authentication_results',replace((SELECT e->>'authentication_results' FROM base),'spf=pass','spf=fail'),
     'authentication',(SELECT a FROM auth)||jsonb_build_object('authentication_results',replace((SELECT e->>'authentication_results' FROM base),'spf=pass','spf=fail'))) UNION ALL
  SELECT 'DMARC fail', (SELECT e FROM env)||jsonb_build_object('authentication_results',replace((SELECT e->>'authentication_results' FROM base),'dmarc=pass','dmarc=fail'),
     'authentication',(SELECT a FROM auth)||jsonb_build_object('authentication_results',replace((SELECT e->>'authentication_results' FROM base),'dmarc=pass','dmarc=fail'))) UNION ALL
  SELECT 'auth results differ', (SELECT e FROM env)||'{"authentication_results":"mx.google.com; spf=pass"}' UNION ALL
  SELECT 'sha256 short', (SELECT e FROM env)||jsonb_build_object('attachment_sha256',repeat('ab',31)||'a') UNION ALL
  SELECT 'sha256 not hex', (SELECT e FROM env)||jsonb_build_object('attachment_sha256',repeat('zz',32)) UNION ALL
  SELECT 'sha256 missing', (SELECT e FROM env)-'attachment_sha256' UNION ALL
  SELECT 'message id mismatch', (SELECT e FROM env)||'{"gmail_message_id":"d484d484d484d484"}'
)
SELECT :'phase'||'|'||name||'|'||(public.pdc_import_job_parts_csv_20260912(e,'[{"Dept":"999"}]'::jsonb)->>'code') FROM cases;
