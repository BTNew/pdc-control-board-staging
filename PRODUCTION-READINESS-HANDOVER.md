# PDC Control Board — Production Readiness Handover

**Status: staging-only. Production has not been touched. Stop for explicit approval before any production cutover step.**

## 1. Project state

- **Branch:** `feature/workshop-shared-realtime-v2`
- **Latest feature-branch commits (this phase):**
  - `450a8cf` — individual account registration + administrator approval workflow (migration 018, RPCs, frontend, tests)
  - `83831a1` — production-readiness assessment, artifact builder, realtime for account approvals (migration 019, cutover plan)
  - *(this commit, pushed at the end of this session)* — final version bump to `2026.07.17.03-account-approval`, staging redeployment record, and this handover document
- **Staging deployment repo:** `BTNew/pdc-control-board-staging`, branch `main`
- **Staging deployment commit:** `f258ae9` — "Deploy: account registration, administrator approval, realtime User Management (v2026.07.17.03-account-approval)"
- **Staging URL:** `https://btnew.github.io/pdc-control-board-staging/`
- **Staging deployed version (confirmed live):** `2026.07.17.03-account-approval`
- **Production repository:** `BTNew/pdc-control-board-login`, branch `main`
- **Production commit (unchanged throughout this phase):** `04b6237c665dcada0cdab9183de04f9712445047`
- **Production confirmation:** No production Supabase migration, RPC, config, DNS, GitHub Pages setting, or file was changed at any point in this phase. Every mutating action in this session (migrations, `supabase config push`, test-account creation/deletion, realtime publication changes) was executed only against the staging Supabase project `cdsmnqxtyyoeoznmbidd`, verified via `cat supabase/.temp/project-ref` immediately before and after every CLI call that could affect a linked project.

## 2. Account registration

- **Signup:** real `auth.users` signup via the staging anon key, handled by a dedicated staging-only module `pdc-auth-registration.js` (never loaded by `index.html`/production — only by `staging.html`). This keeps the existing production safety test (`test_microsoft_auth.js`, which asserts `pdc-auth.js` never contains `.signUp(`) passing unmodified.
- **Fields collected:** full name, work email, password, confirm password. Client-side validation requires password/confirm match and a minimum-12-character policy matching the real staging Auth password policy pushed this session (`lower_upper_letters_digits_symbols`).
- **Email confirmation:** required before sign-in (`enable_confirmations = true` on staging); verified — an unconfirmed account gets `400 email_not_confirmed` on login attempt.
- **Pending-account behaviour:** the `handle_new_pdc_auth_user()` trigger on `auth.users` automatically creates a `pdc_user_roles` row with `account_status='pending'`, `role=NULL`, `active=false` on every real signup — proven with a real signup in this session and in the prior session's staging integration test file.
- **Awaiting Approval screen:** displays exactly `"Your account has been created and is awaiting administrator approval."` — confirmed live on the deployed staging URL via a real signup → confirm → sign-in flow (screenshot-equivalent evidence: `browser_vision` capture in this session showed the exact required text).
- **No anonymous access:** `enable_anonymous_sign_ins = false` on staging (matches production).
- **Forgot Password:** real `resetPasswordForEmail` flow; verified via UI (`Reset your password` screen renders, "Send reset link" call succeeds with the real staging Auth API) and via the `admin/generate_link` diagnostic endpoint.
- **Password reset:** the reset landing flow (`PASSWORD_RECOVERY` auth event → dedicated "set new password" form) reuses the existing `pdc-auth.js` password-update code path, unchanged from before this phase, now reachable via the Forgot Password screen.
- **Profile creation:** a `pdc_user_roles` row is the account's profile; no separate profile table was introduced, following the existing schema.

## 3. Account-status and role model

- **Account status** (lifecycle, kept separate from role): `pending`, `approved`, `disabled`, `rejected` — a dedicated Postgres enum `pdc_account_status`, not conflated with the operational role.
- **Role** (nullable until approved): `viewer`, `operator` (labelled "controller" in the UI), `administrator`. `role` is `NULL` for every pending and rejected account — a rejected account can never regain a role without a fresh `admin_approve_user` call.
- Both fields live on the pre-existing `pdc_user_roles` table (migration 018 adds the new columns via `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`, idempotent, staging-verified by re-running the full migration file twice with no errors).

