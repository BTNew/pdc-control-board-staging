// r729 (F339): sales list shows Key age (days since key number given) in place of Kewdale ETA when the car is at PMB.
const assert=require('assert'),fs=require('fs');
const src=fs.readFileSync(__dirname+'/sales/sales.js','utf8');
assert(src.includes("['kewdale_eta','Kewdale ETA']"),'column header kept');
assert(src.includes("'<td class=\"eta-cell\">'+etaOrKeyAgeHtml(row)+'</td>'"),'table cell uses key age at PMB');
assert(src.includes("(atPmbWithKey(row)?keyAgeHtml(row):'Kewdale ETA: '+etaHtml(row.kewdale_eta))"),'mobile card uses key age at PMB');
assert(src.includes("rpc('list_pmb_key_assigned_562')"),'reads the key-assigned date the PMB board uses');
// Pull the helpers out and run them.
const grab=name=>{const i=src.indexOf('  function '+name+'(');const j=src.indexOf('\n  }\n',i);return src.slice(i,j+4);};
const state={keyAssigned:new Map()};
const escapeHtml=s=>String(s),dateLabel=s=>s;
const f=new Function('state','escapeHtml','dateLabel',grab('atPmbWithKey')+grab('keyAgeDays')+grab('keyAgeHtml')+'return {atPmbWithKey,keyAgeDays,keyAgeHtml};')(state,escapeHtml,dateLabel);
assert.strictEqual(f.atPmbWithKey({key_number:'448'}),true);
assert.strictEqual(f.atPmbWithKey({key_number:' '}),false);
assert.strictEqual(f.atPmbWithKey({key_number:'448',lifecycle_state:'completed'}),false);
assert.strictEqual(f.atPmbWithKey({key_number:'448',pmb_location:'Completed'}),false);
const threeDays=new Date(Date.now()-3*86400000).toISOString();
assert.strictEqual(f.keyAgeDays(threeDays),3);
assert.strictEqual(f.keyAgeDays(''),null);
state.keyAssigned.set('v1',threeDays);
assert(f.keyAgeHtml({canonical_vehicle_id:'v1',key_number:'448'}).includes('Key age</strong> · 3 days'));
assert(f.keyAgeHtml({canonical_vehicle_id:'v2',key_number:'449'}).includes('Key age</strong> · —'));
console.log('ok test_sales_key_age_729');
