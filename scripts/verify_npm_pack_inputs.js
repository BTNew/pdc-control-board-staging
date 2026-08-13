'use strict';

// npm pack otherwise includes arbitrary non-ignored untracked files. Refuse to
// build from a Git worktree unless every package input is committed and its raw
// worktree bytes exactly match the staged Git blob. Git status alone can report
// a CRLF-transformed Windows checkout as clean while npm ships different bytes.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function runGit(args, options = {}) {
  return spawnSync('git', args, {
    encoding: options.encoding || 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
}

function packageInputFiles() {
  const manifest = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  const inputs = new Set(['README.md', 'package.json']);
  for (const entry of manifest.files || []) {
    const probe = runGit(['ls-files', '-z', '--', entry], { encoding: 'buffer' });
    if (probe.status !== 0) throw new Error(`unable to enumerate package input: ${entry}`);
    for (const raw of probe.stdout.toString('utf8').split('\0').filter(Boolean)) inputs.add(raw);
  }
  return [...inputs].sort();
}

const probe = runGit(['rev-parse', '--is-inside-work-tree']);
if (probe.status === 0 && probe.stdout.trim() === 'true') {
  const status = runGit(['status', '--porcelain=v1', '--untracked-files=all', '--ignored=matching']);
  if (status.status !== 0) {
    console.error('NPM_PACK_INPUTS_BLOCKED: unable to verify Git worktree state');
    process.exit(1);
  }
  const residue = status.stdout.split(/\r?\n/).filter(Boolean);
  if (residue.length) {
    console.error('NPM_PACK_INPUTS_BLOCKED: package inputs must come from a clean committed tree');
    for (const line of residue.slice(0, 20)) console.error(line);
    if (residue.length > 20) console.error(`... ${residue.length - 20} more path(s)`);
    process.exit(1);
  }

  const mismatches = [];
  try {
    for (const file of packageInputFiles()) {
      const index = runGit(['show', `:${file}`], { encoding: 'buffer' });
      if (index.status !== 0 || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
        mismatches.push(file);
        continue;
      }
      if (!fs.readFileSync(path.resolve(file)).equals(index.stdout)) mismatches.push(file);
    }
  } catch (error) {
    console.error(`NPM_PACK_INPUTS_BLOCKED: ${error.message}`);
    process.exit(1);
  }
  if (mismatches.length) {
    console.error('NPM_PACK_INPUTS_BLOCKED: package worktree bytes differ from committed Git blobs');
    for (const file of mismatches.slice(0, 20)) console.error(file);
    if (mismatches.length > 20) console.error(`... ${mismatches.length - 20} more path(s)`);
    process.exit(1);
  }
}
console.log('NPM_PACK_INPUTS_EXACT_GIT_BYTES_PASS');