## 4. Administrator User Management

Screen: new "User Management" nav item and view, gated to shared-mode + administrator role at both the UI layer (`backupStatusSharedModeReady()`) and, non-negotiably, at the database layer (every RPC below independently re-checks `require_pdc_role('administrator')`).

- **Approve:** `admin_approve_user(p_target_email, p_role)` — sets `account_status='approved'`, `active=true`, the chosen role, `approved_by`, `approved_at`. Tested live via a real UI button click (previous session) and via independent REST calls (this session) — both produced the identical real database state.
- **Reject:** `admin_reject_registration(p_target_email, p_reason)` — sets `account_status='rejected'`, leaves `role=NULL` permanently.
- **Assign role / Change role:** `admin_change_role(p_target_email, p_role)` — used both for a pending user's initial role (via `admin_approve_user`'s `p_role` argument) and for changing an already-approved user's role later (verified live: viewer → controller/`operator`).
- **Disable:** `admin_disable_user(p_target_email, p_reason)` — sets `account_status='disabled'`, `active=false`. Verified live: the disabled account immediately received zero rows from `GET /rest/v1/vehicles` and a `403` on every mutating RPC, while `current_pdc_account_status()` correctly resolved to `"disabled"` for that account's own session.
- **Restore:** `admin_restore_user(p_target_email, p_reason)` — sets `account_status='approved'`, `active=true`, and returns the account's exact prior role (proven live: a controller who was disabled and restored came back as `operator`, not reset to `viewer`).
- **Realtime behaviour:** migration 019 adds `pdc_user_roles` to the `supabase_realtime` publication; the User Management screen opens a real Supabase Realtime channel (`pdc_user_roles_admin_view`) and auto-re-renders on any row change. **Proven with a genuine two-actor test** (this session, against the live deployed site): `administrator`'s browser tab sat open on the User Management screen with a channel in the `"joined"` state; `administrator2`'s entirely independent REST session approved a fresh pending user; `administrator`'s tab picked up the change in its in-memory state within ~3 seconds with zero console errors and no manual refresh.
- **Audit behaviour:** every one of the five RPCs above writes to `audit_events` with `action='role_change'`, the real acting administrator's email, the RPC name, and the target account's email in `metadata`. Verified with a direct SQL query against real rows produced by real RPC calls in both this and the prior session.
- **Last-administrator protection:** `admin_disable_user` and `admin_change_role` both refuse (`403`, message containing "last active administrator") to disable or demote the sole remaining active administrator. Proven with a real two-administrator recovery test: `administrator2` was temporarily disabled and restored via the real RPCs to safely exercise this path without permanently reducing staging to a single administrator account.

## 5. Security

- **Protected RPCs added (migration 018):** `admin_approve_user`, `admin_reject_registration`, `admin_change_role`, `admin_disable_user`, `admin_restore_user`, `record_pdc_login`, plus the internal helper `current_pdc_actor_role_id()` and the client-facing `current_pdc_account_status()`. All are `security definer` with `set search_path = public`, and all administrator-gated functions call `require_pdc_role('administrator')` as their first statement — the database, not the frontend, is the enforcement point.
- **RLS policy summary:** `pdc_user_roles` — a signed-in user may `select` only their own row (by email match against `auth.jwt()`); an administrator may `select` every row (via `is_pdc_role('administrator')` in the policy). All operational tables (`vehicles`, `workshop_bookings`, etc.) already required `is_pdc_role('operator')` or higher for writes and `is_pdc_role('viewer')` or higher for reads, per the pre-existing schema — the account-approval work does not weaken any existing policy, it only gates whether a given account ever reaches `active=true` in the first place. `audit_events` has a pre-existing `audit_events_select_approved` policy granting read access to `viewer` and above (including controllers) — this was already true before this phase and was confirmed, not changed.
- **Full role-access matrix — direct API test results (both real staging test files, run against the real staging REST/RPC API, not mocked):**

