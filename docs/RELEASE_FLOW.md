# Release flow (staging)

Staging project `cdsmnqxtyyoeoznmbidd` only. Production is never touched by a release agent.

1. **Read-only first.** List the affected keys and save the exact old function definitions
   (`md5(prosrc)`, ACL, owner) for every function the release changes.
2. **Rolled-back test.** Run the migration inside one transaction on synthetic or Dept 139 data,
   check before/after, run the undo, then `RAISE` and roll back. No Delete/Complete, no live jobs
   as fixtures. **Use the test window below.**
3. **Before snapshot** (`md5_before_apply.txt`), then **apply** with `apply_migration` a few
   seconds after a clock tick.
4. **Pins.** Any pinned function changed is re-pinned in `pdc_ops.expected_function_md5` in the
   same migration. Every UPDATE/DELETE (including `ON CONFLICT DO UPDATE`) has a WHERE clause
   (`scripts/lint_migration_safeupdate_dml.js`).
5. **Undo.** `supabase/rollbacks/<version>_<name>.down.sql` asserts the new md5s, restores the old
   definitions exactly and asserts the old md5s and ACLs.
6. **Post-checks, one at a time** (never in parallel with the apply): protected md5s, QC cache
   0 mismatches, clock ticks, `pdc_ops.fault_regression_check()` (clear `request.jwt.claims`
   first).
7. **Repo.** Migration + rollback + tests + `docs/FAULT_LOG.md` row (Craig's rule: root cause,
   fix, FAULT_LOG entry, regression check). Patch built on current `origin/main`.

## Rolled-back test window (F15, r405)

Board write functions take the top-level change lock
`pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0))` and keep it until
the test's `ROLLBACK`. The live clock tick (`staging-workshop-clock-cascade`, every minute at
:00, about 0.5 s) waits only 3 s for that lock. r404's rolled-back tests held it across minute
boundaries and the real tick failed at 21:25, 21:28 and 21:30 AWST on 20 Oct 2026.

Every rolled-back test that calls board write functions starts with
`scripts/rolled_back_test_window.sql` (replace `@TAG@` with the release tag):

- **Wait for the tick.** A lock-free loop waits until this minute's tick has finished and the
  clock is at :02–:15. It gives up after 75 s (`@TAG@_WINDOW`).
- **Short lock waits.** `SET LOCAL lock_timeout = '2s'`: the test never queues behind live work.
- **Deadline at :50.** Call `pg_temp.deadline()` before each step. It stops the test
  (`@TAG@_DEADLINE`, everything rolled back) when less than 1 s is left, and cuts each
  statement's `statement_timeout` to the time left, so the lock is always released before the
  next tick.
- **Report.** `pg_temp.window_report()` shows start/end (AWST) and `same_minute`; it must be true.
- Keep slow read-only work (e.g. the 9 s `fault_regression_check()`) out of the test; run it as a
  post-check.

Why this option: a short `lock_timeout` alone protects the test but not the tick (the test can
still be holding the lock at :00). Waiting for the tick plus a hard deadline protects the tick
whatever the test does.

## Proposed tick guard (not applied)

`workshop_clock_tick` is pinned and runs every minute, so this is a proposal only. Replace the
blocking `pg_advisory_xact_lock` + 3 s `lock_timeout` with `pg_try_advisory_xact_lock`, retry
once after a short `pg_sleep` (e.g. 1 s), and if still locked record `skipped_locked` and return
without error; the next minute catches up. Before applying: confirm the tick is idempotent and
catches up after a skipped minute, and that `clock_ticks_recent` counts a skip as a skip, not a
failure. Needs Craig's approval and a re-pin.
