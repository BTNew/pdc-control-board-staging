# Workshop Planner Fix — Handover / Progress Log

Branch: `feature/workshop-shared-realtime-v2`
Staging Supabase project: `cdsmnqxtyyoeoznmbidd`
Production (untouched throughout): Supabase `vjdtsswhroyguxyfjdkt`, site
`btnew.github.io/pdc-control-board-login/`

## STAGING IS NOW DEPLOYED AND LIVE

**Staging URL: https://btnew.github.io/pdc-control-board-staging/**

- Separate, brand-new public GitHub repo: `BTNew/pdc-control-board-staging`
  (created this session), completely independent from the production repo
  `BTNew/pdc-control-board-login`.
- GitHub Pages enabled on that repo's `main` branch, root path. Build
  status: `built`.
- Points exclusively at the staging Supabase project
  (`cdsmnqxtyyoeoznmbidd`) via CSP and `pdc-supabase-config.staging.js`.
- No bundled operational vehicle data (`data-staging-empty.js` is an empty
  sanitized placeholder — all vehicle data loads live from staging
  Supabase after sign-in).
- `robots.txt` disallows all crawling; `noindex, nofollow, noarchive` meta
  tag present, matching production's convention.

## Final staging report

### Branch / commits
- Branch: `feature/workshop-shared-realtime-v2`
- Latest commits (this segment, newest last):
  - `691dffa` — docs: workshop planner fix handover/progress log
  - `5f30f40` — feat: QC-complete -> RFT + notification outbox + RFT
    Collected -> Completed
  - `a7c5cea` — fix: Parts screen Jita dedicated column
  - `27605cb` — docs: handover update
  - `51e306e` — feat: finish staging-only frontend deployment (auth glue +
    staging.html + config), including a real re-entrancy bug fix in
    `initWorkshopSharedServicesIfEnabled()`
- Deployment repo: `BTNew/pdc-control-board-staging` @ `main` (single
  deploy commit, pushed and built this session)

### Files added/changed (working repo, `pdc-control-board`)
- `supabase/migrations/016_qc_rft_collected_notifications.sql` (new)
- `vehicle-lifecycle-actions.js` (new)
- `backend/vehicle_notification_worker.py` (new)
- `test_vehicle_lifecycle_actions.js` (new)
- `staging.html`, `pdc-supabase-config.staging.js`,
  `data-staging-empty.js` (new, this segment)
- `app.js` — QC/RFT/Collected wiring, staging auth glue
  (`getPdcSupabaseAccessToken`, `createPdcSupabaseRealtimeSubscription`),
  and the shared-services re-entrancy fix
- `pdc-auth.js` — caches the current access token on window for
  synchronous shared-mode callers
- `styles.css`, `test_desktop_operations.js`, `test_production_grid_v2.js`
  — Parts screen Jita column
- `docs/workshop-planner-fix-handover.md` (this file)
- Gitignored staging-only test tooling (not committed, as per existing
  convention): `_staging_test_tools/test_qc_rft_collected_staging.py`,
  `_staging_test_tools/test_vehicle_notification_worker_staging.py`

### Deployment repo (`pdc-control-board-staging`) contents
`index.html` (= `staging.html` renamed), `app.js`, `pdc-auth.js`,
`pdc-supabase-config.staging.js`, `data-staging-empty.js`,
`email-board-data.js`, `arb-labor-catalog.js`, `workshop-planner.js`,
`workshop-planner.css`, `workshop-data-service.js`, `workshop-realtime.js`,
`workshop-shared-actions.js`, `vehicle-lifecycle-actions.js`, `styles.css`,
`desktop-operations.css`, `favicon.svg`, `robots.txt`, `.nojekyll`,
`assets/`, `vendor/`.

