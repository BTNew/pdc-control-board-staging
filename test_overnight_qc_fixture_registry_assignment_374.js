const fs=require('fs');const s=fs.readFileSync('supabase/staging_only/20260825110000_374_overnight_qc_fixture_registry_assignment.sql','utf8');
for(const x of ["version='20260825100000' AND name='373_overnight_qc_fixture_completion'","CREATE OR REPLACE FUNCTION public.pdc_hermes_test_complete_qc_fixture_373","SELECT r.* INTO v_registry","PDC_374_STAGING_HEAD_OR_CONTAINMENT_MISMATCH","VALUES('20260825110000','374_overnight_qc_fixture_registry_assignment'"])if(!s.includes(x))throw new Error(`missing ${x}`);
if(s.includes('SELECT r INTO v_registry'))throw new Error('composite row assignment regression');
if(/^\s*(?:DELETE FROM|TRUNCATE|ALTER TABLE .*DISABLE TRIGGER|GRANT (?:ALL|INSERT|UPDATE|DELETE))/im.test(s))throw new Error('forbidden');
console.log('migration 374 static contract passed');
