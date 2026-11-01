'use strict';
// r807b / r807c (F423): the email readers no longer require RFT'd; the context reads the checkable lines.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r807b/c migrations', () => {
  const b = fs.readFileSync('supabase/migrations/20261101203000_r807b_email_before_rft_readers.sql', 'utf8');
  assert.match(b, /read_rft_transport_booking_context_739\(uuid\)/);
  assert.match(b, /read_rft_transport_draft_739\(uuid\)/);
  assert.match(b, /prosrc LIKE '%rft_confirmation_required%'/);
  const c = fs.readFileSync('supabase/migrations/20261101204000_r807c_email_context_checkable_lines.sql', 'utf8');
  assert.match(c, /pdc_qc_checkable_operation_lines_10700/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /^\| F423b \|/m);
});
