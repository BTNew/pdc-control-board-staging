/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');

// Follow this invoker RPC's private dependency across migrations. Replacing
// an existing function retains its ACL; renaming it and creating a successor
// gives the successor a new ACL. This guard runs in the normal staging CI.
const target='pdc_navision_upload_private.preview_profile';
function previewAcl(sources){
 let exists=false,grants=new Set();
 for(const source of sources){
  const sql=source.replace(/--[^\n]*/g,'').replace(/\/\*[\s\S]*?\*\//g,'');
  const events=[];
  for(const m of sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+pdc_navision_upload_private\.preview_profile\s*\(/gi))events.push({at:m.index,type:'create'});
  for(const m of sql.matchAll(/ALTER\s+FUNCTION\s+pdc_navision_upload_private\.preview_profile\s*\([^;]*?\)\s+RENAME\s+TO/gi))events.push({at:m.index,type:'rename'});
  for(const m of sql.matchAll(/(GRANT|REVOKE)\s+(?:ALL(?:\s+PRIVILEGES)?|EXECUTE)\s+ON\s+(FUNCTIONS?|ALL\s+FUNCTIONS\s+IN\s+SCHEMA)\s+([\s\S]*?)\s+(?:TO|FROM)\s+([^;]+);/gi)){
   const applies=m[2].toUpperCase().startsWith('ALL')
    ? /\bpdc_navision_upload_private\b/i.test(m[3])
    : /\bpdc_navision_upload_private\.preview_profile\s*\(/i.test(m[3]);
   if(applies)events.push({at:m.index,type:m[1].toLowerCase(),roles:m[4].split(',').map(r=>r.trim().toLowerCase())});
  }
  for(const e of events.sort((a,b)=>a.at-b.at)){
   if(e.type==='rename'){exists=false;grants.clear();}
   else if(e.type==='create'){if(!exists)grants=new Set(['public']);exists=true;}
   else if(exists)for(const role of e.roles){if(e.type==='grant')grants.add(role);else grants.delete(role);}
  }
 }
 return {exists,authenticated:grants.has('authenticated')||grants.has('public'),anon:grants.has('anon')||grants.has('public')};
}
const folder=path.join(__dirname,'supabase','migrations');
const files=fs.readdirSync(folder).filter(f=>f.endsWith('.sql')).sort();
const sources=files.map(file=>fs.readFileSync(path.join(folder,file),'utf8'));

test('upload preview dependency remains executable by signed-in staff after all migrations',()=>{
 assert.deepEqual(previewAcl(sources),{exists:true,authenticated:true,anon:false},target);
});
test('access guard detects the dealer-delivery successor permission regression',()=>{
 const last=files.findIndex(f=>f.includes('_navision_delivered_dealer_completion.sql'));
 assert.ok(last>=0);
 assert.deepEqual(previewAcl(sources.slice(0,last+1)),{exists:true,authenticated:false,anon:false});
});
test('an additional revoke or renamed successor without its staff grant fails the access guard',()=>{
 const revoke=`REVOKE ALL ON FUNCTION ${target}(text,jsonb,text,timestamptz) FROM authenticated;`;
 assert.equal(previewAcl([...sources,revoke]).authenticated,false);
 const successor=`ALTER FUNCTION ${target}(text,jsonb,text,timestamptz) RENAME TO preview_previous; CREATE FUNCTION ${target}(text,jsonb,text,timestamptz); REVOKE ALL ON FUNCTION ${target}(text,jsonb,text,timestamptz) FROM PUBLIC,anon,authenticated;`;
 assert.equal(previewAcl([...sources,successor]).authenticated,false);
});
