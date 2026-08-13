'use strict';

// npm pack otherwise includes arbitrary non-ignored untracked files. Refuse to
// build from a Git worktree unless every package input is committed. Exact Git
// archives contain committed files only and therefore need no ambient checkout.
const { spawnSync } = require('child_process');

const probe = spawnSync('git', ['rev-parse', '--is-inside-work-tree'], { encoding: 'utf8' });
if (probe.status === 0 && probe.stdout.trim() === 'true') {
  const status = spawnSync('git', ['status', '--porcelain=v1', '--untracked-files=all', '--ignored=matching'], { encoding: 'utf8' });
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
}
console.log('NPM_PACK_INPUTS_TRACKED_ONLY_PASS');