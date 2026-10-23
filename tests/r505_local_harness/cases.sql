-- r505 local auth cases (17). Expects auth function already installed as the r505 body.
WITH gmail AS (
  SELECT jsonb_build_object(
    'gmail_message_id','a505a505a505a505',
    'from_address','noreply@revolutionsoftware.com.au',
    'mailbox','pmbcontroller@gmail.com',
    'to_address','pmbcontroller@gmail.com',
    'cc_addresses','[]'::jsonb,
    'verified_by','gmail_receiving_provider',
    'header_from','revolutionsoftware.com.au',
    'reply_to','noreply@revolutionsoftware.com.au',
    'authentication_results','mx.google.com;       spf=pass (google.com: domain of noreply@revolutionsoftware.com.au designates 192.0.2.10 as permitted sender) smtp.mailfrom=noreply@revolutionsoftware.com.au;       dmarc=pass (p=QUARANTINE sp=QUARANTINE dis=NONE) header.from=revolutionsoftware.com.au'
  ) a
), outlook AS (
  SELECT jsonb_build_object(
    'internet_message_id','<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>',
    'outlook_message_id','AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE7dQAA',
    'from_address','noreply@revolutionsoftware.com.au',
    'mailbox','pdc@pmgwa.com.au',
    'to_address','pdc@pmgwa.com.au',
    'cc_addresses',jsonb_build_array('craig.watson@broometoyota.com.au'),
    'verified_by','microsoft_receiving_provider',
    'header_from','revolutionsoftware.com.au',
    'reply_to','noreply@revolutionsoftware.com.au',
    'authentication_results','mx.microsoft.com 1; spf=pass (sender IP is 13.238.252.82) smtp.mailfrom=revolutionsoftware.com.au; dkim=none (message not signed) header.d=none;dmarc=pass action=none header.from=revolutionsoftware.com.au;compauth=pass reason=100'
  ) a
), cases(name, want, a, mid) AS (
  SELECT 'gmail: To pmbcontroller', true, (SELECT a FROM gmail), 'a505a505a505a505' UNION ALL
  SELECT 'gmail: To Craig CC pmb', true, (SELECT a FROM gmail)||'{"to_address":"craig.watson@broometoyota.com.au","cc_addresses":["pmbcontroller@gmail.com"]}', 'a505a505a505a505' UNION ALL
  SELECT 'gmail: To pdc CC Craig (mailbox still pmb)', true, (SELECT a FROM gmail)||'{"to_address":"pdc@pmgwa.com.au","cc_addresses":["craig.watson@broometoyota.com.au"]}', 'a505a505a505a505' UNION ALL
  SELECT 'outlook: internet_message_id', true, (SELECT a FROM outlook), '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: outlook_message_id (Graph)', true, (SELECT a FROM outlook), 'AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE7dQAA' UNION ALL
  SELECT 'outlook: microsoft_message_id field', true,
    ((SELECT a FROM outlook)-'internet_message_id'-'outlook_message_id')||jsonb_build_object('microsoft_message_id','AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE7dQAA'),
    'AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE7dQAA' UNION ALL
  SELECT 'outlook: To pdc no Craig CC', false, (SELECT a FROM outlook)||'{"cc_addresses":[]}', '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: wrong mailbox (still gmail)', false, (SELECT a FROM outlook)||'{"mailbox":"pmbcontroller@gmail.com"}', '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: gmail verifier', false, (SELECT a FROM outlook)||'{"verified_by":"gmail_receiving_provider"}', '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: mx.google.com', false,
    (SELECT a FROM outlook)||jsonb_build_object('authentication_results', replace((SELECT a->>'authentication_results' FROM outlook),'mx.microsoft.com 1;','mx.google.com;')),
    '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: SPF fail', false,
    (SELECT a FROM outlook)||jsonb_build_object('authentication_results', replace((SELECT a->>'authentication_results' FROM outlook),'spf=pass','spf=fail')),
    '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: DMARC fail', false,
    (SELECT a FROM outlook)||jsonb_build_object('authentication_results', replace((SELECT a->>'authentication_results' FROM outlook),'dmarc=pass','dmarc=fail')),
    '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>' UNION ALL
  SELECT 'outlook: id mismatch', false, (SELECT a FROM outlook), '<other$id@host>' UNION ALL
  SELECT 'outlook: spaces in id', false, (SELECT a FROM outlook)||jsonb_build_object('internet_message_id','<a b@c>'), '<a b@c>' UNION ALL
  SELECT 'gmail: wrong mailbox=pdc', false, (SELECT a FROM gmail)||'{"mailbox":"pdc@pmgwa.com.au"}', 'a505a505a505a505' UNION ALL
  SELECT 'gmail: microsoft verifier', false, (SELECT a FROM gmail)||'{"verified_by":"microsoft_receiving_provider"}', 'a505a505a505a505' UNION ALL
  SELECT 'not an object', false, '["x"]'::jsonb, 'a505a505a505a505'
), r AS (
  SELECT name, want, pdc_codex_intake_private.revolution_parts_authenticated_20261006(a, mid) got FROM cases
)
SELECT 'passed' AS k, count(*) FILTER (WHERE got IS NOT DISTINCT FROM want), count(*) FROM r;
