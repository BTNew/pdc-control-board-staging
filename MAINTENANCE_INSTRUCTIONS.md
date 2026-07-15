# PDC Control Board Maintenance Instructions

Use this as the canonical maintenance workflow for the PDC Control Board project.

## Repository and deployment status
- Local repo: `C:\Users\nwmgr\pdc-control-board`
- GitHub repo: `https://github.com/BTNew/pdc-control-board` — **private as of 15 July 2026**.
- Former Pages URL: `https://btnew.github.io/pdc-control-board/` — disabled and returning 404.
- The operational website remains offline until authenticated shared hosting is ready.
- The production shell starts locked behind `pdc-auth.js`. The temporary mode is individual Supabase email/password plus an active `pdc_user_roles` allowlist row; both authentication and authorization are required before the application unlocks.
- Public/anonymous account creation is disabled. Passwords require at least 12 characters with lower/upper-case letters, a digit and a symbol; TOTP enrolment remains enabled. Staff accounts must be created or invited administratively.
- Microsoft/Azure remains the planned identity provider but is not yet enabled. Completion requires a Microsoft Entra app registration and provider configuration.
- Branch: `main`

## Required workflow: inspect → modify → test → browser-check → commit → push → approved-environment verify
1. Inspect first:
   - `git status --short`
   - `git branch --show-current`
   - `git log -1 --oneline`
   - Read the relevant code/tests before editing.
2. Modify only the needed files. Keep changes small and reviewable.
3. Keep version/cache-busting identifiers in sync.
4. Run automated checks.
5. Run local browser smoke checks.
6. Review `git diff` and `git diff --check`.
7. Commit with a clear message.
8. Push `main` to origin.
9. Verify the approved environment. GitHub Pages verification is permitted only with synthetic/non-sensitive data.
10. Report changed files, tests, live status and any remaining risks.

## Files with matching version numbers
Current version identifier: `2026.07.15.05-password-auth`

When bumping version, update all references in:
- `app.js` (`APP_VERSION`)
- `index.html` asset query strings
- `no-vehicles.html`
- `test-50.html`
- `test-75.html`
- `test-100.html`
- `test_uniform_stage_matrix.js`
- Any other HTML/JS asset links found by searching the old version string

Recommended search:
```bash
grep -R "2026\." -n *.html *.js
```
Or use the agent search tool for the exact old version string.

## Tests to run after every change
Run from `C:\Users\nwmgr\pdc-control-board`:
```bash
node --check app.js
node --check data.js
node test_all.js
git diff --check
```

`test_all.js` discovers every `test_*.js` file and summarizes pass/fail/skip results. The real-PO PDF integration test is optional and reports a skip when its three external fixtures or `pdftotext` are unavailable.

Expected success messages include:
- `Navision confirmation tests passed`
- `Parts/production principle tests passed`
- `Data integrity checks passed`
- `Review update alignment tests passed`
- `Vehicle lookup safety checks passed`
- `Storage transaction and recovery checks passed`
- `Operational hardening checks passed`

## Local browser checks
1. Start a local static server:
```bash
python -m http.server 8025 --bind 127.0.0.1
```
2. Open:
```text
http://127.0.0.1:8025/index.html?v=<version>
```
3. Verify:
   - Header/footer shows the current version.
   - Vehicle count loads.
   - Vehicle Locations view renders.
   - Control Board view opens.
   - Parts page opens if Parts code changed.
   - Browser console has no uncaught errors.
   - Workshop Planner loads on first use (its script is intentionally lazy-loaded).
   - PDF.js loads only when a PDF is processed; QZ Tray loads only when printing is requested.

Use `?clearLocalData=1` only for isolated test sessions where clearing app localStorage is intended. Do not use it against a real user’s production browser unless explicitly approved.

## Deployment verification
GitHub Pages may be checked only as a non-sensitive demonstration. It ignores `staticwebapp.config.json` and must not host the operational `data.js` baseline. Production verification requires the approved authenticated environment.

After an approved synthetic-data Pages push, the service may serve mixed old/new assets briefly. Poll until both `index.html` and referenced assets show the new version.

Useful live cache-busted link:
```text
https://btnew.github.io/pdc-control-board/index.html?v=<commit-or-version>
```

Verify by browser and console:
```js
document.querySelector('#app-version')?.textContent
window.VEHICLE_TRACKING_DATA.vehicles.length
performance.getEntriesByType('resource').map(r => r.name).filter(n => /app\.js|data\.js/.test(n))
```

Do not treat a successful Pages check as production security or backend validation.

## Preserving user data
- Do not wipe `localStorage` as part of normal changes.
- Do not modify clear/reset functions unless the user explicitly asks.
- Bundled `data.js` is baseline/static data; live users may have local edits layered over it.
- Manual local overrides must remain higher priority than Navision/bundled values.
- Do not commit private user/customer data, credentials, or generated backups.
- Never deploy the operational bundled baseline to unauthenticated GitHub Pages. Use the zero-vehicle or synthetic fixture for public demonstrations.
- `data.js` and `email-board-data.js` are sanitised zero-record fallbacks. Do not restore operational records to either file.
- Windows task `PDC Email Website Updater` is disabled. Static publication additionally requires both `--publish-static` and the exact local `PDC_ALLOW_STATIC_PUBLICATION` safety gate; normal runs write only to ignored `backend/.generated/`.

## Avoiding regressions
- Preserve compact UI and existing workflows unless asked.
- Preserve import rules: only real Batch/Stock rows; no totals/fake rows.
- Preserve manual YH/PMB/RFT overrides over Navision.
- Preserve first-PMB-transfer-to-Unallocated rule.
- Preserve Parts/RFT gates; RFT requires required jobs including Parts.
- Preserve PMB bay capacity constants and internal stage keys.
- Explicit missing/ambiguous vehicle lookups must stop without mutating another vehicle.
- Multi-key imports and restores must validate before mutation and roll back fully on a write/rebuild failure.
- Add/update tests whenever a business rule changes.

## Fragile areas
- `app.js` is large and contains duplicated concepts across Dashboard, Parts, PMB, RFT and modal code.
- Version strings are duplicated across HTML/JS test files.
- `localStorage` schema is implicit in constants and save/load helpers.
- Parts and PMB workflow rules are tightly coupled to tests; update tests with code.
- GitHub Pages can temporarily serve old `index.html` with new assets or vice versa.
- Read `BACKEND_MIGRATION_PLAN.md` before introducing authentication, API, database or deployment-platform dependencies.

## Packaging handovers
Create clean zips outside the repo or with excluded patterns. Exclude:
- `.git/`
- `node_modules/`
- secrets or `.env*`
- backup ZIPs
- temporary folders
- generated test output/cache folders

Example from repo parent:
```bash
zip -r pdc-control-board-handover-<date>-<commit>.zip pdc-control-board \
  -x 'pdc-control-board/.git/*' 'pdc-control-board/node_modules/*' 'pdc-control-board/*.zip' 'pdc-control-board/.env*'
```
