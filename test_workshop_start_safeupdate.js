'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');

// This is a source regression against the actual migration expressions. It
// does not simulate PostgREST's safeupdate hook: that safeguard is loaded in
// API sessions and may be absent from an ordinary SQL rollback-test session.
const dir=path.join(__dirname,'supabase','migrations');
function migration(suffix) {
  const names=fs.readdirSync(dir).filter(name=>name.endsWith(suffix));
  assert.equal(names.length,1,`one deployed/candidate migration for ${suffix}`);
  return fs.readFileSync(path.join(dir,names[0]),'utf8').replace(/\r\n/g,'\n');
}
const originalMigration=migration('_workshop_start_priority_for_unstarted_vehicle_jobs.sql');
const repair=migration('_workshop_start_safeupdate_initialization.sql');
const clockWrapper=migration('_workshop_start_clock_version_rebase.sql');
const signature='public.start_workshop_work_pre_116(uuid,integer,timestamptz,jsonb)';
const begin=originalMigration.indexOf('CREATE OR REPLACE FUNCTION public.start_workshop_work_pre_116(');
const end=originalMigration.indexOf('END $function$;',begin)+'END $function$;'.length;
assert(begin>=0 && end>begin,'PR204 canonical Start function exists');
const original=originalMigration.slice(begin,end);

function sqlLiteral(raw) {
  const escaped=raw.startsWith('E');
  let value=raw.slice(escaped?2:1,-1).replace(/''/g,"'");
  if(escaped)value=value.replace(/\\([nrt\\])/g,(_m,ch)=>({n:'\n',r:'\r',t:'\t','\\':'\\'}[ch]));
  return value;
}
const changes=[...repair.matchAll(/repaired:=replace\((source|repaired),\s*(E?'(?:''|[^'])*'),\s*(E?'(?:''|[^'])*')\);/g)]
  .map(match=>({input:match[1],before:sqlLiteral(match[2]),after:sqlLiteral(match[3])}));
const occurrences=(source,part)=>source.split(part).length-1;
function apply(source) {
  let changed=source;
  for(const change of changes)changed=changed.split(change.before).join(change.after);
  return changed;
}
const repaired=apply(original);

// Split SQL expressions without mistaking commas in window clauses, casts,
// subqueries or array literals for INSERT/SELECT column boundaries.
function topLevelList(sql) {
  const parts=[];let start=0,depth=0,quoted=false,lineComment=false;
  for(let i=0;i<sql.length;i++) {
    const ch=sql[i];
    if(lineComment){if(ch==='\n')lineComment=false;continue;}
    if(!quoted && ch==='-' && sql[i+1]==='-'){lineComment=true;i++;continue;}
    if(ch==="'"){if(quoted && sql[i+1]==="'"){i++;continue;}quoted=!quoted;continue;}
    if(quoted)continue;
    if(ch==='(' || ch==='[')depth++;
    else if(ch===')' || ch===']')depth--;
    else if(ch===',' && depth===0){parts.push(sql.slice(start,i).trim());start=i+1;}
  }
  assert.equal(depth,0);assert.equal(quoted,false);
  parts.push(sql.slice(start).trim());return parts;
}
function initialization(source) {
  const match=source.match(/INSERT INTO pg_temp\.workshop_start_plan\(([\s\S]*?)\)\n SELECT ([\s\S]*?)\n FROM public\.workshop_bookings b/);
  assert(match,'initial INSERT SELECT is present');
  const columns=topLevelList(match[1]),expressions=topLevelList(match[2]);
  assert.equal(columns.length,expressions.length,'each column has exactly one SELECT expression');
  return new Map(columns.map((name,index)=>[name,expressions[index]]));
}

test('safeupdate repair is pinned to the exact reviewed function and all three unique anchors',()=>{
  assert.match(repair,/pdc_monitor_staging_guard\(\) IS NOT TRUE/);
  assert.match(repair,/to_regclass\('public\.pdc_production_environment_sentinel'\) IS NOT NULL/);
  assert(repair.includes(`pg_get_functiondef('${signature}'::regprocedure)`));
  assert.match(repair,/IF md5\(source\)<>'ff85f53f7e0ef5ec9da6fc97466cf6d0' THEN\s+RAISE EXCEPTION/);
  assert.equal(changes.length,3,'read actual SQL transformations rather than duplicating a proposed fix');
  assert.deepEqual(changes.map(change=>change.input),['source','repaired','repaired']);
  for(const change of changes)assert.equal(occurrences(original,change.before),1,change.before);
  assert.match(repair,/Start initialization anchors did not match/);
  assert.equal(occurrences(repair,'EXECUTE repaired;'),1);
});

