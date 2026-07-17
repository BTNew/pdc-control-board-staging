# PDC Control Board — Production Migration & Cutover Plan

Status: **DRAFT — staging-tested only. Not executed against production. Requires explicit approval before any step below runs against production.**

## 0. Read-only production assessment (findings this plan is based on)

| Item | Finding |
|---|---|
| Live URL | `https://btnew.github.io/pdc-control-board-login/` (200 OK, confirmed) |
| GitHub Pages source | Repo `BTNew/pdc-control-board-login`, branch `main`, path `/`, `build_type: legacy`, `public: true` |
| Latest production commit | `04b6237c665dcada0cdab9183de04f9712445047` — "Deploy workshop planner drag target stabilization" (2026-07-16) |
| Custom domain | **`cname: null` — no custom domain is configured today.** `pdccontrolboard.com` does not resolve in DNS at all (confirmed via `nslookup`, including `www.`/`staging.`/`test.`/`dev.` subdomains — none exist). **The brief's assumption that this domain already exists and must be "preserved" does not match reality; it must be registered and wired up as a new step, not preserved.** |
| HTTPS | Enforced (`https_enforced: true`, HSTS header present, valid `*.github.io` certificate through 2026-09-02) |
| Production Supabase project | `vjdtsswhroyguxyfjdkt` (confirmed via `pdc-supabase-config.js` and `supabase projects list`) |
| Production Supabase schema / migration version / Auth users / row counts | **Not inspected.** Doing so requires a production database connection string/password, which does not exist in this working environment and was not created, per the explicit "do not touch production" / "read-only" constraint — creating new production credentials is itself a production-adjacent action that was not pre-approved this session. **This is the single largest unknown blocking a safe cutover and must be established as step 1 of execution, by the user or an operator with production DB access, before anything else runs.** |
| `data.js` (production) | Confirmed sanitized/empty: `vehicles: []`, title "Vehicle Tracking Core - Private Cutover Hold" |
| `email-board-data.js` (production) | Confirmed sanitized/empty: `vehicles: []`, `reviews: []` |
| localStorage (production, real staff browsers) | **Not remotely inspectable.** Requires a real staff machine or explicit screenshot/export from the user. |
| Legacy/stray files still deployed | `random-100-vehicles.csv` — a downloadable synthetic 100-row test CSV, offered via a "Download random 100-vehicle CSV" button in the Back End Data admin panel. Not auto-loaded, but is synthetic test data shipped in the live repo; flagged for removal decision during cutover. |
| Other GitHub Pages deployments on the account | Only `pdc-control-board-login` (production) and `pdc-control-board-staging` (this project's staging) have Pages enabled among files relevant to PDC. One unrelated repo (`excellence-transfer`) also has Pages enabled but is a different, unrelated project. No other staging/test/preview/dev Pages sites found. |
| DNS records | No `pdccontrolboard.com` A/CNAME record exists in any form checked. |
| Workshop-planner / shared-realtime feature on production | **Not deployed.** Production's live `index.html` script list is `vendor/supabase → pdc-supabase-config.js → pdc-auth.js → data.js → email-board-data.js → arb-labor-catalog.js → app.js` only — no `workshop-planner.js`/`workshop-data-service.js`/etc. Production's `pdc-supabase-config.js` also has no `workshop.sharedData`/`vehicleLifecycle.sharedData` flags, so even though `app.js` contains the lazy-load code for these features, it never fires on production today. |
| Test/shared accounts on production Supabase Auth | **Not inspected** (same credential constraint as schema/migration version above). |

## 1. Non-negotiable constraints carried into every step below

- Every step that touches production requires explicit, separate user approval before it runs. This plan being written does **not** constitute that approval.
- Production and staging Supabase projects, and their backups, remain completely separate at every step.
- No service-role key, database password, or mailbox credential is ever placed in a committed file or frontend code.
- Every migration applied to production must have been applied to staging first and passed the staging test suite.
- Rollback must be possible at every stage before proceeding to the next.

## 2. Sequenced cutover steps

### Step 1 — Establish production access (user/operator action, not this session)
Obtain the production Supabase database connection details (via the Supabase dashboard, not committed anywhere) and confirm:
- Current `supabase_migrations.schema_migrations` version.
- Current row counts for `vehicles`, `workshop_bookings`, `pdc_user_roles`/equivalent, `audit_events` (if the table already exists there at all — it may not, since the workshop/backup/account-approval features have never shipped to production).
- Existing `auth.users` accounts and their roles.

This step is a **prerequisite finding**, not a code change. Nothing below can be safely sequenced without it.

### Step 2 — Production database backup (before any migration)
Run the already-staging-tested backup tool (`scripts/pdc_backup.py`) against production for the first time, with `--environment production` explicitly (the tool currently hard-refuses production; the guard must be deliberately lifted only after this plan is approved), storing the encrypted backup in a location outside the live database, never inside the public site repo.
- Verify the backup with `scripts/pdc_restore.py` into an **isolated schema on the production project** (never into `public`) before proceeding, exactly as already proven twice on staging.

### Step 3 — Existing website ZIP backup
`gh api repos/BTNew/pdc-control-board-login/zipball/main` → save the current live site's exact file set as a timestamped ZIP, stored outside the repo, before any file is changed.

### Step 4 — Apply outstanding migrations to production (schema only, no data change)
Apply, **in order**, every migration from `001` through `018` that is not already present on production (per Step 1's finding). Every one of these has already been applied to and tested against staging in this project. Do not apply any migration that has not passed the staging suite.

### Step 5 — Existing operational-data migration (if applicable)
If Step 1 finds production already has real operational data in its own `vehicles`/`workshop_bookings` tables (separate from the empty `data.js`/`email-board-data.js` static fallbacks confirmed in the read-only assessment), that data must be preserved through the migration — do not overwrite it. If production genuinely has zero rows in these tables today (plausible, since the static JS fallbacks are already sanitized/empty and the shared-data feature has never been enabled there), this step is a no-op.

### Step 6 — localStorage / static-data migration
Because `data.js` and `email-board-data.js` are already sanitized/empty on production, there is nothing to migrate out of them. If real operational data is later found to exist only in individual staff members' browser localStorage (per the "operational data still exists in localStorage" assessment question — not remotely checkable this session), that data must be exported from each affected browser and imported via the same legacy-import tooling already built and tested in this project (`scripts/workshop_legacy_import.py`), never assumed to be absent without checking.

### Step 7 — Production administrator creation
See dedicated section below (§3). Must happen only after Step 4's migrations are live, so `pdc_user_roles`/`admin_approve_user` exist to receive the first administrator.

### Step 8 — Authentication URL configuration
Push `supabase/config.toml`'s `[auth]` section to production **with production's own site_url/redirect list** (i.e. the eventual live URL — either the existing `https://btnew.github.io/pdc-control-board-login/` or the new custom domain once registered, see §0), using `supabase config push --project-ref vjdtsswhroyguxyfjdkt`. Do this only after Step 9 registers the domain (if a custom domain is desired) so the URLs pushed are final, not provisional.

### Step 9 — Domain registration and DNS (only if a custom domain is actually wanted)
`pdccontrolboard.com` does not exist today. If the business wants this domain: register it, add a GitHub Pages custom-domain CNAME record pointing at `btnew.github.io`, add the domain in the production repo's Pages settings, and wait for Pages to issue its own TLS certificate before enabling HTTPS enforcement on the custom domain. This is a new setup task, not a "preservation" task, and should be sequenced and approved independently of the account-approval feature rollout if the business wants to ship the feature sooner than the domain can be registered/verified (DNS + cert issuance can take hours to a few days).

### Step 10 — Removal or disabling of test/synthetic material
- Remove `random-100-vehicles.csv` and its download button from `index.html` (or keep, if the business wants to retain the sample-import feature — flagged as a decision, not assumed).
- Confirm no staging/synthetic accounts exist in production `pdc_user_roles`/`auth.users` (per Step 1's finding).

### Step 11 — Deploy the clean production artifact
Build the artifact with `python scripts/build_production_artifact.py` (already built and validated this session — zero staging references, zero secrets, production Supabase ref present, no staging Pages URL present). Deploy by pushing the artifact's contents to `BTNew/pdc-control-board-login`'s `main` branch — this is the **only** step that actually changes the live site, and must be the last content change before live verification.

### Step 12 — Public test-site cleanup
Decide whether `BTNew/pdc-control-board-staging` remains public indefinitely (recommended: keep, since it costs nothing and is clearly labelled staging-only) or is made private/archived after cutover. Not required for production correctness either way.

### Step 13 — Live verification
- Load the production URL, confirm zero console/CSP errors.
- Sign in as the newly created production administrator (§3).
- Confirm the account-approval flow end-to-end exactly as tested on staging (register → pending → approve → access granted).
- Confirm production Supabase project ref appears in the loaded config, and staging project ref does not.

### Step 14 — Rollback procedure (must be rehearsed on staging before Step 11 runs on production)
1. Re-deploy the Step 3 ZIP backup's exact file set to `BTNew/pdc-control-board-login` `main` (undoes Step 11).
2. If a migration in Step 4 needs reverting, apply the corresponding down-migration (each of migrations 013–018 was written with a clear single-purpose scope so a manual reverse migration is short and reviewable — none of them are irreversible schema drops).
3. Restore the Step 2 database backup into an isolated schema, verify row counts against the restore-verification report format already proven on staging, and only then consider a full restore into `public` (a last resort, requires separate explicit approval, never done automatically).
4. Revert the Step 8 Auth URL config with `supabase config push` using the pre-change values captured in Step 1.

## 3. Production administrator setup (secure, no passwords stored anywhere)

1. After Step 4's migrations are live, an operator with production Supabase dashboard access creates exactly one `auth.users` row via the Supabase dashboard's "Invite user" or `admin_create_user` (never via the public signup form, and never with a hardcoded password in any script or commit).
2. That operator, using a direct `psql`/dashboard SQL editor session against production only (not this repo, not any file), manually inserts or updates the matching `pdc_user_roles` row to `role='administrator'`, `active=true`, `account_status='approved'` — a one-time bootstrap, since no administrator yet exists to call `admin_approve_user` on themselves.
3. The operator immediately signs in once to confirm access, then sets a strong password via Supabase Auth's own "send password reset" flow rather than ever typing/storing a plaintext password anywhere.
4. A second production administrator should be created the same way before the first administrator's session ends, mirroring the two-administrator recovery pattern already proven on staging (`administrator@`/`administrator2@`), so the last-administrator protection has a real second account to fail over to from day one.
5. No password for any production account is ever written to a commit, a chat log, or this document.

## 4. What is NOT included in this plan

- Any AI Email Monitoring / Vehicle Intelligence work (separate, paused feature track).
- Any decision about whether `pdccontrolboard.com` should actually be registered — that is a business decision this plan surfaces but does not make.
- Automatic execution of any step above. This document is a plan for human-approved, step-by-step execution, not a script that runs itself against production.
