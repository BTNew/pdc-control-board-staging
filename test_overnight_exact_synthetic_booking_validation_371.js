const fs=require('fs');const sql=fs.readFileSync('supabase/staging_only/20260825080000_371_overnight_exact_synthetic_booking_validation.sql','utf8');
function need(x){if(!sql.includes(x))throw new Error(`missing ${x}`)}
for(const x of ["project_ref='cdsmnqxtyyoeoznmbidd'","version='20260825070000' AND name='370_overnight_exact_synthetic_minutes'",'456502dbfe5bafd64193830020023117779194ebb1e79e9caba0b4da4da513ca','pdc_duration_minutes<60','e.estimated_minutes=p_duration_minutes','e.estimated_minutes between 1 and 59',"e.run_id=\\'HERMES-TEST-RUN-20260824\\'",'pdc_371_protected_validation',"v_bad->>'error'<>'minimum_duration'","VALUES('20260825080000','371_overnight_exact_synthetic_booking_validation'"])need(x.replace('pdc_duration_minutes','p_duration_minutes'));
if(/^\s*(?:DELETE FROM|TRUNCATE|ALTER TABLE .*DISABLE TRIGGER|GRANT (?:ALL|INSERT|UPDATE|DELETE))/im.test(sql))throw new Error('forbidden mutation or grant');
console.log('migration 371 static contract passed');
