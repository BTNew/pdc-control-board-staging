'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { performance } = require('perf_hooks');
const auditor = require('./pdc-ai-auditor-stage-a.js');
const fixtures = require('./pdc-ai-auditor-stage-a-fixtures.js');

const clone = value => JSON.parse(JSON.stringify(value));
function freeze(value) { if (!value || typeof value !== 'object' || Object.isFrozen(value)) return value; Object.values(value).forEach(freeze); return Object.freeze(value); }
function has(result, id) { return result.findings.some(row => row.ruleId === id); }
function base() { return fixtures.buildRuleFixture('LABOUR_HOURS_MISSING'); }
function cleanBase() { const s=base(); s.workItems[0].estimatedHours=1; return s; }
function audit(s, at=fixtures.NOW_ISO, options) { return auditor.auditSnapshot(s, at, options); }

// Machine-readable catalogue completeness and one executable positive fixture per rule.
assert.ok(Array.isArray(auditor.RULE_CATALOGUE));
assert.strictEqual(auditor.RULE_CATALOGUE.length, 54);
assert.strictEqual(new Set(auditor.RULE_CATALOGUE.map(r => r.id)).size, auditor.RULE_CATALOGUE.length);
const requiredCatalogueFields=['id','name','authoritativeInputs','exactCondition','exclusions','severity','risk','confidenceSemantics','recommendedAction','stableDedupeIdentity','resolutionCondition','limitations'];
for(const rule of auditor.RULE_CATALOGUE){
  requiredCatalogueFields.forEach(k=>assert.ok(Object.prototype.hasOwnProperty.call(rule,k),`${rule.id} missing ${k}`));
  assert.ok(rule.authoritativeInputs.length>0);
  assert.ok(['critical','high','medium','low','info'].includes(rule.severity));
  assert.ok(['authority','conflict','hours','parts','forgotten','stoppage','workflow'].includes(rule.risk.component));
  const result=audit(freeze(fixtures.buildRuleFixture(rule.id)));
  assert.ok(has(result,rule.id),`direct fixture did not exercise ${rule.id}`);
  assert.strictEqual(result.ruleCatalogueCount,auditor.RULE_CATALOGUE.length);
  assert.strictEqual(result.ruleCatalogueVersion,auditor.RULE_CATALOGUE_VERSION);
}
const vehicleFinding = audit(fixtures.buildRuleFixture('LABOUR_HOURS_MISSING')).findings.find(row => row.ruleId === 'LABOUR_HOURS_MISSING');
assert.ok(vehicleFinding.vehicleId, 'vehicle-scoped findings must carry the exact authoritative vehicle identity for read-only detail navigation');
assert.ok(Object.isFrozen(auditor.RULE_CATALOGUE)&&auditor.RULE_CATALOGUE.every(Object.isFrozen));
assert.strictEqual(fs.readFileSync(path.join(__dirname,'docs','pdc-ai-auditor-stage-a-rule-catalogue.md'),'utf8').replace(/\r\n/g,'\n'),auditor.renderRuleCatalogueMarkdown(),'rule catalogue document drifted from executable catalogue');

// 192 dealer-separated mixed-board vehicle fixtures.
assert.ok(fixtures.fixtureCount>=192,`expected >=192 fixtures, got ${fixtures.fixtureCount}`);
assert.strictEqual(fixtures.snapshots.length,4);
fixtures.snapshots.forEach((s,i)=>{
  assert.strictEqual(s.vehicles.length,48);
  assert.ok(s.vehicles.every(v=>v.id.startsWith(`${fixtures.DEALERS[i]}-`)));
  const result=audit(s);
  assert.ok(result.findings.length>0);
  assert.ok(result.findings.every(f=>f.dealer===fixtures.DEALERS[i]));
});

