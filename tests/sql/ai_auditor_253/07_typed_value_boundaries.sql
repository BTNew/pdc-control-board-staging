-- Direct signed-RPC probes: PostgreSQL must reject every value Python rejects.
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","email":"auditor@example.test","role":"authenticated"}',false);

create function pg_temp.envelope7(p_instruction text,p_scope jsonb,p_delivery uuid,p_nonce text) returns jsonb
language plpgsql as $$declare issued text;expires text;evidence jsonb;env jsonb;digest text;begin
 issued:=to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
 expires:=to_char((clock_timestamp()+interval '2 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
 digest:=encode(extensions.digest(convert_to(p_instruction,'UTF8'),'sha256'),'hex');
 evidence:=jsonb_build_object('bot_identity','pdc-auditor-staging','instruction_sha256',digest,'original_instruction',p_instruction,'telegram_chat_id',7828138290,'telegram_message_id',abs(hashtextextended(p_delivery::text,0))%2147483646+1,'telegram_sender_id',7828138290,'telegram_update_id',abs(hashtextextended(p_delivery::text,1))%2147483647);
 env:=jsonb_build_object('gateway_instance_id','fixture-gateway','delivery_uuid',p_delivery,'key_id','fixture-key','nonce',p_nonce,'issued_at',issued,'expires_at',expires,'instruction_sha256',digest,'selected_scope',p_scope,'telegram_evidence',evidence,'signature',repeat('0',64));
 return jsonb_set(env,'{signature}',to_jsonb(encode(extensions.hmac(public.pdc_auditor_signing_bytes_253(env),decode(repeat('42',32),'hex'),'sha256'),'hex')));
end$$;

do $$
declare value jsonb;
begin
 foreach value in array array[
  '{"description":123,"estimated_hours":1.5,"operation_code":"OK","work_key":"hoist"}'::jsonb,
  '{"description":"ok","estimated_hours":1.5,"operation_code":"BAD CODE!","work_key":"hoist"}'::jsonb,
  '{"description":"ok","estimated_hours":1.5,"operation_code":"OK","ordered_position":1.25,"work_key":"hoist"}'::jsonb,
  '{"description":"ok","estimated_hours":1.5,"operation_code":"OK","ordered_position":10001,"work_key":"hoist"}'::jsonb
 ] loop
  if public.pdc_auditor_valid_new_value_253(value,true,true,false) then raise exception 'invalid complete value accepted: %',value;end if;
 end loop;
 if not public.pdc_auditor_valid_new_value_253('{"description":"ok","estimated_hours":1.5,"operation_code":"OK","ordered_position":1e0,"work_key":"hoist"}'::jsonb,true,true,false) then raise exception 'canonical integral exponent value rejected';end if;
 if public.pdc_auditor_valid_new_value_253('{"description":"ok","estimated_hours":1.5,"operation_code":"OK","ordered_position":1.25,"work_key":"hoist"}'::jsonb,true,true,false) then raise exception 'fractional ordered position accepted';end if;
 if not public.pdc_auditor_valid_new_value_253('{"description":"ok","estimated_hours":1.5,"operation_code":"OK-1/a.b","ordered_position":10000,"work_key":"hoist"}'::jsonb,true,true,false) then raise exception 'valid complete value rejected';end if;
 if public.pdc_auditor_valid_new_value_253('{"description":"ok","estimated_hours":1,"work_key":"hoist"}'::jsonb,true,false,true) then raise exception 'required operation code omitted';end if;
 if public.pdc_auditor_valid_new_value_253('{"description":"ok","estimated_hours":1,"operation_code":"OK","ordered_position":2,"work_key":"hoist"}'::jsonb,true,false,true) then raise exception 'disallowed ordered position accepted';end if;
 if not public.pdc_auditor_valid_new_value_253('{"description":"edited"}'::jsonb,false,true,false) then raise exception 'valid partial edit rejected';end if;
end$$;

do $$
declare actions text[]:=array['add','edit','split','combine'];errors text[]:=array['PDC_253_ADD_SCHEMA_INVALID','PDC_253_EDIT_SCHEMA_INVALID','PDC_253_SPLIT_SCHEMA_INVALID','PDC_253_COMBINE_SCHEMA_INVALID'];scopes jsonb[];i int;env jsonb;unexpected jsonb;
begin
 scopes:=array[
  jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','add','apply_unambiguous',true,'selector',jsonb_build_object('vehicle_id','20000000-0000-4000-8000-000000000010'),'desire',jsonb_build_object('new_value',jsonb_build_object('description',123,'estimated_hours',1.5,'operation_code','BAD CODE!','work_key','hoist'))),
  jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','edit','apply_unambiguous',true,'selector',jsonb_build_object('operation_ref','source:30000000-0000-4000-8000-000000000011'),'desire',jsonb_build_object('new_value',jsonb_build_object('description',123,'operation_code','BAD CODE!'))),
  jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','split','apply_unambiguous',true,'selector',jsonb_build_object('operation_ref','source:30000000-0000-4000-8000-000000000012'),'desire',jsonb_build_object('children',jsonb_build_array(jsonb_build_object('description',123,'estimated_hours',0.5,'operation_code','BAD CODE!','work_key','fitting'),jsonb_build_object('description','valid child','estimated_hours',1.5,'operation_code','OK','work_key','hoist')))),
  jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','combine','apply_unambiguous',true,'selector',jsonb_build_object('operation_refs',jsonb_build_array('source:30000000-0000-4000-8000-000000000013','source:30000000-0000-4000-8000-000000000014')),'desire',jsonb_build_object('survivor_operation_ref','source:30000000-0000-4000-8000-000000000013','new_value',jsonb_build_object('description',123,'estimated_hours',2,'operation_code','BAD CODE!','work_key','fabrication')))
 ];
 for i in 1..4 loop
  env:=pg_temp.envelope7('Typed boundary rejection '||actions[i],scopes[i],('85000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'typed-boundary-'||actions[i]);
  begin
   unexpected:=public.plan_pdc_auditor_typed_instruction_253(actions[i],'review',scopes[i],env);
   raise exception 'direct signed planner accepted invalid % value: %',actions[i],unexpected;
  exception when sqlstate '22023' then if sqlerrm<>errors[i] then raise exception 'wrong % rejection: %',actions[i],sqlerrm;end if;
  end;
 end loop;
end$$;

do $$
declare scope jsonb;env jsonb;accepted jsonb;
begin
 scope:=jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','add','apply_unambiguous',true,'selector',jsonb_build_object('vehicle_id','20000000-0000-4000-8000-000000000010'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','ok','estimated_hours',1.5,'operation_code','OK','ordered_position',1e0,'work_key','hoist')));
 env:=pg_temp.envelope7('Typed boundary acceptance add canonical integer exponent',scope,'85000000-0000-4000-8000-000000000099'::uuid,'typed-boundary-add-exponent');
 accepted:=public.plan_pdc_auditor_typed_instruction_253('add','review',scope,env);
 if accepted->>'code'<>'typed_review_proposal_created' then raise exception 'canonical integral exponent direct add rejected: %',accepted;end if;
end$$;

-- Signed scalar identifiers must retain the same JSON string types enforced by
-- the Python gateway boundary. PostgreSQL must not silently coerce numbers,
-- booleans, arrays, objects, or null through ->> before signature verification.
do $$
declare scope jsonb;env jsonb;field text;wrong jsonb;unexpected jsonb;
begin
 scope:=jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','add','apply_unambiguous',true,'selector',jsonb_build_object('vehicle_id','20000000-0000-4000-8000-000000000010'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','typed envelope probe','estimated_hours',1.5,'operation_code','TYPE','work_key','hoist')));
 foreach field in array array['gateway_instance_id','delivery_uuid','key_id','nonce','instruction_sha256','signature'] loop
  foreach wrong in array array['1234567890123456'::jsonb,'true'::jsonb,'null'::jsonb,'[]'::jsonb,'{}'::jsonb] loop
   env:=pg_temp.envelope7('Typed envelope scalar rejection '||field||wrong::text,scope,gen_random_uuid(),'typed-envelope-'||field||'-'||substr(md5(wrong::text),1,12));
   env:=jsonb_set(env,array[field],wrong);
   -- Type validation precedes signature verification, so a non-string scalar
   -- must receive the same rejection regardless of the now-stale signature.
   begin
    unexpected:=public.plan_pdc_auditor_typed_instruction_253('add','review',scope,env);
    raise exception 'direct signed planner accepted non-string % (%): %',field,jsonb_typeof(wrong),unexpected;
   exception when sqlstate '22023' then if sqlerrm<>'PDC_253_INVALID_ENVELOPE_VALUE' then raise exception 'wrong non-string % rejection: %',field,sqlerrm;end if;
   end;
  end loop;
 end loop;
