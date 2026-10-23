/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r515 (F129): internal same-tenant Outlook parts-complete. SQL preview. Not applied.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');

const ID = '20261023170000_r515_outlook_internal_parts_auth';
const MIG = `supabase/migrations/${ID}.sql`;
const DOWN = `supabase/rollbacks/${ID}.down.sql`;
const up = fs.readFileSync(MIG, 'utf8');
const down = fs.readFileSync(DOWN, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const notes = fs.readFileSync('release_log/r515/NOTES', 'utf8');
const r514 = fs.readFileSync('supabase/migrations/20261023140000_r514_outlook_parts_completion.sql', 'utf8');
const PERSON = '8ddb1477beeb94c7879c4021cccf1d40';
const OLD_PERSON = 'eb02f76ec94cd0b6c824a18660432afa';
const MARK = 'f5bdb212b439fd37adb73860c5e5d4d3';
const AR = 'mx.microsoft.com 1; dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=pmgwa.com.au;';
const MSG = '<SY1P282MB63556EA203EA75E467DCAC23AC642@SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM>';
const SHA = 'c94f7ca4357c95113dbfcb15cd93cb21d24d9714ad99056cbaaf59bfcdda8656';

function between(text, tag) {
  const start = text.indexOf(tag);
  const end = text.indexOf(tag, start + tag.length);
  return text.slice(start + tag.length, end);
}

test('migration files are LF only and do not name production', () => {
  assert.equal(up.includes('\r') || down.includes('\r'), false);
  assert.equal(up.includes('vjdtsswhroyguxyfjdkt') || down.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(up.slice(0, 400).includes('Specialise Pty Ltd'), false);
  assert.equal(down.slice(0, 400).includes('Specialise Pty Ltd'), false);
  const listed = fs.readFileSync('release_log/r515/PATCH_MD5S', 'utf8').trim().split('\n');
  for (const line of listed) {
    const [sum, file] = line.split(/\s+/);
    const got = crypto.createHash('md5').update(fs.readFileSync(file)).digest('hex');
    assert.equal(got, sum, file);
  }
});

test('staging guard, r514 tip, and no service_role grant', () => {
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /NOT BETWEEN 2 AND 45/);
  assert.match(up, /^SET LOCAL lock_timeout = '2s';$/m);
  assert.match(up, /expected 225 pins at tip/);
  assert.match(down, /pin count is not 225/);
  assert.equal(/CREATE OR REPLACE FUNCTION public\.is_pdc_role/.test(up), false);
  assert.equal(/CREATE OR REPLACE FUNCTION public\.record_pdc_wayne_parts_complete_20260912/.test(up), false);
  assert.equal(/CREATE OR REPLACE FUNCTION public\.mark_pdc_parts_complete/.test(up), false);
  assert.equal(/CREATE OR REPLACE FUNCTION public\.mark_pdc_parts_complete/.test(down), false);
  assert.equal(/INSERT INTO pdc_ops\.expected_function_md5/.test(up), false);
  assert.equal(/UPDATE pdc_ops\.expected_function_md5/.test(up), false);
  assert.equal(/ALTER TABLE/.test(up), false);
  assert.equal(/karratha135/.test(up.replace(/--[^\n]*/g, '')) > 0, true);
  assert.equal(/GRANT EXECUTE ON FUNCTION public\.record_pdc_person_parts_complete_20260913[\s\S]*service_role/.test(up), false);
  assert.equal(/GRANT EXECUTE ON FUNCTION public\.mark_pdc_parts_complete/.test(up), false);
  assert.match(up, /REVOKE ALL ON FUNCTION public\.record_pdc_person_parts_complete_20260913\(text,text,timestamptz,text,text,text,jsonb\) FROM PUBLIC, anon, authenticated, service_role;/);
});

test('person prosrc changes and the Gmail assignment stays the r514 text', () => {
  assert.equal(crypto.createHash('md5').update(between(up, '$person515$')).digest('hex'), PERSON);
  assert.equal(crypto.createHash('md5').update(between(r514, '$person514$')).digest('hex'), OLD_PERSON);
  const gmail = ` gmail_ok:=p_authentication->>'mailbox'='pmbcontroller@gmail.com'
  AND coalesce(p_gmail_message_id,'') ~ '^[a-f0-9]{10,40}$'
  AND p_authentication->>'to_address'='pmbcontroller@gmail.com'
  AND p_authentication->>'verified_by'='gmail_receiving_provider'
  AND authenticated_sender;`;
  assert.equal(between(up, '$person515$').includes(gmail), true);
  assert.equal(between(r514, '$person514$').includes(gmail), true);
  assert.match(up, /external_ok OR internal_ok/);
  assert.match(up, /domain='pmgwa.com.au'/);
  assert.match(down, new RegExp(OLD_PERSON));
  assert.match(down, new RegExp(MARK));
  assert.match(up, new RegExp(MARK));
  assert.equal(down.includes(PERSON), true);
});

test('documents the internal AuthAs keys and the real Authentication-Results', () => {
  for (const key of ['auth_as', 'x_ms_exchange_organization_authas', 'auth_source', 'x_ms_exchange_organization_authsource']) {
    assert.equal(up.includes(key), true, key);
    assert.equal(notes.includes(key), true, key);
  }
  assert.equal(up.includes(AR), true);
  assert.equal(up.includes(MSG), true);
  assert.equal(up.includes(SHA), true);
  assert.equal(notes.includes('"auth_as": "Internal"'), true);
  assert.equal(notes.includes(AR), true);
  assert.match(up, /do not invent Authentication-Results/i);
});

test('regression check outlook_internal_parts_auth_515 sort 302 F129 re-pins r514', () => {
  assert.match(up, /outlook_internal_parts_auth_515','F129'/);
  assert.match(up, /,302,'r515'\)/);
  assert.match(up, /d876e9bd42a929e659c811c0c9e6c2ec/);
  assert.match(up, /ece98352be4126d5fd4ad2707157cae2/);
  assert.match(up, /replace\(check_sql, 'eb02f76ec94cd0b6c824a18660432afa', '8ddb1477beeb94c7879c4021cccf1d40'\)/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='outlook_internal_parts_auth_515'/);
  assert.match(down, /DROP TABLE pdc_ops\.r515_person_parts_prev/);
  assert.match(log, /\| F129 \|/);
  assert.equal(log.includes(MSG), true);
  assert.equal(log.includes('IS60353006'), true);
  assert.match(log, /\| F128 \|/);
});
