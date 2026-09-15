'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');

test('emergency migration scopes the temporary-plan update for API safeupdate',()=>{
  const sql=fs.readFileSync(path.join(__dirname,'supabase/migrations/20260915122000_workshop_emergency_safeupdate.sql'),'utf8');
  assert.match(sql,/original_bay_id=bay_id WHERE original_bay_id IS DISTINCT FROM bay_id/);
  assert.doesNotMatch(sql,/safeupdate\.enabled\s*=\s*off|DISABLE ROW LEVEL SECURITY|session_preload_libraries\s*=/i);
  assert.match(sql,/pdc_monitor_staging_guard/);
});

test('every linked CSS asset has a valid stylesheet relation',()=>{
  const html=fs.readFileSync(path.join(__dirname,'index.html'),'utf8');
  const links=html.match(/<link\b[^>]*href="[^"]*\.css[^>]*>/g)||[];
  assert.ok(links.length>5);
  for(const link of links) assert.match(link,/\brel="stylesheet"/,link);
});