end$$;

do $$
declare scope jsonb;env jsonb;field text;wrong jsonb;unexpected jsonb;
begin
 scope:=jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','add','apply_unambiguous',true,'selector',jsonb_build_object('vehicle_id','20000000-0000-4000-8000-000000000010'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','typed Telegram evidence probe','estimated_hours',1.5,'operation_code','TYPE','work_key','hoist')));
 foreach field in array array['bot_identity','instruction_sha256','original_instruction'] loop
  foreach wrong in array array['123'::jsonb,'true'::jsonb,'null'::jsonb,'[]'::jsonb,'{}'::jsonb] loop
   env:=pg_temp.envelope7('Typed Telegram string rejection '||field||wrong::text,scope,gen_random_uuid(),'typed-telegram-'||field||'-'||substr(md5(wrong::text),1,12));
   env:=jsonb_set(env,array['telegram_evidence',field],wrong);
   begin unexpected:=public.plan_pdc_auditor_typed_instruction_253('add','review',scope,env);raise exception 'planner accepted non-string Telegram %: %',field,unexpected;
   exception when sqlstate '22023' then if sqlerrm<>'PDC_253_INVALID_TELEGRAM_EVIDENCE' then raise exception 'wrong Telegram % rejection: %',field,sqlerrm;end if;end;
  end loop;
 end loop;
 foreach field in array array['telegram_chat_id','telegram_message_id','telegram_sender_id','telegram_update_id'] loop
  foreach wrong in array array['"123"'::jsonb,'true'::jsonb,'null'::jsonb,'[]'::jsonb,'{}'::jsonb,'0'::jsonb,'-1'::jsonb,'1.5'::jsonb,'9223372036854775808'::jsonb] loop
   env:=pg_temp.envelope7('Typed Telegram number rejection '||field||wrong::text,scope,gen_random_uuid(),'typed-telegram-'||field||'-'||substr(md5(wrong::text),1,12));
   env:=jsonb_set(env,array['telegram_evidence',field],wrong);
   begin unexpected:=public.plan_pdc_auditor_typed_instruction_253('add','review',scope,env);raise exception 'planner accepted non-number Telegram %: %',field,unexpected;
   exception when sqlstate '22023' then if sqlerrm<>'PDC_253_INVALID_TELEGRAM_EVIDENCE' then raise exception 'wrong Telegram % rejection: %',field,sqlerrm;end if;end;
  end loop;
 end loop;
