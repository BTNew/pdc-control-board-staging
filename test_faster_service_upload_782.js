// r782 (F387): Apply sends only changed, new and held-before stocks; F388: no \uXXXX escapes in edge source.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const dir = 'supabase/functions/revolution-upload/';
const edge = fs.readFileSync(dir + 'index.ts', 'utf8');

test('apply filters rows by the r771 delta and falls back to every row', () => {
  assert.match(edge, /const sendRows = await changedRows782\(projectUrl, auth, prepared\.rows\);/);
  assert.match(edge, /p_rows: sendRows\.slice\(i, i \+ 400\)/);
  assert.match(edge, /if \(part\.ok !== true \|\| !part\.hashes\) return rows;/);
  assert.match(edge, /if \(compared\.ok !== true \|\| !Array\.isArray\(compared\.unchanged\)\) return rows;/);
  assert.match(edge, /Nothing changed: still send one stock so the last part runs the archive step/);
  // The snapshot is still recorded from every line before rows are sent.
  assert.ok(edge.indexOf("'revolution_upload_snapshot_763'") < edge.indexOf('const sendRows = await changedRows782'));
});

test('edge source has no \\uXXXX escapes other than \\u0000 (the MCP deploy decodes them)', () => {
  for (const name of ['index.ts', 'parse.js', 'service_rows.js']) {
    const text = fs.readFileSync(dir + name, 'utf8');
    const hits = (text.match(/\\u[0-9a-fA-F]{4}/g) || []).filter((hit) => hit !== '\\u0000');
    assert.deepStrictEqual(hits, [], name);
  }
});