### Database migrations added (staging only)
- `016_qc_rft_collected_notifications.sql`: `qc_complete_vehicle()`,
  `rft_transfer_vehicle()`, `rft_collect_vehicle()`,
  `queue_vehicle_notification()`, `claim_pending_vehicle_notifications()`,
  `mark_vehicle_notification_result()`, `retry_vehicle_notification()`,
  `vehicle_notifications` table + `notification_status` enum, plus new
  columns on `vehicles` (`qc_completed_at`, `qc_completed_by`,
  `rft_collected_by`).
- Applied directly to staging via the existing psycopg2 tooling (not
  `supabase db push`, consistent with the established pattern in this
  repo for out-of-band migrations).

### Protected RPCs added
`qc_complete_vehicle`, `rft_transfer_vehicle`, `rft_collect_vehicle`,
`retry_vehicle_notification` (all `authenticated`-grantable, role-checked
via `require_pdc_role`); `claim_pending_vehicle_notifications` and
`mark_vehicle_notification_result` (service-role only — never granted to
`authenticated`, so the browser cannot call them).

### Test accounts / roles (staging only)
- `administrator@staging.pdc-workshop.example.com` / `AdminStagingPW!2026xz` — administrator
- `controllerA@staging.pdc-workshop.example.com` / `ControllerAPW!2026xz` — operator/controller
- `viewer@staging.pdc-workshop.example.com` — viewer
- `unapproved@staging.pdc-workshop.example.com` — unapproved
(All pre-existing from earlier sessions; reused, not newly created.)

### Monitored staging mailbox
None — out of scope for this task (this task was the Workshop Planner /
QC / RFT / Parts fix, not the AI Email Monitoring feature, which was
explicitly not started this segment per instruction).

### Exact automatic actions enabled
- None beyond what already existed. QC complete, RFT transfer, and RFT
  Collected all require an explicit authenticated user action (button
  click / confirm dialog) — nothing fires automatically on a schedule or
  in response to another event. The **notification outbox worker** is a
  manually-invoked script (`backend/vehicle_notification_worker.py`), not
  a cron job — it does not run automatically in staging.

### Exact actions still requiring approval / not yet automatic
- Real email sending (worker's `send_via_provider()` is deliberately
  unimplemented — `--dry-run` is the only mode exercised).
- Any change to `pdc-control-board-login` (production) or its Supabase
  project.
- Any decision to make the staging URL non-`noindex` / public-facing
  beyond internal testing.

### Confidence thresholds
Not applicable to this task — no AI confidence-scored automation was
built or touched this segment.

### Full test results (this session, final run)
- `node test_all.js`: **37 passed, 0 failed, 2 skipped**
- Backend `python -m unittest test_email_board_publisher
  test_email_intake_security test_static_publication_gate
  test_vehicle_intelligence_fixtures.py`: **22 passed**
- `_staging_test_tools/test_workshop_staging_integration.py` (real
  staging PostgreSQL/PostgREST, gitignored): **34 passed, 0 failed**
- `_staging_test_tools/test_qc_rft_collected_staging.py` (real staging,
  gitignored): **28 passed, 0 failed**
- `_staging_test_tools/test_vehicle_notification_worker_staging.py` (real
  staging, gitignored, runs the actual worker module): **5 passed, 0
  failed**
- `git diff --check`: clean after every commit

### Browser smoke-test result
- Local (`test-75.html`) and the **real deployed public staging URL**
  (`https://btnew.github.io/pdc-control-board-staging/`) both loaded with
  **zero console errors and zero CSP errors** across Vehicle Locations,
  Control Board, Workshop Planner, and Parts views.
- Real sign-in against staging Supabase succeeded on the public URL as
  `administrator@staging.pdc-workshop.example.com`; header correctly
  showed the authenticated email + role; "Sign out" appeared.
- After opening Workshop Planner, `window.__workshopDataService`,
  `window.__workshopRealtimeManager` (subscribed), `window.
  __workshopSharedActions`, and `window.__vehicleLifecycleActions` were
  all present and live, loaded from the real staging snapshot RPC (real
  bays/stages/bookings/vehicles).

