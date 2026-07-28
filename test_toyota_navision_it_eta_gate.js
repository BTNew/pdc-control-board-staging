'use strict';
const fs=require('fs');
const vm=require('vm');
const assert=require('assert');
const app=fs.readFileSync('app.js','utf8');
const migrationPath='supabase/staging_only/089_toyota_navision_it_requires_kewdale_eta.sql';
assert(fs.existsSync(migrationPath),'migration 089 must exist');
const sql=fs.readFileSync(migrationPath,'utf8');
const parityPath='supabase/staging_only/090_toyota_navision_it_status_parity.sql';
assert(fs.existsSync(parityPath),'migration 090 must close pre-arrival status parity');
const paritySql=fs.readFileSync(parityPath,'utf8');

function extractFunction(source,name){
  const marker=`function ${name}(`;
  const start=source.indexOf(marker); assert(start>=0,`${name} must exist`);
  const bodyStart=source.indexOf(') {',start)+2; assert(bodyStart>1,`${name} body must exist`); let depth=0;
  for(let i=bodyStart;i<source.length;i++){
    if(source[i]==='{')depth++;
    else if(source[i]==='}'&&--depth===0)return source.slice(start,i+1);
  }
  throw new Error(`unterminated ${name}`);
}

const context={
  vehicleLooksToyota:v=>v.toyota!==false,
  cleanNavisionText:v=>String(v||'').trim(),
  navisionLocationSourceText:v=>[v.navisionLocationStatus,v.navisionSubLocationDescription,v.toyotaStatus].filter(Boolean).join(' ').toLowerCase(),
  normalizeToyotaStatus:v=>String(v||'').trim().toLowerCase(),
  kewdaleEtaValue:v=>String(v.navisionKewdaleEta||v.etaAtKewdale||v.etaAtDealer||''),
  parseDateAU:v=>/^\d{4}-\d{2}-\d{2}$/.test(String(v||''))||/^\d{1,2}\/\d{1,2}\/\d{4}$/.test(String(v||''))?new Date(2026,6,30):null,
};
vm.createContext(context);
vm.runInContext(`${extractFunction(app,'navisionImportedToyotaTransitCategory')}; this.classify=navisionImportedToyotaTransitCategory;`,context);
assert.strictEqual(context.classify({source:'Navision',toyota:true,navisionLocationStatus:'In Transit'}),'other','Navision Toyota transit without ETA must be OTHER');
assert.strictEqual(context.classify({source:'Shared Navision',toyota:true,pdcLocation:'IT',navisionKewdaleEta:'not-a-date'}),'other','invalid ETA must not qualify for IT');
assert.strictEqual(context.classify({source:'Navision',toyota:true,navisionSubLocationDescription:'Final Inspection'}),'other','Final Inspection without ETA must remain OTHER');
assert.strictEqual(context.classify({source:'Navision',toyota:true,navisionSubLocationDescription:'Planned for Production'}),'other','Planned for Production without ETA must remain OTHER');
assert.strictEqual(context.classify({source:'Navision',toyota:true,navisionSubLocationDescription:'Planned for Production',navisionKewdaleEta:'2026-08-05'}),'prodtransit','Planned for Production with ETA may qualify for IT');
assert.strictEqual(context.classify({sourceSystem:'microsoft_navision',toyota:true,navisionSubLocationDescription:'In Transit to WA',navisionKewdaleEta:'2026-07-30'}),'prodtransit','valid Kewdale ETA must qualify a Navision Toyota transit row for IT');
assert.strictEqual(context.classify({source:'Manual tracker',toyota:true,navisionLocationStatus:'In Transit'}),'','non-Navision rows retain existing category rules');
assert(app.includes("const navisionTransitCategory = navisionImportedToyotaTransitCategory(vehicleOrStatus);"),'statusCategory must call the ETA gate');
assert(app.includes("if (navisionTransitCategory) return navisionTransitCategory;"),'ETA gate result must take precedence over raw transit text');

assert(sql.includes("project_ref='cdsmnqxtyyoeoznmbidd'"),'migration must be staging guarded');
assert(sql.includes('navision_kewdale_eta_from_payload'),'migration must parse the authoritative Kewdale ETA field');
assert(sql.includes("when value like '%INTRANSIT%'"),'Navision transit classification must remain explicit');
assert(sql.includes('public.navision_kewdale_eta_from_payload(p_data) is not null'),'IT classification must require a parsed ETA date');
assert(sql.includes("new.current_location:='Other'"),'database must fail closed when a Navision vehicle would enter IT without ETA');
assert(sql.includes('before insert or update of current_location,eta_to_kewdale,source_system,source_record_id'),'database enforcement must cover every canonical Navision location write');
assert(sql.includes("upper(btrim(coalesce(v.current_location,''))) in ('IT','OTHER')"),'backfill must be limited to pre-workflow IT/OTHER rows');
assert(sql.includes("'source','toyota_navision_it_eta_gate_089'"),'backfill changes must be audited');
assert(paritySql.includes("value like '%PLANNEDFORPRODUCTION%'"),'server parity must cover Planned for Production');
assert(paritySql.includes("value like '%FINALINSPECTION%'"),'server parity must cover Final Inspection');
assert(paritySql.includes("value like '%READYFORSHIPMENT%'"),'server parity must cover Ready for Shipment');
assert(paritySql.includes("and public.navision_kewdale_eta_from_payload(p_data) is not null then 'IT'"),'all pre-arrival statuses must still require a parsed ETA');
assert(!sql.includes('vjdtsswhroyguxyfjdkt'),'migration must never name production');
console.log('Toyota Navision IT/Kewdale ETA gate contract passed');
