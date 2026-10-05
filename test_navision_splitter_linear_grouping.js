'use strict';
// Structural checks only. The independent 17-case READ ONLY SQL comparison
// proves returned-data equivalence; this test never connects to a database.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const migration = fs.readFileSync(require.resolve('./supabase/migrations/20261004235337_navision_upload_splitter_linear_grouping.sql'));
const sql = migration.toString('utf8');
const replacement = sql.match(/EXECUTE \$replacement\$([\s\S]*?)\$replacement\$;/)?.[1];
assert.ok(replacement, 'the applied splitter definition is present');
const body = replacement.match(/AS \$function\$([\s\S]*?)\$function\$/)?.[1];
assert.ok(body);

test('the exact applied migration changes one existing private STABLE invoker splitter only', () => {
  assert.equal(crypto.createHash('sha256').update(migration).digest('hex'), 'ff2e8fe78f2f3a7261f24b573f2fe3fdfd6c3f4ebb73cbc0605c351111339189');
  assert.deepEqual([...sql.matchAll(/CREATE OR REPLACE FUNCTION\s+(\S+)\(/g)].map(match => match[1]), ['pdc_navision_upload_private.split_profile']);
  assert.match(replacement, /RETURNS jsonb\s+LANGUAGE plpgsql\s+STABLE\s+SET search_path/);
  assert.doesNotMatch(replacement, /SECURITY DEFINER|\bGRANT\b|\bALTER\b|statement_timeout|lock_timeout|\bINSERT\s+INTO\b|\bDELETE\s+FROM\b|\bUPDATE\s+[a-z_]/i);
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION public\./);
});

test('installation keeps the actual staging guard, frozen definition and exact permissions fence', () => {
  assert.match(sql, /current_user<>'postgres' OR session_user<>'postgres' OR NOT public\.pdc_monitor_staging_guard\(\)/);
  const metadata = JSON.parse(sql.match(/\$metadata\$([\s\S]*?)\$metadata\$::jsonb/)[1]);
  assert.equal(metadata.oid, '3532960');
  assert.equal(metadata.prosecdef, false);
  assert.equal(metadata.provolatile, 's');
  assert.equal(metadata.acl, '{postgres=X/postgres}');
  assert.equal(metadata.identity_arguments, 'p_rows jsonb, p_profile text');
  assert.match(sql, /definition_before<>'ed56db7ed2741cea5c6d4efeb52ca212b7f9783a06700707c4dc17edfd5df440'/);
  assert.match(sql, /metadata_after IS DISTINCT FROM metadata_before OR definition_after<>'2ce8683e055c98f2b50000341a159bb94d4a0cab5405ccd58e1a5bb710c5dba6'/);
});

test('one final aggregation preserves original row order and exclusion order without repeated JSON copying', () => {
  assert.match(body, /accepted_rows jsonb\[\]:=ARRAY\[\]::jsonb\[\]/);
  assert.match(body, /excluded_items jsonb\[\]:=ARRAY\[\]::jsonb\[\]/);
  assert.match(body, /accepted_rows:=array_append\(accepted_rows,jsonb_build_object\('row',normalized,'index',idx\)\)/);
  assert.match(body, /jsonb_agg\(a\.value ORDER BY \(a\.value->>'index'\)::integer\)/);
  assert.match(body, /FROM unnest\(accepted_rows\) AS a\(value\) GROUP BY a\.value#>>'\{row,dealer_code\}'/);
  assert.match(body, /coalesce\(jsonb_object_agg\(g\.dealer_code,g\.rows\),'\{\}'::jsonb\) INTO groups/);
  assert.match(body, /jsonb_agg\(e\.value ORDER BY e\.ordinality\).*FROM unnest\(excluded_items\) WITH ORDINALITY/s);
  assert.doesNotMatch(body, /groups:=jsonb_set|groups:=groups\|\||excluded:=excluded\|\|/);
  assert.match(body, /RETURN jsonb_build_object\('groups',groups,'excluded_rows',excluded\)/);
});

test('dealer, stockless COSI, raw-evidence and existing identity ambiguity guards remain present', () => {
  for (const pattern of [
    /p_profile='broome' THEN allowed:=ARRAY\['37047','001234','002345'\]/,
    /p_profile='pilbara' THEN allowed:=ARRAY\['14450','001234','002345'\]/,
    /jsonb_array_length\(p_rows\) NOT BETWEEN 1 AND 10000/,
    /octet_length\(p_rows::text\)>8000000/,
    /IF codes<>1 OR code IS NULL/,
    /conflicting Dealer values/,
    /normalized:=row_data\|\|jsonb_build_object/,
    /IF matches>1 THEN RAISE EXCEPTION/,
    /existing_order<>ord THEN RAISE EXCEPTION/,
    /stock IS NULL AND NOT sold AND matches=0 AND NOT EXISTS/,
    /length\(ord\) NOT BETWEEN 1 AND 80/,
    /stock IN\('0','TBA'\)/,
    /'TOYOTA-ORDER-'\|\|ord/,
    /No eligible rows for the selected upload/,
  ]) assert.match(body, pattern);
  const matching = body.match(/WITH matched AS \(([\s\S]*?)\) SELECT count\(\*\)/)?.[1];
  assert.ok(matching); assert.match(matching, /\n\s+UNION SELECT/); assert.doesNotMatch(matching, /UNION ALL/);
});

test('other functions and protected PMB, Sales, Karratha and shared-source rows are fenced', () => {
  assert.match(sql, /p\.oid<>target_oid INTO protected_before/);
  assert.match(sql, /p\.oid<>target_oid INTO protected_after/);
  assert.match(sql, /protected_after IS DISTINCT FROM protected_before/);
  for (const scope of ['vehicles', 'pdc_new_vehicle_reviews', 'pdc_sales_private', 'karratha135_%', 'karratha_pdc', 'navision_']) assert.ok(sql.includes(scope), scope);
  assert.match(sql, /rows_before:=fence_snapshot/);
  assert.match(sql, /fence_snapshot IS DISTINCT FROM rows_before/);
  assert.match(sql, /Protected operational or shared source rows changed during splitter repair/);
});