| Role/state | Read operational data | Write operational data | Call admin_* RPCs | Notes |
|---|---|---|---|---|
| Pending | 0 rows (`[]`) | `403` role required | `403` role required | Cannot self-approve; `current_pdc_account_status()` → `"pending"` |
| Disabled | 0 rows (`[]`) | `403` role required | `403` role required | `current_pdc_account_status()` → `"disabled"`; proven with disable→zero-rows→restore→rows-return cycle |
| Viewer | Real rows returned | `403` role required | `403` role required | Confirmed live: viewer sees real vehicle rows, write attempt correctly rejected |
| Controller (`operator`) | Real rows returned | Succeeds (not role-blocked) | `403` role required | Confirmed live: `schedule_vehicle_work` succeeds for a controller; `admin_approve_user`/`admin_disable_user`/`admin_change_role` all `403` |
| Administrator | Real rows returned | Succeeds | Succeeds | Can read every `pdc_user_roles` row (5+ confirmed), all `audit_events`, and call every admin RPC |

- **Confirmation no service-role key is exposed:** `pdc-supabase-config.staging.js` (committed, deployed) contains only the `publishableKey` (`sb_publishable_...`), never a `service_role`/`secret` key. The real staging service-role key used for test-account setup in this session lives only in the gitignored `_staging_test_tools/staging_rest.py` and was never written into any committed file, the deploy repo, or this document.

## 6. Authentication URLs

Pushed to **staging only** via `supabase config push --project-ref cdsmnqxtyyoeoznmbidd` (verified the CLI was linked to staging both immediately before and after every push, via `cat supabase/.temp/project-ref`):

- **Staging site URL (Auth config):** `https://btnew.github.io/pdc-control-board-staging/`
- **Allowed redirects:** `https://btnew.github.io/pdc-control-board-staging/`, `https://btnew.github.io/pdc-control-board-staging/index.html`, `http://127.0.0.1:8270/staging.html`, `http://localhost:8270/staging.html`
- **Signup-link result:** `redirect_to` resolves to the real staging URL when an allowed value is requested (confirmed via `admin/generate_link` with `type=signup`).
- **Recovery-link result:** same — resolves to the real staging URL (confirmed twice, once in the prior session and once against the freshly redeployed site in this session).
- **Magic-link result:** same — resolves to the real staging URL.
- **Rejected redirect tests:** `http://127.0.0.1:8270/staging.html` alone (without the exact configured path) and, critically, **`https://pdccontrolboard.com/` were both tested and correctly fell back to the configured `site_url` rather than being honoured** — proving an attacker (or a stale link) cannot redirect a staging auth flow to an arbitrary or production-looking domain.
- **Confirmation production Auth configuration was not changed:** the working repo's `supabase/config.toml` (which holds production's real `[auth]` values, including `site_url = "https://btnew.github.io/pdc-control-board-login/"` and `enable_signup = false`) was temporarily edited to staging values, pushed only to `--project-ref cdsmnqxtyyoeoznmbidd`, then restored byte-for-byte immediately afterward — confirmed via `git diff --stat supabase/config.toml` showing zero diff after restoration, both in the prior session and re-verified before writing this document.

## 7. Production artifact