// Pure transformation, recursive freeze, repeat/session determinism.
const frozen=freeze(clone(fixtures.snapshots[0])),before=JSON.stringify(frozen);
const first=audit(frozen),second=audit(frozen);
assert.strictEqual(JSON.stringify(frozen),before,'input mutated');
assert.deepStrictEqual(first,second,'repeat analysis changed');
assert.ok(Object.isFrozen(first)&&Object.isFrozen(first.findings)&&Object.isFrozen(first.config));
const sessionA=auditor.transitionHistory([],first.findings,fixtures.NOW_ISO);
const sessionB=auditor.transitionHistory([],second.findings,fixtures.NOW_ISO);
assert.deepStrictEqual(sessionA,sessionB,'session transition is nondeterministic');

// Input/database ordering cannot affect full output.
const reversed=clone(fixtures.snapshots[0]);
['vehicles','workItems','bookings','stationCompatibility','parallelCompatibility','parts'].forEach(k=>reversed[k].reverse());
assert.deepStrictEqual(audit(reversed),first,'database/input order changed output');
const rotated=clone(fixtures.snapshots[0]);
for(const k of ['vehicles','workItems','bookings','stationCompatibility']) if(rotated[k].length) rotated[k].push(rotated[k].shift());
assert.deepStrictEqual(audit(rotated),first,'database rotation changed output');

// Stable recommendation identity vs evidence fingerprint and resolution/reappearance.
const stop=fixtures.buildRuleFixture('WORK_STOPPAGE');
const f1=audit(stop).findings.find(f=>f.ruleId==='WORK_STOPPAGE');
stop.workItems[0].stoppageReason='new evidence';
const f2=audit(stop,'2026-07-29T05:00:00.000Z').findings.find(f=>f.ruleId==='WORK_STOPPAGE');
assert.strictEqual(f1.id,f2.id); assert.notStrictEqual(f1.fingerprint,f2.fingerprint);
const detected=auditor.transitionHistory([], [f1], fixtures.NOW_ISO);
const unchanged=auditor.transitionHistory(detected,[f1],'2026-07-29T05:00:00.000Z');
assert.strictEqual(unchanged[0].transition,'unchanged');
const resolved=auditor.transitionHistory(unchanged,[],'2026-07-29T06:00:00.000Z');
assert.strictEqual(resolved[0].transition,'resolved');
const reappeared=auditor.transitionHistory(resolved,[f2],'2026-07-29T07:00:00.000Z');
assert.strictEqual(reappeared[0].transition,'reappeared'); assert.strictEqual(reappeared[0].reappearanceCount,1);

// Perth fixed UTC+8, no DST in winter or summer.
assert.deepStrictEqual(auditor.perthParts(new Date('2026-07-29T00:00:00.000Z')).minute,480);
assert.deepStrictEqual(auditor.perthParts(new Date('2026-01-29T00:00:00.000Z')).minute,480);
assert.strictEqual(auditor.perthParts(new Date('2026-01-29T16:00:00.000Z')).dateKey,'2026-01-30');

