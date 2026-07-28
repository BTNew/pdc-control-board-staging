'use strict';
const fs=require('fs');
function assert(v,m){if(!v)throw new Error(m);}
const sql=fs.readFileSync('supabase/staging_only/082_navision_authenticated_api_timeout.sql','utf8');
assert(sql.includes("alter role authenticated set statement_timeout = '30s'"),'Signed-in staging API role must use the measured 30-second bound');
assert(!/alter role\s+(anon|authenticator|service_role|postgres)/i.test(sql),'Migration must not broaden another database role');
assert(!/statement_timeout\s*=\s*'(?:0|[4-9]\ds|\d+m)'/i.test(sql),'Migration must not disable or exceed the 30-second API bound');
assert(sql.includes("notify pgrst, 'reload config'"),'PostgREST must reload the role configuration');
assert(sql.includes('PDC_STAGING_SENTINEL_MISMATCH'),'Migration must fail closed outside staging');
console.log('Navision authenticated API timeout contract passed');
