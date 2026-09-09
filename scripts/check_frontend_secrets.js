'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

function findPrivilegedTokens(text) {
  const findings = [];
  for (const match of text.matchAll(/\bsb_secret_[A-Za-z0-9_-]{16,}\b/g)) {
    findings.push({ index: match.index, kind: 'Supabase privileged secret key' });
  }
  for (const match of text.matchAll(/\beyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g)) {
    try {
      const claims = JSON.parse(Buffer.from(match[0].split('.')[1], 'base64url').toString('utf8'));
      if (claims.role === 'service_role') findings.push({ index: match.index, kind: 'Supabase privileged JWT' });
    } catch (_error) {
      // An arbitrary dotted string is not necessarily a JWT.
    }
  }
  return findings;
}

function isFrontendSource(name) {
  const normalized = name.replace(/\\/g, '/');
  const basename = path.posix.basename(normalized);
  return /\.(?:js|mjs|cjs|html)$/i.test(normalized)
    && !/(?:^|\/)(?:tests?|fixtures)(?:\/|$)/i.test(normalized)
    && !/^(?:test_|test-)/i.test(basename)
    && !/\.(?:test|spec)\.[cm]?js$/i.test(basename);
}

function scanFrontend(root) {
  // A failed Git/file read throws. Scanner errors must never be interpreted as clean.
  const names = execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 })
    .split('\0').filter(isFrontendSource);
  if (names.length === 0) throw new Error('No tracked frontend files were scanned');
  const findings = [];
  for (const name of names) {
    const filename = path.resolve(root, name);
    if (!filename.startsWith(path.resolve(root) + path.sep)) throw new Error('Tracked path escaped repository');
    if (!fs.lstatSync(filename).isFile()) throw new Error(`Frontend source is not a regular file: ${name}`);
    const text = fs.readFileSync(filename, 'utf8');
    for (const finding of findPrivilegedTokens(text)) {
      findings.push({ file: name, line: text.slice(0, finding.index).split('\n').length, kind: finding.kind });
    }
  }
  return { scannedFiles: names.length, findings };
}

if (require.main === module) {
  try {
    const result = scanFrontend(process.cwd());
    for (const finding of result.findings) console.error(`${finding.file}:${finding.line}: ${finding.kind} detected; value redacted`);
    console.log(`Frontend secret scan: ${result.scannedFiles} tracked files; ${result.findings.length} findings`);
    process.exitCode = result.findings.length ? 1 : 0;
  } catch (error) {
    console.error(`Frontend secret scan failed: ${error.message}`);
    process.exitCode = 2;
  }
}

module.exports = { findPrivilegedTokens, isFrontendSource, scanFrontend };