- **Build command:** `python scripts/build_production_artifact.py`
- **Artifact path:** `_build/production-artifact/` (gitignored — never committed; `_build/` added to `.gitignore` this phase)
- **Excluded files (enforced in code, not just by omission):** `staging.html`, `pdc-supabase-config.staging.js`, `data-staging-empty.js`, `pdc-auth-registration.js`, anything under `_staging_test_tools/`, anything with `.staging.` in its path, `random-100-vehicles.csv` (flagged as a synthetic fixture per the brief, even though it is currently live on production — see §8), and any `.env*` file. The build script raises immediately if any of these ever appear in its file list.
- **Production Supabase reference:** confirmed present in `index.html`, `app.js`, and `pdc-supabase-config.js` (`vjdtsswhroyguxyfjdkt`).
- **Staging-reference scan result:** **PASS — zero occurrences of `cdsmnqxtyyoeoznmbidd`** anywhere in the built artifact (confirmed both by the script's own check and an independent `grep -rl` over the artifact directory). A real bug was found and fixed this phase: `app.js` had the staging project ref hardcoded as a string literal (used only to label the backup-status panel's environment); replaced with a `PRODUCTION_SUPABASE_PROJECT_REF` constant so only the production ref appears in the shipped file.
- **Secret scan result:** **PASS** — no `sb_secret_...` pattern, no real `service_role: <value>` assignment (the scan was refined this phase to distinguish an actual key/value assignment from `pdc-supabase-config.js`'s own safety comment that merely *mentions* the words "service_role" as a warning not to add one), no PEM private key, no AWS/SMTP credential pattern.
- **Confirmation staging files are excluded:** verified — `ls` of the built artifact contains no `staging.html`, no `*.staging.*` file, and no `_staging_test_tools` directory.

## 8. Read-only production assessment

All of the following were obtained via read-only GitHub API calls, DNS lookups, and public HTTP requests — **no production database connection was made, and no production credentials were created or used**, per the explicit constraint.

| Item | Finding |
|---|---|
| Production repository | `BTNew/pdc-control-board-login` |
| Production branch | `main` |
| Production commit | `04b6237c665dcada0cdab9183de04f9712445047` — "Deploy workshop planner drag target stabilization" (2026-07-16) |
| Live Pages status | `status: built`, live at `https://btnew.github.io/pdc-control-board-login/` (confirmed 200 OK) |
| HTTPS status | Enforced (`https_enforced: true`, HSTS header present, valid `*.github.io` wildcard certificate through 2026-09-02) |
| Pages publishing source | Repo `BTNew/pdc-control-board-login`, branch `main`, path `/`, `build_type: legacy` |
| Downloadable test/synthetic files | **`random-100-vehicles.csv` is currently live and publicly downloadable** via a "Download random 100-vehicle CSV" button inside the Back End Data admin panel of the live production `index.html`. It is not auto-loaded into the app, but is a synthetic 100-row fixture ("Random test vehicle 001", etc.) shipped in the public repo today. |
| Workshop features in production | **Not deployed.** Production's live `index.html` script tag list is exactly `vendor/supabase → pdc-supabase-config.js → pdc-auth.js → data.js → email-board-data.js → arb-labor-catalog.js → app.js`; there is no `workshop-planner.js`/`workshop-data-service.js`/`workshop-realtime.js`/`workshop-shared-actions.js`/`vehicle-lifecycle-actions.js` reference, and production's `pdc-supabase-config.js` has no `workshop.sharedData`/`vehicleLifecycle.sharedData` flags, so even the lazy-load code paths in `app.js` never fire there. |
| Account-approval features in production | **Not deployed.** Migrations 013–019 (legacy import, shared write-path, backup system, account approval, realtime) exist only on the staging Supabase project. Production's Supabase schema/migration version could not be directly queried (see below), but the frontend evidence above confirms none of the new UI or RPC-dependent code paths are reachable on the live production site today. |
| Production database inspection limitation | **Could not inspect production Postgres schema, migration version, `auth.users` accounts, or table row counts.** This requires a production database connection string/password, which does not exist anywhere in this working environment and was deliberately not created — creating new production credentials is itself outside the scope of a "read-only" assessment under the explicit "do not touch production" constraint. **This is the single largest open item before a safe cutover and must be the first action an operator with real production access takes, ahead of every other cutover step.** |
| Confirmation no production database changes were attempted | Confirmed — no connection string for `vjdtsswhroyguxyfjdkt` was ever obtained, requested, or used at any point in either the prior or this session. |
| `data.js` / `email-board-data.js` | Both confirmed already sanitized/empty on production (`vehicles: []`, `reviews: []`) — no embedded operational data to migrate out of these files. |
| localStorage on real staff browsers | Not remotely inspectable; would require direct access to a staff machine or an explicit export from the user. Not claimed to be empty or populated — genuinely unknown from this session. |
| Other GitHub Pages deployments on the account | Exactly two PDC-related Pages sites exist: `pdc-control-board-login` (production) and `pdc-control-board-staging` (this project's staging). One unrelated repo (`excellence-transfer`) also has Pages enabled but belongs to a different, unrelated project. No other PDC-related staging/test/preview/dev Pages deployments exist. |

### Domain finding

- **`pdccontrolboard.com` currently has no active DNS record.** Confirmed via `nslookup` for the bare domain and for `www.`, `staging.`, `test.`, and `dev.` subdomains — **none resolve**; all return `Non-existent domain`.
- GitHub Pages' own record for the production repo confirms this independently: `"cname": null` in the Pages API response.
- **The brief's assumption that this domain already exists as a "permanent bookmark" and must be "preserved" during cutover cannot be assumed complete — it does not exist today.** If the business wants this domain live, it must be registered and DNS-configured as a new setup task, not a preservation task.
- **No DNS changes were made during this phase.** This finding is reported, not acted upon.
- DNS and custom-domain setup (if wanted) must be handled as an explicit, separately-approved part of the production cutover — see the cutover plan's Step 9.

## 9. Migration and cutover plan

Full detail: `docs/production-migration-cutover-plan.md`. Summary of the sequenced steps (none executed against production):

1. **Production backup** — run the already-staging-proven `scripts/pdc_backup.py --environment production` (currently hard-refuses production; the guard is deliberately lifted only after this plan is approved) and verify it with an isolated-schema restore on production, exactly as already proven twice on staging.
2. **Current-site backup** — `gh api repos/BTNew/pdc-control-board-login/zipball/main`, saved outside the repo before any file changes.
3. **Database migrations** — apply, in order, every migration `001`–`019` not already present on production (production's exact current version is unknown — see §8's largest open item — so this step begins with establishing that baseline).
4. **Production administrator bootstrap** — one-time manual creation via the Supabase dashboard (never via public signup, never with a password stored in any file/commit/chat); a second administrator created immediately after, mirroring the two-administrator recovery pattern already proven on staging.
5. **Auth URL setup** — `supabase config push --project-ref vjdtsswhroyguxyfjdkt` with production's real final site URL (existing Pages URL or the new custom domain, once registered).
6. **Operational-data migration** — only if Step 3's baseline finds real rows in production's own `vehicles`/`workshop_bookings` tables (separate from the already-sanitized static JS files); otherwise a no-op.
7. **Domain decision** — a business decision, not assumed: register `pdccontrolboard.com` and wire up GitHub Pages custom-domain + DNS + certificate issuance, or continue using the existing `btnew.github.io/pdc-control-board-login/` URL indefinitely.
8. **GitHub Pages deployment** — push the already-built-and-validated clean artifact (`_build/production-artifact/`) to `BTNew/pdc-control-board-login` `main`. This is the only step that changes the live site's content.
9. **Removal of publicly exposed synthetic files** — decide whether to remove `random-100-vehicles.csv` and its download button, or intentionally retain the sample-import convenience feature.
10. **Public test-site cleanup** — decide whether `pdc-control-board-staging` remains public (recommended: yes, clearly labelled staging-only) or is made private/archived.
11. **Live verification** — reproduce this session's full staging verification checklist against the live production URL post-deployment.
12. **Rollback** — re-deploy the Step 2 ZIP, reverse any Step 3 migration via a short manual down-migration, restore the Step 1 backup into an isolated schema first (full `public` restore only as a last resort, requiring separate explicit approval), and revert the Step 5 Auth config using the pre-change values.

## 10. Testing — complete results

| Suite | Result |
|---|---|
| JavaScript (`node test_all.js`) | **37 passed, 0 failed, 2 skipped** — matches expected total exactly |
| Backend Python (`test_email_board_publisher`, `test_email_intake_security`, `test_static_publication_gate`, `test_vehicle_intelligence_fixtures`) | **22 passed, 0 failed** — matches expected total exactly |
| Staging PostgreSQL integration (`test_workshop_staging_integration.py`) | **34 passed, 0 failed** |
| Staging PostgreSQL integration (`test_qc_rft_collected_staging.py`) | **28 passed, 0 failed** |
| Staging PostgreSQL integration (`test_vehicle_notification_worker_staging.py`) | **5 passed, 0 failed** |
| Account approval lifecycle (`test_account_approval_staging.py`) | **10/10 real assertions passed** (signup trigger, unconfirmed-email block, pending zero-access, approve, viewer write-block, role change, disable/restore, last-administrator protection, rejection, audit trail) |
| Role-access matrix (`test_role_access_matrix_staging.py`) | **6/6 real assertions passed** (controller can act / cannot manage users / can read audit per pre-existing policy; viewer read-only; disabled full lockout; administrator full access) |
| **Staging PostgreSQL total** | **34 + 28 + 5 + 10 + 6 = 83 — matches expected total exactly** |
| Direct API security tests | Included in the two suites above — all run against the real staging REST/RPC API with real bearer tokens, never mocked |
| Browser smoke tests (live deployed staging URL) | Site loads, zero console errors, zero CSP errors, config connects only to `cdsmnqxtyyoeoznmbidd` — confirmed via direct inspection of `window.PDC_SUPABASE_CONFIG` |
| Two-user realtime test (live deployed staging URL) | **Passed** — `administrator`'s open browser tab (real "joined" Realtime channel) auto-updated within ~3 seconds when `administrator2`'s fully independent REST session approved a new account, with zero console errors |
| Console/CSP checks | Zero errors observed at every checkpoint: initial load, post-login, Create Account, Awaiting Approval, Forgot Password, User Management |
| Artifact validation (`scripts/build_production_artifact.py`) | **PASS** — zero staging references, zero secret patterns, production ref present, no staging Pages URL leakage |
| `git diff --check` | **Clean** (line-ending warnings only, no actual whitespace errors) |

### End-to-end workflow, verified live against the deployed staging site (not just locally)

1. Registered a new account (`pdc-live-e2e-test@gmail.com`) via the real staging Auth API.
2. Confirmed pending status: zero operational rows, `current_pdc_account_status()` → `"pending"`.
3. Signed in via the live deployed browser session; confirmed the exact "awaiting administrator approval" screen text.
4. Approved via an independent `administrator2` session (not the browser under test) → role `viewer`.
5. Reloaded the browser session; confirmed real viewer access to Vehicle Locations, and confirmed a write attempt correctly returned `403`.
6. Changed role to `operator` (controller) via `administrator`; confirmed the account could invoke `schedule_vehicle_work` (not role-blocked) and could not invoke any `admin_*` RPC.
7. Disabled the account; confirmed zero operational rows returned immediately.
8. Restored the account; confirmed the exact prior role (`operator`) was returned, not reset.
9. Cleaned up the test account and all associated audit rows.

## 11. Known limitations and production blockers

- Production database could not be inspected without credentials — its current schema, migration version, `auth.users` accounts, and operational row counts remain unknown.
- Production backups have not been enabled.
- Production migrations have not been applied.
- Production administrator has not been created.
- Production Auth URLs have not been changed.
- `pdccontrolboard.com` DNS is not configured — the domain does not exist at all today.
- `random-100-vehicles.csv` remains publicly downloadable from the current production deployment.
- The new account-registration, approval, and shared-realtime workshop features are not live on production.
- No production cutover has occurred.
- The pending user's own "Awaiting approval" screen does not update live via realtime (only the administrator's User Management screen does) — a user must sign out/in or reload after being approved to regain access. This is a real, minor UX gap, not a security issue (the RLS/RPC enforcement is unaffected either way).

## 12. Exact next production steps (provided, not executed)

1. Obtain production Supabase database credentials and record the current schema/migration version, `auth.users` accounts, and table row counts (read-only).
2. Run `scripts/pdc_backup.py --environment production` (after deliberately lifting its current staging-only guard) and verify with an isolated-schema restore.
3. Take a ZIP backup of the current live site via `gh api repos/BTNew/pdc-control-board-login/zipball/main`.
4. Apply migrations `001`–`019` to production, in order, only for versions not already present per step 1.
5. Create the first production administrator via the Supabase dashboard (never via public signup); create a second immediately after.
6. Migrate any real operational data found in step 1 (only if present); confirm `data.js`/`email-board-data.js` remain sanitized.
7. Decide and execute the domain path: register `pdccontrolboard.com` and configure Pages/DNS/certificate, or continue with the existing Pages URL.
8. Push production Auth URL configuration for the final chosen URL via `supabase config push --project-ref vjdtsswhroyguxyfjdkt`.
9. Decide whether to remove `random-100-vehicles.csv` from the live site.
10. Deploy the already-built, already-validated `_build/production-artifact/` to `BTNew/pdc-control-board-login` `main`.
11. Run the full live-verification checklist (§10's end-to-end workflow) against the production URL.
12. Decide on `pdc-control-board-staging`'s long-term visibility.
13. Keep the rollback plan (§9, step 12 of the cutover plan) ready and rehearsed before step 10 runs.

**This document stops here. No production action will be taken without your explicit separate approval.**