end$$;

-- Telegram instruction text must match the producer's bounded, trimmed text
-- contract before signature or instruction-hash verification.
do $$
declare scope jsonb;env jsonb;wrong_text text;unexpected jsonb;
begin
 scope:=jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','add','apply_unambiguous',true,'selector',jsonb_build_object('vehicle_id','20000000-0000-4000-8000-000000000010'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','instruction text probe','estimated_hours',1.5,'operation_code','TYPE','work_key','hoist')));
 foreach wrong_text in array array['','ab',' leading','trailing ',repeat('x',4001)] loop
  env:=pg_temp.envelope7('Temporary valid instruction',scope,gen_random_uuid(),'typed-telegram-text-'||substr(md5(wrong_text),1,12));
  env:=jsonb_set(env,'{telegram_evidence,original_instruction}',to_jsonb(wrong_text));
  env:=jsonb_set(env,'{telegram_evidence,instruction_sha256}',to_jsonb(encode(extensions.digest(convert_to(wrong_text,'UTF8'),'sha256'),'hex')));
  env:=jsonb_set(env,'{instruction_sha256}',env->'telegram_evidence'->'instruction_sha256');
  begin unexpected:=public.pdc_auditor_verify_envelope_253('plan',env);raise exception 'verifier accepted invalid Telegram instruction text: %',unexpected;
  exception when sqlstate '22023' then if sqlerrm<>'PDC_253_INVALID_TELEGRAM_EVIDENCE' then raise exception 'wrong instruction-text rejection: %',sqlerrm;end if;end;
 end loop;
