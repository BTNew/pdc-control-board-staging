'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const SKIP_PREVIOUS = new Set(['for', 'on', 'before', 'after', 'grant', 'revoke', 'of']);

function scanSql(sql) {
  const text = String(sql).replace(/\r\n/g, '\n');
  const violations = [];
  let i = 0;
  let paren = 0;
  const frames = [];
  let word = '';
  let previousWord = '';
  let pendingVerb = null;

  function closeFrames(nextParen) {
    while (frames.length && frames[frames.length - 1].depth > nextParen) {
      const frame = frames.pop();
      if (!frame.hasWhere) violations.push(text.slice(frame.start, i));
    }
  }

  function considerToken(token) {
    if (pendingVerb) {
      const verb = pendingVerb;
      pendingVerb = null;
      // CREATE TRIGGER ... UPDATE ON/OF/OR is an event, not a statement.
      if (token !== 'on' && token !== 'of' && token !== 'or') {
        frames.push(verb);
      }
    }
    if ((token === 'delete' || token === 'update') && !SKIP_PREVIOUS.has(previousWord)) {
      pendingVerb = { depth: paren, hasWhere: false, start: i - word.length };
    } else if (token === 'where' && frames.length && frames[frames.length - 1].depth === paren) {
      frames[frames.length - 1].hasWhere = true;
    }
    previousWord = token;
  }

  function finishWord() {
    if (!word) return;
    considerToken(word.toLowerCase());
    word = '';
  }

  while (i < text.length) {
    const c = text[i];
    const next = text[i + 1];
    if (c === '-' && next === '-') {
      finishWord();
      i += 2;
      while (i < text.length && text[i] !== '\n') i += 1;
      continue;
    }
    if (c === '/' && next === '*') {
      finishWord();
      i += 2;
      while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) i += 1;
      i += 2;
      continue;
    }
    if (c === "'") {
      finishWord();
      const escapeString = i > 0 && (text[i - 1] === 'E' || text[i - 1] === 'e')
        && (i < 2 || !/[A-Za-z0-9_]/.test(text[i - 2]));
      i += 1;
      while (i < text.length) {
        if (escapeString && text[i] === '\\') { i += 2; continue; }
        if (text[i] === "'" && text[i + 1] === "'") { i += 2; continue; }
        if (text[i] === "'") { i += 1; break; }
        i += 1;
      }
      continue;
    }
    if (c === '"') {
      finishWord();
      i += 1;
      while (i < text.length) {
        if (text[i] === '"' && text[i + 1] === '"') { i += 2; continue; }
        if (text[i] === '"') { i += 1; break; }
        i += 1;
      }
      continue;
    }
    if (c === '$') {
      const tag = text.slice(i).match(/^\$[A-Za-z0-9_]*\$/);
      if (tag) {
        finishWord();
        const end = text.indexOf(tag[0], i + tag[0].length);
        if (end < 0) break;
        const inner = text.slice(i + tag[0].length, end);
        for (const violation of scanSql(inner)) violations.push(violation);
        i = end + tag[0].length;
        continue;
      }
    }
    if (c === '(') {
      finishWord();
      paren += 1;
      i += 1;
      continue;
    }
    if (c === ')') {
      finishWord();
      paren -= 1;
      closeFrames(paren);
      i += 1;
      continue;
    }
    if (c === ';') {
      finishWord();
      if (pendingVerb) {
        frames.push(pendingVerb);
        pendingVerb = null;
      }
      closeFrames(-1);
      i += 1;
      continue;
    }
    if (/[A-Za-z0-9_]/.test(c)) {
      word += c;
      i += 1;
      continue;
    }
    finishWord();
    i += 1;
  }
  finishWord();
  if (pendingVerb) {
    frames.push(pendingVerb);
    pendingVerb = null;
  }
  closeFrames(-1);
  return violations.map(statement => statement.replace(/\s+/g, ' ').trim()).filter(Boolean);
}

function violationId(statement) {
  return crypto.createHash('sha256').update(statement).digest('hex');
}

function lintMigrationFiles(root) {
  const dir = path.join(root, 'supabase', 'migrations');
  const files = fs.readdirSync(dir).filter(name => name.endsWith('.sql')).sort();
  const found = {};
  for (const name of files) {
    const rel = path.join('supabase', 'migrations', name);
    const statements = scanSql(fs.readFileSync(path.join(root, rel), 'utf8'));
    if (!statements.length) continue;
    found[rel] = statements.map(statement => ({
      id: violationId(statement),
      statement: statement.slice(0, 180),
    }));
  }
  return found;
}

function versionOf(file) {
  const match = file.match(/(?:^|\/)(\d+)_/);
  return match ? match[1] : '';
}

function idsFor(found) {
  const out = {};
  for (const [file, items] of Object.entries(found)) {
    out[file] = items.map(item => item.id).sort();
  }
  return out;
}

function compareBaseline(found, baseline) {
  const errors = [];
  const locked = String(baseline.locked_through_version || '');
  const listed = baseline.violations || {};
  const actual = idsFor(found);
  const files = new Set([...Object.keys(actual), ...Object.keys(listed)]);
  for (const file of files) {
    const got = actual[file] || [];
    const expected = [...(listed[file] || [])].sort();
    if (got.join() !== expected.join()) {
      const sample = (found[file] || []).find(item => !expected.includes(item.id));
      errors.push(sample
        ? `${file} has a DELETE or UPDATE without a WHERE clause: ${sample.statement.slice(0, 160)}`
        : `${file} safeupdate baseline does not match the bare DELETE and UPDATE statements in the file`);
    }
    if (got.length && versionOf(file) > locked) {
      errors.push(`${file} is newer than ${locked} and still has a DELETE or UPDATE without a WHERE clause`);
    }
  }
  return errors;
}

module.exports = {
  scanSql,
  violationId,
  lintMigrationFiles,
  compareBaseline,
  versionOf,
};
