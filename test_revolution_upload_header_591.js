const assert = require('node:assert/strict');
const { test } = require('node:test');
const { revolutionUploadParts } = require('./pdc-revolution-upload.js');

const UNICODE_NAME = 'PMG PD Service as a Whole w/Sublet – 28‑10‑2026 · copy.xlsx';

test('a unicode report name stays in the form body and out of the request headers', () => {
  const file = new File(['<table></table>'], UNICODE_NAME, { type: 'application/vnd.ms-excel' });
  assert.throws(() => new Request('http://127.0.0.1/revolution-upload', {
    method: 'POST',
    headers: { 'x-filename': UNICODE_NAME },
  }));
  const { form, headers } = revolutionUploadParts(file, 'latin1-token');
  assert.equal(headers['x-filename'], undefined);
  assert.equal(headers['x-uploader'], undefined);
  assert.equal(headers.Authorization, 'Bearer latin1-token');
  assert.equal([...form.values()][0].name, UNICODE_NAME);
  assert.doesNotThrow(() => new Request('http://127.0.0.1/revolution-upload', {
    method: 'POST',
    body: form,
    headers,
  }));
  const refused = revolutionUploadParts(file, 'staff – name');
  assert.equal(refused.headers.Authorization, undefined);
});