// Working calendar: weekend, explicit holiday, and exact 1/3 working-day thresholds.
const calendar={...auditor.DEFAULT_CONFIG,holidays:[],businessDays:[1,2,3,4,5]};
assert.strictEqual(auditor.workingDaysBetween(new Date('2026-07-24T00:00:00.000Z'),new Date('2026-07-27T04:00:00.000Z'),calendar),1,'weekend must not count');
assert.strictEqual(auditor.workingDaysBetween(new Date('2026-07-24T00:00:00.000Z'),new Date('2026-07-27T04:00:00.000Z'),{...calendar,holidays:['2026-07-27']}),0,'holiday must not count');
assert.strictEqual(auditor.workingDaysBetween(new Date('2026-07-23T00:00:00.000Z'),new Date('2026-07-28T04:00:00.000Z'),calendar),3,'Fri/Mon/Tue are 3 working days');
assert.strictEqual(auditor.workingDaysBetween(new Date('2026-07-27T00:00:00.000Z'),new Date('2026-07-28T23:59:00.000Z'),calendar),1,'next working day does not count before 08:00 Perth');
assert.strictEqual(auditor.workingDaysBetween(new Date('2026-07-27T00:00:00.000Z'),new Date('2026-07-29T00:00:00.000Z'),calendar),2,'next working day counts exactly at 08:00 Perth');
assert.strictEqual(auditor.workingDaysBetween(new Date('2026-07-27T00:00:00.000Z'),new Date('2026-07-29T08:00:00.000Z'),calendar),2,'16:00 Perth EOD does not double-count a working day');
const one=fixtures.buildRuleFixture('PARTS_NOT_CONFIRMED_ONE_WORKING_DAY');
assert.ok(has(audit(one),'PARTS_NOT_CONFIRMED_ONE_WORKING_DAY'));
one.parts[0].createdAt='2026-07-29T00:00:00.000Z'; assert.ok(!has(audit(one),'PARTS_NOT_CONFIRMED_ONE_WORKING_DAY'),'same local working day is below threshold');
const three=fixtures.buildRuleFixture('PARTS_ORDERED_OR_UNKNOWN_THREE_WORKING_DAYS');
assert.ok(has(audit(three),'PARTS_ORDERED_OR_UNKNOWN_THREE_WORKING_DAYS'));
three.parts[0].orderedAt='2026-07-27T00:00:00.000Z'; assert.ok(!has(audit(three),'PARTS_ORDERED_OR_UNKNOWN_THREE_WORKING_DAYS'));

// Missing holiday configuration fails safely and suppresses every working-day assertion.
const noCalendar=fixtures.buildRuleFixture('FORGOTTEN_WORK'); delete noCalendar.config.holidays;
const noCalendarResult=audit(noCalendar);
assert.ok(has(noCalendarResult,'HOLIDAY_CALENDAR_COVERAGE_LIMIT'));
for(const id of ['FORGOTTEN_WORK','NO_PROGRESS','PARTS_NOT_CONFIRMED_ONE_WORKING_DAY','PARTS_ORDERED_OR_UNKNOWN_THREE_WORKING_DAYS','RFT_NOT_COLLECTED']) assert.ok(!has(noCalendarResult,id),`${id} must be suppressed without holidays`);

// 08:00–16:00 local boundaries; end exactly 16:00 is valid, one minute later is not.
const boundary=cleanBase(); boundary.bookings=[{id:'b1',dealer:boundary.dealer,revision:'br',vehicleId:'v1',workId:'w1',type:'FAB',station:'B1',status:'planned',startAt:'2026-07-30T07:00:00.000Z',endAt:'2026-07-30T08:00:00.000Z',expectedDurationMinutes:60}];
assert.ok(!has(audit(boundary),'BOOKING_OUTSIDE_HOURS'),'16:00 Perth end must be allowed');
boundary.bookings[0].endAt='2026-07-30T08:01:00.000Z'; assert.ok(has(audit(boundary),'BOOKING_OUTSIDE_HOURS'));
boundary.bookings[0].startAt='2026-07-30T00:00:00.000Z';boundary.bookings[0].endAt='2026-07-30T08:00:00.000Z';boundary.bookings[0].expectedDurationMinutes=480;
assert.ok(!has(audit(boundary),'BOOKING_OUTSIDE_HOURS'),'exact 08:00–16:00 Perth interval must be allowed');

// Configurable department and provisional duration thresholds.
const duration=cleanBase(); duration.bookings=[{id:'b1',dealer:duration.dealer,revision:'br',vehicleId:'v1',workId:'w1',type:'FAB',department:'FAB',station:'B1',status:'planned',startAt:'2026-07-30T01:00:00.000Z',endAt:'2026-07-30T01:20:00.000Z',expectedDurationMinutes:20}];
duration.config.durationThresholds={fab:{minMinutes:30,maxMinutes:120}};
assert.ok(has(audit(duration),'BOOKING_DURATION_TOO_SHORT'));
duration.bookings[0].provisional=true; duration.config.provisionalDurationThresholds={fab:{minMinutes:10,maxMinutes:180}};
assert.ok(!has(audit(duration),'BOOKING_DURATION_TOO_SHORT'));
duration.bookings[0].provisional=false;duration.bookings[0].endAt='2026-07-30T01:30:00.000Z';duration.bookings[0].expectedDurationMinutes=45;
assert.ok(!has(audit(duration),'BOOKING_DURATION_TOO_SHORT'),'minimum equality is valid');
assert.ok(!has(audit(duration),'BOOKING_DURATION_MISMATCH'),'duration mismatch tolerance equality is valid');