end$$;

-- String-typed values must also satisfy the exact Python value grammar before
-- key lookup, signature verification, UUID coercion, or any replay reservation.
do $$
declare scope jsonb;env jsonb;field text;wrong text;unexpected jsonb;
begin
 scope:=jsonb_build_object('contract','pdc-auditor-bounded-intent-253-v1','action','add','apply_unambiguous',true,'selector',jsonb_build_object('vehicle_id','20000000-0000-4000-8000-000000000010'),'desire',jsonb_build_object('new_value',jsonb_build_object('description','value-shape probe','estimated_hours',1.5,'operation_code','TYPE','work_key','hoist')));
 foreach field in array array['gateway_instance_id','key_id','nonce'] loop
  foreach wrong in array case field when 'nonce' then array['short','bad value nonce 123',repeat('x',129)] else array[' bad','-leading',repeat('x',129)] end loop
   env:=pg_temp.envelope7('Envelope identifier value rejection '||field||md5(wrong),scope,gen_random_uuid(),'value-shape-nonce-'||substr(md5(field||wrong),1,12));
   env:=jsonb_set(env,array[field],to_jsonb(wrong));
   begin unexpected:=public.plan_pdc_auditor_typed_instruction_253('add','review',scope,env);raise exception 'planner accepted malformed %: %',field,unexpected;
   exception when sqlstate '22023' then if sqlerrm<>'PDC_253_INVALID_ENVELOPE_VALUE' then raise exception 'wrong malformed % rejection: %',field,sqlerrm;end if;end;
  end loop;
 end loop;
 foreach wrong in array array['{85000000-0000-4000-8000-000000000001}','85000000000040008000000000000001','not-a-uuid'] loop
  env:=pg_temp.envelope7('Envelope UUID value rejection '||md5(wrong),scope,gen_random_uuid(),'value-shape-uuid-'||substr(md5(wrong),1,12));env:=jsonb_set(env,'{delivery_uuid}',to_jsonb(wrong));
  begin unexpected:=public.plan_pdc_auditor_typed_instruction_253('add','review',scope,env);raise exception 'planner accepted malformed delivery UUID: %',unexpected;
  exception when sqlstate '22023' then if sqlerrm<>'PDC_253_INVALID_ENVELOPE_VALUE' then raise exception 'wrong UUID rejection: %',sqlerrm;end if;end;
 end loop;
 foreach field in array array['instruction_sha256','signature'] loop
  foreach wrong in array array['',repeat('0',63),repeat('g',64),repeat('0',65)] loop
   env:=pg_temp.envelope7('Envelope hex value rejection '||field||md5(wrong),scope,gen_random_uuid(),'value-shape-hex-'||substr(md5(field||wrong),1,12));env:=jsonb_set(env,array[field],to_jsonb(wrong));
   begin unexpected:=public.plan_pdc_auditor_typed_instruction_253('add','review',scope,env);raise exception 'planner accepted malformed %: %',field,unexpected;
   exception when sqlstate '22023' then if sqlerrm<>'PDC_253_INVALID_ENVELOPE_VALUE' then raise exception 'wrong hex rejection: %',sqlerrm;end if;end;
  end loop;
 end loop;
 env:=pg_temp.envelope7('Envelope selected-scope type rejection',scope,gen_random_uuid(),'value-shape-scope-123');env:=jsonb_set(env,'{selected_scope}','[]'::jsonb);
 begin unexpected:=public.pdc_auditor_verify_envelope_253('plan',env);raise exception 'verifier accepted non-object selected scope: %',unexpected;
 exception when sqlstate '22023' then if sqlerrm<>'PDC_253_INVALID_ENVELOPE_VALUE' then raise exception 'wrong selected-scope rejection: %',sqlerrm;end if;end;
end$$;

select 'AI_AUDITOR_253_TYPED_VALUE_BOUNDARIES_PASS' result;
