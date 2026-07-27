'use strict';

const assert = require('node:assert/strict');
const {
  buildAiIntakeReviewSummary,
  normalizeAiIntakeDecision,
} = require('./pdc-ai-intake-review.js');

{
  const result = buildAiIntakeReviewSummary({
    summary: '  Customer requests a bull bar, UHF and tint.\nETA to Kewdale is 20/08/2026.  ',
  });
  assert.equal(result.available, true);
  assert.equal(result.approvalReady, true);
  assert.equal(result.text, 'Customer requests a bull bar, UHF and tint. ETA to Kewdale is 20/08/2026.');
  assert.equal(result.warning, '');
}

{
  const result = buildAiIntakeReviewSummary({
    subject: 'RE: New vehicle order for 13044227 - PMG Build',
    stock_number: '13044227',
  });
  assert.equal(result.available, false);
  assert.equal(result.approvalReady, false);
  assert.match(result.text, /No email summary is available/i);
  assert.match(result.warning, /Do not approve/i);
}

{
  const result = buildAiIntakeReviewSummary({ summary: '<script>alert(1)</script>' });
  assert.equal(result.text, '<script>alert(1)</script>', 'helper returns text; the overlay must assign it through textContent');
}

for (const value of ['apply', 'Apply', 'APPLY', ' apply ']) {
  assert.equal(normalizeAiIntakeDecision(value), 'apply', `${JSON.stringify(value)} must receive the approval gate`);
}
assert.equal(normalizeAiIntakeDecision('reject'), 'reject');

console.log('AI Intake summary unit tests passed');
