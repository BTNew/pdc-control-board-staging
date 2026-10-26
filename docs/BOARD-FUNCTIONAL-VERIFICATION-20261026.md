# Board movements, saves and checks — 26 October 2026

Craig asked whether every board movement, save and check had been double-checked.
The optimisation release's 2,846 passing code tests and signed-in read/navigation
checks did not establish all browser mutations. This follow-up records that gap
explicitly and reruns the available database workflows against a fresh owned copy.

Only the working staging project `cdsmnqxtyyoeoznmbidd` is in scope. Production,
customer bookings, source hours, completed work, Parts business rules and existing
automation settings are preserved. Private evidence is outside Git under
`work/functional-monitor-private/board-functional-verification-20261026T1327Z`.

## Baseline and evidence boundaries

The public build was `b-2d5f226b5102a8722942`, commit `64ae19f8805b`.
The latest broad historical workflow evidence was 19 October, before later rule
changes. A new restore used the verified encrypted backup completed on 26 October
at 18:18 Perth. Sixteen checked public function fingerprints matched current live
definitions; two additional estimate endpoints were checked separately. This is
scoped function parity, not a claim that every restored object matches live.

The original, unchanged 24-group run produced **19 PASS and 5 FAIL**. The original
logs remain intact. Fresh estimate checks separately found a passing cross-station
batch save and a failing running-job estimate save. Copied jobs were disabled,
outbound-capable extensions excluded, scenarios rolled back and each owned test
server stopped with generated passwords, plaintext data and scratch files removed.

SQL tests are not actual browser dragging. The existing local runner has no
browser/API bridge. Its old report incorrectly blamed the browser connection;
signed-in read-only browser inspection works, and the report now names the missing
isolated bridge accurately. No live customer job substitutes for a test fixture.

## Verified findings

### Reopened: running estimate save and cascade

The earlier `running-estimate-cascade-20261019` fault was reopened. A newer hours
trigger attempted to extend a running booking immediately while endpoint 407 had
explicitly deferred reconciliation until all hours were written. The planned
follower had not moved yet. Guarded error-only instrumentation in the disposable
copy exposed `22023 / bay_overlap`; the working function was not instrumented.

A separate warm-projection case revealed that the duration reconciler could read
old cached hours before the later cache-invalidation trigger ran. The immediate
extension then encountered the same unmoved follower. These are distinct ordering
paths, so an endpoint-only repair is insufficient.

The guarded repair honours the existing exact `407` deferral contract and
evicts only the affected OLD/NEW vehicle projection cache rows before ordinary
duration reconciliation. Existing invalidation epochs, calendars, lifecycle and
collision protections stay in place. No trigger is renamed. Native verification
includes allowed growth, forward followers, retained actual starts and bayless
reservations, genuine started/stopped conflicts, replay, stale versions, source
minimums, warm reads, and exact inverse/metadata preservation.

**Installed at 22:28 Perth**, migration `20261026142832`. Live readback confirmed
trigger definition `1b2c507e05f0247bec9d41446e2cb5eb` and duration reconciler
`ef3116918cfb1d1c44cc45ef6e425bab`, unchanged owner/ACL/configuration and 241 pins.
The cold save/protection suite and exact inverse passed. The complete warm case,
including the actual dealer-scoped running batch-save endpoint, passed at 22:21.
All these tests used synthetic work in the disposable copy.

Station reassignment into a running job invokes a separate direct helper. That
path reproduced a further follower collision and remains a separate open repair;
the hours-save release does not establish that category changes are fixed.
Both Hoist and Bus Mechanical reproduce that separate category failure. Current
installed client source opens the Vehicle Locations drawer and saves through
batch 768; the retired planner popup does not dispatch endpoint 407. This installed
load-chain inspection is code evidence, not browser-save proof.

### Automatic external additions use inconsistent routing authorities

An uploaded Pit/Weigh addition could receive the legacy station from its proposal
while the canonical projection used the owner's current Sublet rule. Acceptance
then correctly rejected inconsistent readback. Existing AI/dictionary precedence
also needs preservation checks; changing a global resolver could affect existing
read projections. The repair is verified separately from test expectation changes.

### Outdated verification fixtures

- Fitter and category completion fixtures skipped item Start, although r440
  requires Start before Done. Positive paths now start items and read fresh state;
  negative checks explicitly retain the required rejection, unchanged progress,
  version protection, exact retry and current other-station rules.
- The Best slot fixture required an old cascade bug to remain reproducible before
  checking Best slot. It now exercises the real free-slot save directly, retaining
  exact assertions that following jobs and other stations do not move.
- Pit/Weigh expectations used `BUS_PIT` despite the later Sublet rule. Expectations
  follow the current owner-approved classification, preserving manual choices,
  source hours and completed work.
- A category fixture's anonymous-access check used a retired function identity;
  it now checks the actual installed signature, without changing access rules.
- The Finance group could not initialize because it depends on existing staff
  fixtures. That is a test setup limitation, not a demonstrated Finance defect.
- A long Windows private-log path prevented one result from being recorded. That
  attempt remains BLOCKED; shorter separately labelled reruns provide the evidence.

## Release and final results

Verification remains in progress for category reassignment and automatic external
additions. The hours-save repair above is installed and has scoped proof. Its
private release receipt and the per-run index retain the original failures,
corrected fixtures, current passes and cleanup independently. Full browser
movement/save/dragging proof remains unavailable without an isolated API bridge.

## Rollback

Each proposed function repair has a guarded inverse beside its up script under
`supabase/proposals/`. Rollback restores only the exact reviewed function version
and refuses unexpected drift. It must not restore a database backup or erase later
staff work. Restoring the old functions restores the documented defects. Test and
report changes can be reverted through a new Git commit; that does not alter data.
