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
path reproduced a further follower collision. That separate repair was installed
at 05:32 Perth on 27 October after the additional copied tests described below;
the hours-save release alone did not establish that category changes were fixed.
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

Installed at **23:18 Perth**, migration **20261026151839**, after combined
acceptance/source-hour/manual/completed-work tests and unchanged results for all
8,817 old routes and 557 uncached vehicle projections. Fresh live readback matched
all three tested function hashes, unchanged permissions and the expected resolver
pin (241 total). No backlog retry or existing-row migration was performed.
See `import-external-routing-20261026.md` for the exact policy and proof.
Deployment and inverse hold the same scheduling locks as acceptance, in one
transaction, and refuse contention. Reversal also refuses once receipt-backed
work exists, preserving accepted decisions until a reviewed forward repair.

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
  fixtures. That was a test setup limitation, not a demonstrated Finance defect.
  Its fixture now creates disposable administrator/viewer identities instead of
  selecting and demoting existing staff. The unchanged save/totals/replay/stale/
  permissions/public-record preservation assertions passed in phase11.
- A long Windows private-log path prevented one result from being recorded. That
  attempt remains BLOCKED; shorter separately labelled reruns provide the evidence.

## Release and final results

The hours repair is versioned in PR #536, merged as
`ee08259153a9ad0e887239a6187fbdc3543d94f7`. Both PR workflows passed;
the suite reported 2,846 PASS, 0 FAIL and 3 SKIP (2,849 total).

At 22:55 Perth, actual signed-in browser navigation rendered the QC queue,
Control Board (46 bays, 345 bookings), Department 138 Mechanical (bays 01–04),
and Electrical (bays 08–09). The existing idle session initially displayed
Connection lost and recovered after reload; its cause was not established.
No tick, estimate or booking was changed. No console error was captured during
the recovered Control Board read.

At 23:00, all 98 live read-only fault-register checks passed. At 23:05, the
published public monitor passed nine entries, nine legacy redirects, eight
assets, three signed-out denials and 155 focused regressions. Neither result
establishes the newly found category path or actual browser writes.

The final coherent copied run completed at **00:40 Perth on 27 October**:
**33 PASS, 0 FAIL**, comprising all original 24 and nine added estimate/growth
groups. A separate positive Bus closing-time supplement passed at 00:45, making
34 registered recurring groups. This is one 33-group run plus one focused group,
not a single 34-group run. Both processes exited zero and cleanup passed.

The new running-category/fitter-growth repair is installed as migration
`20261026213222`. It plans affected followers before persisting root growth,
preserves genuine running/stopped/resource conflicts, and records system-trigger
changes without inventing a staff actor. Exact installed hashes, permissions and
check metadata passed readback. All **103 current live read-only fault checks
passed at 05:32 Perth**. See [the detailed repair record](RUNNING-GROWTH-CASCADE-20261026.md)
for endpoint/helper distinctions, preservation assertions and inverse proof.

The raw initial 19/24 result and every later failed or blocked attempt remain
recorded. One broad attempt was blocked before assertions because a new backup
already contained the earlier releases. The successful retry used that backup
directly and verified 24 exact baseline definitions, then the candidate hashes.
Its standard fingerprint receipt remained incomplete for three required entries;
the explicit baseline/candidate evidence is separate, not an invented raw PASS.

A real signed-in browser search found a separate linked-job-card label defect:
matching used linked identities while rendering used only an empty primary field.
PR538 fixed and versioned both dynamic planner loads and their loader. Actual
published browser readback showed both linked cards; search selection, Enter,
drawer open/close and clear passed. At 00:33 the public monitor again passed all
nine entries, nine redirects, eight assets, three signed-out denials and 155
focused regressions. Main PR538 CI passed 2,849 tests with zero failures and three
skips. Current release CI is recorded separately with its final commit receipt.

Six concurrent main releases landed during an expired deployment request.
Fresh comparison confirmed 23 of the 24 sampled definitions unchanged and only
the intended running helper changed; all concurrent edits and pins were retained.
This record does not claim every possible new or future path is error-free.
Full actual-browser movement/save/dragging proof remains unavailable without an
isolated API/auth bridge. Storage contents and actual external delivery were not
tested. No live customer job was used as a test fixture.

## Rollback

Each proposed function repair has a guarded inverse beside its up script under
`supabase/proposals/`. Rollback restores only the exact reviewed function version
and refuses unexpected drift. It must not restore a database backup or erase later
staff work. Restoring the old functions restores the documented defects. Test and
report changes can be reverted through a new Git commit; that does not alter data.