// Parts authority semantics and non-contamination: unrelated same-vehicle Parts never assert against job w1.
const contamination=cleanBase();
contamination.workItems.push({...contamination.workItems[0],id:'w2'});
contamination.parts=[{id:'p-other',dealer:contamination.dealer,vehicleId:'v1',workId:'w2',scope:'job-specific',vehicleConfidence:1,jobConfidence:1,status:'ready',ready:true}];
const contaminationResult=audit(contamination);
assert.ok(!contaminationResult.findings.some(f=>f.ruleId.startsWith('PARTS_')&&f.scope.includes('w1')),'unrelated Parts contaminated w1');
const vehicleOnly=cleanBase(); vehicleOnly.parts=[{id:'pv',dealer:vehicleOnly.dealer,vehicleId:'v1',scope:'vehicle',status:'ready',vehicleConfidence:1,jobConfidence:1}];
const vehicleOnlyResult=audit(vehicleOnly);
assert.ok(has(vehicleOnlyResult,'PARTS_CONFIDENCE_LIMIT'));
assert.ok(!['PARTS_REQUIRED_TODAY','PARTS_NOT_CONFIRMED_ONE_WORKING_DAY','PARTS_ORDERED_OR_UNKNOWN_THREE_WORKING_DAYS','PARTS_ACTIVE_STOPPAGE_BOOKED_OR_STARTED','PARTS_RECEIVED_WITH_STOPPAGE','PARTS_READY_NO_FUTURE_BOOKING'].some(id=>has(vehicleOnlyResult,id)));
const inferred=cleanBase(); inferred.parts=[{id:'pi',dealer:inferred.dealer,vehicleId:'v1',workId:'w1',scope:'inferred',status:'ready',vehicleConfidence:1,jobConfidence:1}];
assert.ok(has(audit(inferred),'PARTS_CONFIDENCE_LIMIT'));

// Approved parallel compatibility suppresses only bay conflict; endpoint touching is not overlap.
const parallel=fixtures.buildRuleFixture('APPROVED_PARALLEL_COMPATIBLE_WORK'),parallelResult=audit(parallel);
assert.ok(has(parallelResult,'APPROVED_PARALLEL_COMPATIBLE_WORK')); assert.ok(!has(parallelResult,'BAY_OVERLAP'));
const endpoints=fixtures.buildRuleFixture('BAY_OVERLAP'); endpoints.bookings[1].startAt=endpoints.bookings[0].endAt; endpoints.bookings[1].endAt='2026-07-30T03:00:00.000Z';
assert.ok(!has(audit(endpoints),'BAY_OVERLAP'),'touching endpoints do not overlap');

// Transparent 0–100 risk with requested named components and caps totaling 100.
assert.ok(first.risk.score>=0&&first.risk.score<=100);
assert.deepStrictEqual(first.risk.categories.map(x=>x.category),['authority','conflict','forgotten','hours','parts','stoppage','workflow']);
assert.strictEqual(first.risk.categories.reduce((n,x)=>n+x.cap,0),100);
assert.ok(first.risk.categories.every(x=>x.points<=x.cap));

