-- r736 rollback: the two bay checks assert the r483/r509 names and flags again (red while Hoist 01 and Tint 02 are hidden).
UPDATE pdc_ops.regression_checks
SET check_sql = replace(replace(check_sql,
   $a$AND b.is_active = (NOT (m.stage_code = 'HOIST' AND m.bay_number = 1) AND (m.stage_code <> 'ELECTRICAL' OR m.bay_number <= 7)) AS good$a$,
   $a$AND b.is_active = (m.stage_code <> 'ELECTRICAL' OR m.bay_number <= 7) AS good$a$),
   $a$(SELECT n FROM o WHERE code='TINT'),0)=1$a$, $a$(SELECT n FROM o WHERE code='TINT'),0)=2$a$)
WHERE check_name = 'pmb_bay_names_483';
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, $a$OR g.code IS DISTINCT FROM e.code
             OR NOT g.is_active$a$, $a$OR g.code IS DISTINCT FROM e.code
             OR g.display_name IS DISTINCT FROM e.display_name OR NOT g.is_active$a$)
WHERE check_name = 'fabrication_bays_14_509';
