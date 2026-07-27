'use strict';
const fs=require('fs');
function assert(v,m){if(!v)throw new Error(m);}
const sql=fs.readFileSync('supabase/staging_only/080_navision_generic_header_dealer_evidence.sql','utf8');
assert(sql.includes("header_key in ('dealer','dealercode','dealerno','dealernumber')"),'Exact Dealer headers must remain authoritative');
assert(sql.includes("regexp_replace(source_value,'^0+','') in ('14450','37047')"),'Fallback must accept only approved original dealer codes');
assert(sql.includes("count(distinct code)=1"),'Fallback must require one unambiguous approved dealer identity');
assert(sql.includes("when exists(select 1 from columns where header_key in"),'An explicit Dealer header must take precedence over fallback evidence');
assert(sql.includes("'%PILBARA TOYOTA%'")&&sql.includes("'%BROOME TOYOTA%'"),'Fallback must recognize only the two approved exact dealer names');
assert(!sql.includes('hard_delete'),'Dealer evidence recovery must not alter deletion policy');
console.log('Navision generic-header dealer evidence contract passed');
