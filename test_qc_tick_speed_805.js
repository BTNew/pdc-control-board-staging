'use strict';
// r805 (F420, Craig 1 Nov 19:20): Final check ticks show at once; one board reload after the last tick.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const app = fs.readFileSync('app.js', 'utf8');
test('r805: no per-tick triple snapshot reload; one debounced sync; queued tick shown', () => {
  const start = app.indexOf('async function qcPageSetOperationState(');
  const body = app.slice(start, app.indexOf('\nfunction qcPageScheduleSync(', start));
  assert.ok(!/qcPageAwaitOperationSnapshot\(key, lineIdentity, checked, 3/.test(body), 'success path no longer reloads three times');
  assert.match(body, /qcPageScheduleSync\(authority\)/);
  assert.match(app, /function qcPageScheduleSync\(authority = capturePdcWriteAuthority\(\)\) \{[\s\S]*?2500\);/);
  assert.match(app, /const shownDone = pending \? pending\.checked === true : line\.completed;/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /^\| F420 \|/m);
});