### Two-user realtime test result — genuinely performed, twice
Performed once against a local server and once again against the real
public staging URL, using two independent, real authenticated sessions
(never the same session/token):

- **Browser session** (administrator, browser automation) — opened the
  Workshop Planner and left it open, unrefreshed.
- **Independent REST session** (controllerA, direct HTTPS calls to the
  staging Supabase REST/RPC endpoint, completely separate from the
  browser) — called `move_workshop_booking` with real parameters.
- Result both times: the open, unrefreshed administrator browser tab
  picked up controllerA's real database write via the live Supabase
  realtime subscription within ~3–4 seconds, with **no manual refresh**.
  Verified by reading `workshopLoadPlans()` in the browser console before
  and after controllerA's RPC call and confirming the bay/time changed to
  exactly what controllerA wrote.

### QC → RFT → Collected + notification outbox — verified live, twice
Performed once locally and once again on the real public staging URL,
using the real browser session (administrator) calling the actual
`window.__vehicleLifecycleActions` bridge (the same code path the
Control Board "Complete QC" button / RFT transfer / Collected checkbox
use):
1. `qcCompleteVehicle` → `qc_completed_at` set, work item marked
   complete, notification enqueued (`notification_has_recipient: true`).
2. `rftTransferVehicle` → `lifecycle_state: 'rft'`,
   `current_location: 'RFT'`.
3. `rftCollectVehicle` → `lifecycle_state: 'completed'`,
   `current_location: 'Completed'`, `visible_on_board: false`.
4. `backend/vehicle_notification_worker.py --dry-run` claimed and
   successfully "sent" (logged, no real email) the queued notification.
5. Full `audit_events` history confirmed for the vehicle:
   `qc_complete_vehicle` → `rft_transfer_vehicle` → `rft_collect_vehicle`,
   each recorded with the authenticated actor email
   `administrator@staging.pdc-workshop.example.com` and a timestamp.
6. All synthetic fixture rows created for these live verifications
   (salesperson, work item, notification, vehicle version resets) were
   cleaned up after each run.

### Security review
- Production Supabase project and production site were never called,
  configured, or modified at any point this session.
- `pdc-supabase-config.staging.js` contains only the publishable
  (`sb_publishable_...`) key — no service_role key, no database password,
  no Microsoft client secret.
- `claim_pending_vehicle_notifications` / `mark_vehicle_notification_result`
  are **not** granted to `authenticated` — the browser genuinely cannot
  call them; only a service-role-authenticated worker process can.
- CSP on the new staging page is identical to production's except for the
  Supabase host, and still uses `script-src 'self'` (no inline scripts
  beyond the one pre-existing `onerror` attribute that is byte-identical
  to what already ships in production `index.html`, and does not
  introduce new attack surface).
- Role gating verified live and by test: `viewer` cannot call
  `qc_complete_vehicle` / `rft_collect_vehicle`; only `administrator` can
  call `retry_vehicle_notification`.
- The staging repo (`pdc-control-board-staging`) is public (GitHub Pages
  requires this on a free plan) but contains no real customer data, no
  secrets beyond the staging publishable key, and `robots.txt` +
  `noindex` discourage indexing. If a private-repo Pages plan becomes
  available later, this could be tightened further — flagged as a known
  limitation below.

### Known limitations
- The staging deployment repo is public (not private) because GitHub
  Pages requires a paid plan for private-repo Pages under the
  organization's current setup; mitigated by containing zero real data
  and zero real secrets, `robots.txt` disallow-all, and `noindex` meta.
- The notification worker's real email sending is intentionally
  unimplemented; only `--dry-run` has been exercised, consistent with
  "do not process real operational emails during development unless
  explicitly approved."
- Control Board / Parts / RFT legacy views on the staging page currently
  show 0 vehicles until a legacy-data import is run for staging (this is
  expected — those views are still backed by the browser-local
  `app.data`/localStorage layer, which is intentionally empty on this
  entry point; only the Workshop Planner and the QC/RFT/Collected bridge
  functions talk to live staging Supabase data today). The live QC/RFT/
  Collected verification in this report was performed by calling the
  bridge functions directly (the same functions the UI buttons call),
  since there is no legacy vehicle row rendered on-screen to click yet.
