'use strict';
const fs=require('fs');
function assert(v,m){if(!v)throw new Error(m);}
const sql=fs.readFileSync('supabase/staging_only/081_navision_restore_bounded_wrapper_timeout.sql','utf8');
for(const signature of [
  'preview_navision_backend_import(jsonb,text,text,text,timestamptz)',
  'apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)',
  'preview_navision_backend_import_pre076(jsonb,text,text,text,timestamptz)',
  'apply_navision_backend_import_pre076(text,jsonb,text,text,text,timestamptz,text,text,bigint)'
]) assert(sql.includes(`alter function public.${signature}`),`Missing timeout restoration for ${signature}`);
assert((sql.match(/set statement_timeout = '120s'/g)||[]).length===4,'All four current/delegate functions must retain the approved 120-second bound');
assert(!/statement_timeout\s*=\s*'(?:0|[2-9]\d\ds|\d+m)'/i.test(sql),'Migration must not disable or increase the approved timeout');
assert(sql.includes('PDC_STAGING_SENTINEL_MISMATCH'),'Migration must fail closed outside staging');
console.log('Navision wrapper timeout restoration contract passed');
