# Running work growth and forward cascade

## Status

Installed on staging at **05:32 Perth, 27 October 2026**, migration
`20261026213222` (`running_growth_forward_cascade_20261026`). The installed
definitions match the tested candidate. Actual browser write/dragging proof
remains unavailable; this is a database repair with separately stated evidence.

## Observed fault and verified cause

Adding work to an existing running or stopped Hoist/Bus reservation could fail
with `bay_overlap` instead of extending the job and pushing later planned work
forward. The actual `set_vehicle_work_category` endpoint reproduced this in the
disposable copy for both Hoist and Bus Mechanical.

The r538 helper `workshop_extend_running_booking_538` updated the running row
before its planned follower moved. Immediate overlap validation correctly
rejected that intermediate state. The independently released hours/cache repair
does not cover this separate helper used by category changes and fitter extra
work; passing an ordinary estimate save was therefore insufficient evidence.

## Repair scope

The helper keeps its existing calculation of authoritative station work plus
accepted fitter work from another station. Instead of extending one row first,
it delegates to a private explicit-root cascade derived from the existing full
estimate planner. The existing estimate planner and shared validators are not
changed.

- Keep the running/stopped root's scheduled start, actual start and lifecycle.
- Preserve allocated duration floors; reductions do not shorten running work.
- Use each Bus reservation's bay calendar and the established PMB calendar.
- Plan forward through bay, vehicle and technician dependencies, including
  secondary technicians and the one-hour vehicle handover.
- Save downstream reservations first so immediate constraints remain enabled.
- Retain assignment identities, source hours, completed work and audit history.
- Reject genuine started/stopped conflicts, Admin blocks, leave and Sublet-away
  conflicts. A failed change rolls back atomically.
- Canonical returns to Unallocated release technician assignments. Their bayless
  history reserves no capacity and remains unchanged. The central technician
  conflict helper and physical exclusion constraint remain intact.

The new routine is an ungranted private invoker function. The existing public
helper retains its owner, permissions and configuration. Deployment changes
only those definitions and the exact r538 regression-check text; it does not
retry operational requests or move existing staff bookings.

## Background actor handling

A copied management test exposed two additional candidate boundaries: booking
`updated_by` and workshop-history `actor_user_id` require a named user. A system
connection has no `auth.uid()`. The final candidate preserves each row's existing
named updater and records full before/after snapshots through the existing
generic audit function with a NULL actor and explicit `actor_kind=system`.
Named staff still use the existing workshop-history path. No user is invented,
no constraint is weakened, and the general audit/history functions are unchanged.

## Verification and evidence distinctions

The first focused copied run passed four actual category saves (Hoist and Bus,
started and stoppage), canonical released-history preservation and exact inverse
checks. Its direct management probe failed; that failure remains recorded.
The second run passed protected/resource/multi-hop checks and both inverses after
successful work. Hoist fitter extra/replay passed; the later Bus setup used the
wrong calendar and failed before reaching its growth assertion. The actual
management trigger reached the named-history constraint. Those attempts are not
relabeled as whole-group passes.

The final coherent run passed **33/33 groups**: all original 24, two estimate
cases and seven growth cases. A separate supplemental group passed positive Bus
closing-time rollover: Mechanical and Electrical through the actual category
setter; whole-job through the explicitly private planner, followed by the public
helper's no-shrink retry. This is 33 broad groups plus one focused group, not one
34-group run. Recurring coverage now registers all 34. All fixtures require the owned loopback
database, preserve copied operational records, finish with rollback and use the
reviewed restore helper with copied jobs and external delivery disabled.

The runner now compares schema, function name and arguments. Missing required
fingerprints or changed restored definitions are BLOCKED. Bounded per-function
reads avoid the restore helper's output truncation limit. Scheduled checks never
install candidate definitions. Pre-release candidate injection, live baseline
parity and candidate hashes are separately labelled in private review evidence.

None of these SQL transactions proves actual browser dragging or browser saves.
Live browser navigation/search and source-level client tests remain separately
reported. Parts business rules and external provider delivery are outside this
repair.

## Deployment and reversal

Use only the complete `running_growth_cascade_20261026.up.sql` transaction under
`supabase/proposals/`. It requires the authorized staging sentinel and trusted
management connection, refuses production, checks exact dependency/source hashes,
and takes the clock then top-level mutation locks without waiting on contention.
Metadata, grants, pins and the registered check are verified before commit.

The paired `.down.sql` restores the exact old helper and check before removing
the exact private function, without CASCADE. It refuses source/metadata drift,
unexpected callers or new pins. It never restores a database backup and does not
undo later saved booking, assignment or history rows. Reversal restores the old
future extension defect; use it only as a considered code rollback.

## Final release evidence

The installed private engine full-definition hash is
`a53b5d76a81b6a42aef826d8d433170f`; public helper hash is
`876704abdee272bb2724cb640c895c33`. Readback at 05:32 Perth confirmed both,
unchanged public-helper metadata and registered-check metadata, no external
grants on the private invoker, and 241 function pins. The deployment transaction
verified its exact pin-table preservation. All **103 live read-only fault checks
passed**.

The initial deployment request expired without applying: catalog and migration
readback confirmed that before an exact retry succeeded. Six concurrent releases
landed during that delay. A fresh comparison of all 24 baseline functions found
23 unchanged definitions and only the intended helper change; concurrent pin
updates were preserved. This does not establish every untested concurrent path.

Both successful copied runs exited zero and cleaned up their server, plaintext
data, scratch directory and generated password. The earlier broad attempt is
retained as 33 BLOCKED before assertions: a new backup already contained released
repairs, and their second-application guards correctly refused. The retry used
that backup directly with exact 24-function baseline parity before candidate
installation. The raw receipt's missing three required fingerprint entries
remain BLOCKED; separate explicit baseline and candidate guards provide the
qualified proof. No old report was relabeled as a clean version check.

Unused and used-after-success Hoist/Bus inverses passed in separate rollback
transactions. Actual browser writes, Storage contents, outbound delivery and
provider integrations remain outside this evidence. Private source receipts,
per-attempt failures and release readbacks are retained outside Git.