test('INSERT initializes current bounds from exactly the values previously copied by UPDATE',()=>{
  const before=initialization(original),after=initialization(repaired);
  assert.equal(after.size,before.size+2);
  for(const[column,expression]of before)assert.equal(after.get(column),expression,`unchanged value for ${column}`);
  assert.equal(after.get('current_start'),before.get('original_start'));
  assert.equal(after.get('current_end'),before.get('effective_end'));
  assert.equal(after.get('current_start'),'b.scheduled_start_at');
  assert.equal(after.get('current_end'),'e.ends','must retain the effective occupied end, not only the old scheduled end');
  assert.match(repaired,/current_start timestamptz,current_end timestamptz,write_count integer DEFAULT 0/);
  assert.match(repaired,/parked boolean DEFAULT false,initial_snapshot jsonb/);
});

test('unsafe whole-temp-table UPDATE is removed and remaining plan updates retain predicates',()=>{
  const statements=source=>[...source.matchAll(/\bUPDATE pg_temp\.workshop_start_plan\b[\s\S]*?;/g)].map(match=>match[0]);
  const before=statements(original),after=statements(repaired);
  assert.equal(before.filter(statement=>! /\bWHERE\b/.test(statement)).length,1,'reproduces the rejected statement in the reviewed source');
  assert.equal(after.length,before.length-1);
  assert(after.length>0);
  assert(after.every(statement=>/\bWHERE\b/.test(statement)),'all remaining temporary-plan updates are qualified');
  assert.doesNotMatch(repaired,/SET current_start=original_start,current_end=effective_end/);
  assert.deepEqual(after,before.filter(statement=>/\bWHERE\b/.test(statement)),'other updates are byte-for-byte unchanged');
});

test('effective durations, priority ordering, parking, atomic saves and guards are untouched',()=>{
  // The three old anchors and their replacements are the complete allowed
  // difference; compare each intervening source span rather than isolated
  // guard keywords which could pass even if their logic changed.
  let before=original,after=repaired;
  for(let index=0;index<changes.length;index++) {
    const change=changes[index],marker=`/* verified-initializer-change-${index} */`;
    before=before.replace(change.before,marker);
    if(change.after)after=after.replace(change.after,marker);
    else {
      const anchor=' IF (SELECT count(*) FROM pg_temp.workshop_start_plan)>10000 THEN RETURN jsonb_build_object(\'ok\',false,\'error\',\'schedule_too_large\'); END IF;\n';
      assert.equal(occurrences(after,anchor),1);
      after=after.replace(anchor,anchor+marker);
    }
  }
  assert.equal(after,before,'every character outside the three initialization edits stays unchanged');
});

test('public Start and fitter authority/clock wrappers remain outside the repaired definition',()=>{
  const wholeAfter=originalMigration.slice(0,begin)+repaired+originalMigration.slice(end);
  assert.equal(wholeAfter.slice(0,begin),originalMigration.slice(0,begin));
  assert.equal(wholeAfter.slice(begin+repaired.length),originalMigration.slice(end));
  assert.match(originalMigration.slice(end),/CREATE OR REPLACE FUNCTION public\.fitter_job_command/);
  assert.match(clockWrapper,/CREATE OR REPLACE FUNCTION public\.start_workshop_work\(/);
  assert.match(clockWrapper,/public\.start_workshop_work_pre345\(p_booking_id,v,p_actual_start_at,metadata\)/);
  const targets=[...repair.matchAll(/pg_get_functiondef\('([^']+)'::regprocedure\)/g)].map(match=>match[1]);
  assert.deepEqual(targets,[signature]);
  const withoutComments=repair.replace(/--[^\n]*/g,'');
  assert.doesNotMatch(withoutComments,/\b(?:ALTER|GRANT|REVOKE|DROP)\b|set_config\s*\(|\bLOAD\b|\bSET\s+(?:ROLE|session_preload_libraries|safeupdate)/i,'no authority changes or disabling the HTTP safeguard');
});

test('definition hash guard rejects reapplying prefix replacements to an already repaired function',()=>{
  assert.equal(occurrences(repaired,'apply_order,current_start,current_end)'),1);
  assert.equal(occurrences(repaired,'false,NULL,b.scheduled_start_at,e.ends'),1);
  // The SELECT anchor remains a prefix of the replacement, so blindly running
  // it twice would add values without columns. The deployed-definition guard
  // is essential, and must run before any transformation is executed.
  assert.notEqual(apply(repaired),repaired);
  const digest=value=>crypto.createHash('md5').update(value).digest('hex');
  assert.notEqual(digest(original),digest(repaired));
  assert(repair.indexOf('IF md5(source)')<repair.indexOf('repaired:=replace('));
  assert.match(repair,/Unexpected Start definition; review before applying safeupdate repair/);
});