// Explicit clocks only and no operational/browser/network/storage/ambient-time primitives.
assert.throws(()=>auditor.auditSnapshot(cleanBase()),/nowIso/);
assert.throws(()=>auditor.auditSnapshot(cleanBase(),'2026-07-29'),/nowIso/);
assert.throws(()=>auditor.transitionHistory([],[],'bad'),/nowIso/);
const source=fs.readFileSync(path.join(__dirname,'pdc-ai-auditor-stage-a.js'),'utf8');
for(const pattern of [/\blocalStorage\b/,/\bsessionStorage\b/,/\bindexedDB\b/,/\bdocument\b/,/\bwindow\b/,/\bnavigator\b/,/\bfetch\s*\(/,/\bXMLHttpRequest\b/,/\bWebSocket\b/,/\bsupabase\b/i,/\.rpc\s*\(/,/\bDate\.now\s*\(/,/new Date\s*\(\s*\)/,/\bsetTimeout\s*\(/,/\bsetInterval\s*\(/,/\bcreate_workshop_booking\b/,/\bmove_workshop_booking\b/,/\bcomplete_workshop_booking\b/]) assert.ok(!pattern.test(source),`forbidden primitive ${pattern}`);
assert.strictEqual(globalThis.PdcAiAuditorStageA,auditor,'browser/CommonJS API mismatch');

// Dedicated RPC-shaped snapshot adapter: no browser-created authority and no guessed links.
const rpcSnapshot={ok:true,code:'pdc_auditor_snapshot',snapshot_contract_version:'stage-a-v2',dealer_code:'14450',environment:'staging',response_revision:'a'.repeat(64),generated_at:fixtures.NOW_ISO,page_size:100,has_more:false,next_vehicle_id:null,
  source_revisions:{workshop_revision:11,pdc_email_vehicle_revision:22,auditor_revision:3,auditor_relation_revision:4,auditor_config_revision:5},
  working_calendar:{timezone:'Australia/Perth',working_days:['monday','tuesday','wednesday','thursday','friday'],day_start:'08:00',day_end:'16:00',holiday_configuration_status:'missing'},
  items:[{vehicle_id:'11111111-1111-4111-8111-111111111111',vehicle_version:3,dealer_code:'14450',key_number:'RPC-K',stock_number:'RPC-S',
    lifecycle:{state:'active'},workshop:{status:'workshop'},location:{code:'YH'},quality:{},
    work_items:[{work_item_id:'22222222-2222-4222-8222-222222222222',work_key:'fitting',required:true,completed:false,status:'required',updated_at:fixtures.NOW_ISO,hours:{confirmed_hours:0,estimated_hours:2,provenance:'ai_estimate'}}],
    bookings:[{booking_id:'33333333-3333-4333-8333-333333333333',stage_code:'fitting',bay_id:'bay-rpc',status:'planned',scheduled_start_at:'2026-07-20T01:00:00.000Z',scheduled_end_at:'2026-07-20T03:00:00.000Z',relationship_status:'legacy_no_relation_unlinked',linked_work_item_id:null,canonical_match_count:1,booking_version:5,duration_minutes:120,assignments:[]}],
    parts:{scope:'vehicle_level',vehicle_level:true,job_specific:false,parts_required:true,parts_ordered:false,parts_received:false,updated_at:fixtures.NOW_ISO,classification:'confirmed'},operation_lines:[],line_adjustments:[],movement_events:[],workflow_events:[],
    collection_completeness:{work_items:{returned:1,total:1,limit:100,complete:true},bookings:{returned:1,total:1,limit:100,complete:true},operation_lines:{returned:0,total:0,limit:100,complete:true},line_adjustments:{returned:0,total:0,limit:100,complete:true},movement_events:{returned:0,total:0,limit:25,complete:true},workflow_events:{returned:0,total:0,limit:100,complete:true}}}],station_compatibility:[],parallel_compatibility:[]};
const rpcAudit=auditor.analyze(rpcSnapshot);
for(const generatedAt of ['2026-07-29T07:33:54.514117Z','2026-07-29T07:33:54.514117+00:00']){
  const postgresTimestamp=clone(rpcSnapshot);postgresTimestamp.generated_at=generatedAt;
  assert.doesNotThrow(()=>auditor.analyze(postgresTimestamp),'canonical PostgreSQL UTC precision must be accepted');
}
const nonUtc=clone(rpcSnapshot);nonUtc.generated_at='2026-07-29T15:33:54.514117+08:00';assert.throws(()=>auditor.analyze(nonUtc),/generated_at/);
const frozenRpc=freeze(clone(rpcSnapshot)),frozenRpcBefore=JSON.stringify(frozenRpc);
assert.deepStrictEqual(auditor.analyze(frozenRpc),auditor.analyze(frozenRpc),'authoritative adapter repeat analysis changed');
assert.strictEqual(JSON.stringify(frozenRpc),frozenRpcBefore,'authoritative adapter mutated frozen SQL DTO');
assert.strictEqual(rpcAudit.dealer,'14450','RPC items must preserve dealer authority');
assert.ok(rpcAudit.findings.some(f=>f.Key==='RPC-K'),'RPC items must be adapted as canonical vehicles');
assert.ok(has(rpcAudit,'BOOKING_WITHOUT_ACTIVE_CANONICAL_WORK'),'legacy unlinked booking must generate review rather than link');
assert.ok(has(rpcAudit,'PARTS_CONFIDENCE_LIMIT'),'vehicle-level Parts must create a confidence limit');
assert.ok(!has(rpcAudit,'PARTS_JOB_SPECIFIC_NOT_CONFIRMED'),'vehicle-level Parts must not become job-level unsafe evidence');
assert.ok(has(rpcAudit,'HOLIDAY_CALENDAR_COVERAGE_LIMIT'),'missing holiday configuration must fail safely');
const adapted=auditor.adaptAuthoritativeSnapshot(rpcSnapshot);
assert.strictEqual(adapted.snapshot.bookings[0].workId,'','canonical_match_count is diagnostic and must never synthesize a link');
for(const [mutate,message] of [
  [x=>{x.ok=false;},/ok\/code\/contract/],
  [x=>{x.environment='production';},/environment/],
  [x=>{x.dealer_code='other';},/dealer/],
  [x=>{x.response_revision='bad';},/revision hash/],
  [x=>{delete x.source_revisions.auditor_revision;},/auditor_revision/],
  [x=>{x.has_more=true;x.next_vehicle_id='11111111-1111-4111-8111-111111111111';},/pagination/],
  [x=>{x.items[0].dealer_code='37047';},/dealer mismatch/],
  [x=>{delete x.items[0].operation_lines;},/operation_lines/],
]){const invalid=clone(rpcSnapshot);mutate(invalid);assert.throws(()=>auditor.analyze(invalid),message);}
const explicit=clone(rpcSnapshot);explicit.items[0].bookings[0].relationship_status='explicit_linked_active';explicit.items[0].bookings[0].linked_work_item_id=explicit.items[0].work_items[0].work_item_id;
assert.strictEqual(auditor.adaptAuthoritativeSnapshot(explicit).snapshot.bookings[0].workId,explicit.items[0].work_items[0].work_item_id,'only explicit relation state may expose linked ID');
const rpcPermuted=clone(explicit);rpcPermuted.items[0].operation_lines.reverse();rpcPermuted.items[0].line_adjustments.reverse();rpcPermuted.items[0].bookings.reverse();rpcPermuted.items[0].work_items.reverse();
assert.deepStrictEqual(auditor.analyze(rpcPermuted),auditor.analyze(explicit),'independent SQL child collection order changed output');

// Focused deterministic performance gate: 100 audits / 4,800 vehicle fixtures.
const started=performance.now(); let total=0;
for(let pass=0;pass<25;pass++) fixtures.snapshots.forEach(s=>{total+=audit(s).findings.length;});
const elapsed=performance.now()-started; assert.ok(total>0); assert.ok(elapsed<3000,`performance ${elapsed.toFixed(2)}ms`);
console.log(`Stage A deterministic auditor: PASS (${fixtures.fixtureCount} dealer-separated fixtures; ${auditor.RULE_CATALOGUE.length}/${auditor.RULE_CATALOGUE.length} catalogue rules directly exercised)`);
console.log(`Focused performance: ${elapsed.toFixed(2)} ms for 100 audits / 4,800 vehicle fixtures; ${(elapsed/100).toFixed(2)} ms/audit`);
