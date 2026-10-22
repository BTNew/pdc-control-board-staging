CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_auth jsonb, p_message_id text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT coalesce(jsonb_typeof(p_auth)='object'
  AND p_message_id ~ '^[a-f0-9]{10,40}$' AND p_auth->>'gmail_message_id'=p_message_id
  AND p_auth->>'from_address'='noreply@revolutionsoftware.com.au'
  AND p_auth->>'mailbox'='pmbcontroller@gmail.com' AND (p_auth->>'to_address'='pmbcontroller@gmail.com' OR (p_auth->>'to_address'='craig.watson@broometoyota.com.au' AND p_auth->'cc_addresses' @> '["pmbcontroller@gmail.com"]'::jsonb))
  AND p_auth->>'verified_by'='gmail_receiving_provider' AND p_auth->>'header_from'='revolutionsoftware.com.au'
  AND coalesce(nullif(p_auth->>'reply_to',''),'noreply@revolutionsoftware.com.au')='noreply@revolutionsoftware.com.au'
  AND p_auth->>'authentication_results' ~* '^mx[.]google[.]com;'
  AND p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*spf=pass[^;]*smtp[.]mailfrom=noreply@revolutionsoftware[.]com[.]au([;[:space:]]|$)'
  AND p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from=revolutionsoftware[.]com[.]au([;[:space:]]|$)',false);
$function$