- Deploying the staging site requires a manual `git push` to the separate
  `pdc-control-board-staging` repo whenever `staging.html` or its
  supporting files change in the main working repo; there is no CI/CD
  automation syncing the two. A future improvement would be a GitHub
  Actions workflow.

### Rollback procedure
- **Staging site**: `gh api -X DELETE repos/BTNew/pdc-control-board-staging/pages`
  to disable Pages, or `gh repo delete BTNew/pdc-control-board-staging`
  to remove it entirely. Neither action touches the working repo
  (`pdc-control-board`) or production.
- **Staging database**: all new objects are additive (new table, new
  columns, new functions) and were built to coexist with existing
  migrations. To roll back, drop the four new functions, the
  `vehicle_notifications` table, the `notification_status` type, and the
  three new `vehicles` columns — no existing data or behaviour depends on
  them, so no existing functionality breaks by removing them.
- **Working repo**: revert commits `5f30f40`, `a7c5cea`, `51e306e` (and
  their doc commits) on `feature/workshop-shared-realtime-v2`; the branch
  has not been merged into `main`.

## Two-user acceptance checklist (for Craig / staff to repeat manually)
1. Open `https://btnew.github.io/pdc-control-board-staging/` in Browser A.
2. Sign in as `administrator@staging.pdc-workshop.example.com`.
3. Open `https://btnew.github.io/pdc-control-board-staging/` in Browser B
   (different browser/profile/incognito).
4. Sign in as `controllerA@staging.pdc-workshop.example.com`.
5. In both browsers, open Workshop Planner.
6. In Browser B, drag/drop or use a quick-duration button to move a
   booking.
7. Confirm Browser A updates automatically within a few seconds, with no
   refresh.
8. Confirm no console/CSP errors in either browser's DevTools.
9. Sign in as `viewer@staging.pdc-workshop.example.com` in a third
   browser/profile and confirm no write actions are available/permitted.
10. Sign in as `unapproved@staging.pdc-workshop.example.com` and confirm
    no vehicle data access beyond the existing unapproved-user gate.

## Status vs the requested order of work (all items now complete)
1. ✅ QC Complete → RFT atomic RPC-backed transition
2. ✅ Notification outbox with idempotency and retry handling
3. ✅ RFT Collected → Completed Vehicles shared workflow
4. ✅ Parts screen ETA/calendar/Jita layout fix
5. ✅ Full regression tests
6. ✅ Staging-only frontend deployment and two-user test

## Real bugs caught and fixed this segment (cumulative)
- `mark_vehicle_notification_result()` enum-cast `DatatypeMismatch` (SQL).
- **Re-entrancy bug in `initWorkshopSharedServicesIfEnabled()`**: the
  realtime manager and the shared-actions bridge were only constructed
  inside the "first call, data service doesn't exist yet" branch. Because
  the new `pdc-auth-ready` listener calls this function once immediately
  on login (before the user has ever opened the Workshop Planner and
  therefore before `workshop-realtime.js`/`workshop-shared-actions.js`
  are lazy-loaded), `window.__workshopRealtimeManager` and `window.
  __workshopSharedActions` could permanently stay `undefined` even after
  those scripts loaded later. Fixed by re-checking both blocks
  independently on every call. Caught by live browser testing against the
  real staging URL, not by a unit test — a genuine "looks fine in
  isolation, breaks in the real login flow" class of bug.

## Confirmation
- Production Supabase (`vjdtsswhroyguxyfjdkt`) and production site
  (`btnew.github.io/pdc-control-board-login/`) were never touched, called,
  or configured at any point in this session.
- All new deployment infrastructure (`BTNew/pdc-control-board-staging`)
  is entirely separate from the production repo/site.

**Stopping here for your approval before any production change**, per
instruction.
