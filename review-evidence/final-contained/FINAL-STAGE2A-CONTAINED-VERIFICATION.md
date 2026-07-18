# Final contained Stage 2A verification

Date: 2026-07-18

## Identity and safety

- Source branch: `fix/stage2a-independent-review-findings`
- Final source HEAD: recorded after the final documentation commit in
  `FINAL-SOURCE-HEAD.txt` and `REVIEW-MANIFEST.json` in the ZIP.
- Staging deployment commit:
  `505c524915d9a567078d08f73dfd63229f178d06`
- Staging URL: <https://btnew.github.io/pdc-control-board-staging/>
- Linked database project during migration: `cdsmnqxtyyoeoznmbidd` only.
- Production project `vjdtsswhroyguxyfjdkt` was never linked, queried,
  migrated, deployed, or contacted by browser acceptance.
- No merge occurred. Stage 2B, AI, Admin planner blocks, current-time feature
  work, unrelated planner redesign, and production deployment were not started.

## Migration 026

`026_stage2a_final_review_remediation.sql` was applied to staging after an
explicit link guard and an encrypted pre-change backup.

- Pre-change encrypted backup: 136,248 bytes.
- SHA-256:
  `0efd1479219a0d74f473c4fb7de5d1f3034864a60f1b752d928c498ec4650e79`.
- Local/remote migration ledgers: aligned through 026.
- Post-apply dry run: `Remote database is up to date.`
- Migration 026 staging role/validation/leave checks: **24 passed, 0 failed**.
- Synthetic cleanup: zero test technicians, salespeople, providers, bays,
  bookings, and leave rows remained.

Migration 026 replaces broad direct-read policies on technicians, salespeople,
sublet providers, and bays. Viewers see active rows only through list RPC,
direct REST, and Realtime RLS; operator/administrator hierarchy retains
inactive-row reads; unapproved/disabled/rejected accounts have no approved role
and read none. Direct writes remain revoked.

Configuration validation checks UUID text before casting and accepts dates only
when they match exact `YYYY-MM-DD` syntax and round-trip unchanged. Failures are
structured JSON. Protected create/reassignment RPCs return
`technician_on_leave` before creating a new assignment.

## Planner model and behavior

The planner now has one authoritative configuration adapter containing integer
minutes and validated collections. `07:30` is stored as `450`; no fractional
clock hour is passed to `Date.setHours` or a Date constructor.
`workshopSetClock()` is the single clock application helper.

Focused tests exercise actual date/scheduling outcomes for:

- exact 07:30–15:30 and 08:15–16:45 boundaries;
- normalize, drag/drop, minute addition, day end, and segment rendering;
- closure skip/block and historical rendering;
- break split/non-bookable behavior;
- configured overtime acceptance and outside-window rejection;
- technician leave rejection;
- three-day and six-day planner columns;
- stale/loading configuration fail-closed behavior.

## Test totals

### Cross-platform CI

GitHub Actions run: <https://github.com/BTNew/pdc-control-board/actions/runs/29625298853>

Each of Windows, Ubuntu, and macOS passed:

- JavaScript aggregate: **39 passed, 0 failed, 2 skipped**;
- exact documented backend command: **54 passed, 0 failed**;
- planner focused test and reference-data service command: passed.

The backend command imported `vehicle_order_email_monitor.py` successfully on
all three platforms. Windows exercised `msvcrt`; Ubuntu/macOS exercised
`fcntl`. Native lock serialization/release tests passed.

### Local credential-free

- JavaScript aggregate: **39 passed, 0 failed, 2 skipped**.
- Reference-data service internal assertions: **44 passed, 0 failed**.
- Exact backend module set: **54 passed, 0 failed**.
- Backup retention: **7 passed, 0 failed**.
- Scheduled backup logging: **3 passed, 0 failed**.
- Syntax/compile and `git diff --check`: passed.

### Staging

- Migration 026 direct REST/RPC matrix: **24 passed, 0 failed**.
- Reference-data live suite: **33 passed, 0 failed** (one no-existing-booking
  historical case was explicitly reported as a passing skip).
- Workshop live integration: **34 passed, 0 failed**.
- Two-browser actual planner acceptance: **passed**.

## Two-browser actual planner acceptance

Two independently authenticated browser contexts were used. The administrator:

1. changed `day_start_time` to `07:30`;
2. Browser B observed the Realtime update and rendered the first planner axis at
   `7:30 am`;
3. added synthetic closure `2099-01-05`;
4. Browser B rendered Monday 05/01 as `CLOSED`, with no droppable lane;
5. restored closures and day start to the exact original values;
6. Browser B observed both restorations.

Final browser diagnostics:

- console errors: 0;
- CSP errors: 0;
- page errors: 0;
- failed requests: 0;
- HTTP errors: 0;
- production requests: 0;
- contacted hosts: `btnew.github.io`,
  `cdsmnqxtyyoeoznmbidd.supabase.co` only.

Machine-readable result:
`review-evidence/final-contained/two-browser-planner-acceptance.json`.

## Deployment verification

GitHub Pages reported deployment commit
`505c524915d9a567078d08f73dfd63229f178d06` as built. Live `index.html`,
`app.js`, `workshop-planner.js`, and `workshop-planner.css` each returned HTTP
200 and matched the corresponding deployment Git blob byte-for-byte.

## Clean-build availability

The account contained only the staging and production projects. Production was
prohibited, and staging was the reviewed target; therefore no free isolated
Supabase project was available for a new 001–026 clean build. Docker was not
available locally. The previously completed isolated 001–025 clean build
remains valid evidence for those immutable migrations. Migration 026 was
instead verified by linked dry run, real staging application, ledger parity,
static regression, direct REST role matrix, strict validation checks, and
protected RPC leave enforcement. This limitation is stated rather than
substituting a production or staging reset.
