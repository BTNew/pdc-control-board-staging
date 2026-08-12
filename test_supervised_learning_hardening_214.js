const fs=require('fs'),assert=require('assert');
const s=fs.readFileSync('supabase/staging_only/214_supervised_learning_review_undo_hardening.sql','utf8');
for(const x of ["project_ref='cdsmnqxtyyoeoznmbidd'","version='213'","name='persistent_supervised_email_learning'","version::integer>213","version='214'",'pdc_supervised_review_queue','No deterministic active rule and no existing mapping',"last_outcome='applied'","last_outcome is null",'restored by undo','read_pdc_supervised_learning_rule','apply_pdc_supervised_correction_batch_213','undo_pdc_supervised_rule_213',"'214','supervised_learning_review_undo_hardening'"]) assert.ok(s.includes(x),`missing ${x}`);
assert.ok(!/vjdtsswhroyguxyfjdkt/.test(s),'production reference forbidden');
assert.ok(!/grant\s+[^;]+to\s+(?:anon|public|service_role)/i.test(s),'unsafe grant');
console.log('Migration 214 supervised learning hardening contract passed');
