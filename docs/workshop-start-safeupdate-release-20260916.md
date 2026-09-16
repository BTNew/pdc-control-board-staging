# Workshop Start safeupdate repair — 16 September 2026

Start job failed through the website with HTTP400 / SQLSTATE21000, “UPDATE requires a WHERE clause.” The PostgREST authenticated role preloads safeupdate; the SQL management connection does not. Earlier SQL-only tests therefore missed this connection-specific failure.

## Repair

Staging migration `20260916074828_workshop_start_safeupdate_initialization` initializes `current_start` and `current_end` directly in the temporary plan INSERT, using the same scheduled-start and effective-end values. This removes the subsequent unqualified UPDATE. The migration checks the exact previous function definition and staging environment before replacing it.

The repair changes no role grants, database safeguards, RLS, priority scheduling rules, calendar settings or persistent vehicle records. Existing clock-version handling and the one-hour vehicle handover remain intact.

Migration SHA256: `86ffbe6407d5f20ea7699cdb9469fe05714cb0feaee585b6d77e8688f707e27f`.

## Verification

- Reproduced the exact rejection through real Auth/PostgREST HTTP before applying the migration; an explicit temporary-table probe confirmed safeupdate was active.
- After deployment, the real HTTP connection passed all33 workflow assertions, including fitter-only Start, timer running, weighted item completion at50% and100%, item notes, refusal to finish outstanding work, stoppage reason, paused timer, duplicate-request replay, resume preserving the original start, completed actual-end and stopped timer, plus direct workshop-controller Start and planner state reads.
- Priority Start moved conflicting unstarted bookings while retaining the one-hour handover. Existing assignments, audit records and unrelated operational rows were preserved.
- All fixtures ran inside a forced-rollback subtransaction. Before/after checks confirmed operational booking, assignment, revision, audit and receipt state was restored. The temporary HTTP probe and test account were removed and its session revoked.
- 47 additional SQL-session assertions passed across clock-rebase guards and priority/fitter authorization. These checks are supplementary; they are not evidence that safeupdate was loaded.
- 945 JavaScript regression checks passed on the local repair base. Publication uses the latest main tree, retaining the concurrent administrator-only User Management update; CI checks that combined tree.
- Security advisor counts remain at the existing baseline:495 RLS-without-policy informational findings,1 public-extension finding,1 anonymous security-definer finding,483 authenticated security-definer findings and1 leaked-password-protection finding. This repair adds none.
- Independent review found no release blockers.

## Repeatable regression

`tests/workshop_start_safeupdate_rollback.sql` deliberately fails before creating fixtures when safeupdate is not enforced. Run it only through a suitable isolated test connection with that safeguard active. It ends in ROLLBACK and does not commit test jobs.

`test_workshop_start_safeupdate.js` verifies the three guarded definition replacements, identical initial values, qualified remaining temporary-table updates and retained authority boundaries.

These are transaction and website-connection checks. No claim is made that a physical iPad touch session was exercised during this repair.
