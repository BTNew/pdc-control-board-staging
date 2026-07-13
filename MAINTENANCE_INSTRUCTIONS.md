# PDC Control Board Maintenance Instructions

Use this as the canonical maintenance workflow for the PDC Control Board project.

## Repository and live site
- Local repo: `C:\Users\nwmgr\pdc-control-board`
- GitHub repo: `https://github.com/BTNew/pdc-control-board`
- Live site: `https://btnew.github.io/pdc-control-board/`
- Branch: `main`

## Required workflow: inspect → modify → test → browser-check → commit → push → live-verify
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
9. Poll GitHub Pages and verify the deployed live site is serving the new version.
10. Report changed files, tests, live status and any remaining risks.

## Files with matching version numbers
Current version identifier: `2026.07.13.07-zero-filter-recovery`

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
node test_navision_confirm.js
node test_parts_production_principles.js
node test_data_integrity.js
node test_review_update_alignment.js
node test_production_grid_v2.js
node test_uniform_stage_matrix.js
node test_desktop_operations.js
node test_master_sheet_import.js
git diff --check
```
If relevant files changed, also run any additional `test_*.js` files that match the area changed. At handover, these extra tests also exist and are useful:
```bash
node test_production_grid_v2.js
node test_uniform_stage_matrix.js
```

Expected success messages include:
- `Navision confirmation tests passed`
- `Parts/production principle tests passed`
- `Data integrity checks passed`
- `Review update alignment tests passed`

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

Use `?clearLocalData=1` only for isolated test sessions where clearing app localStorage is intended. Do not use it against a real user’s production browser unless explicitly approved.

## Live GitHub Pages verification
After push, GitHub Pages may serve mixed old/new assets for a short period. Poll until both `index.html` and referenced assets show the new version.

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

Do not rely only on localhost. Confirm the deployed live URL is serving the expected version.

## Preserving user data
- Do not wipe `localStorage` as part of normal changes.
- Do not modify clear/reset functions unless the user explicitly asks.
- Bundled `data.js` is baseline/static data; live users may have local edits layered over it.
- Manual local overrides must remain higher priority than Navision/bundled values.
- Do not commit private user/customer data, credentials, or generated backups.

## Avoiding regressions
- Preserve compact UI and existing workflows unless asked.
- Preserve import rules: only real Batch/Stock rows; no totals/fake rows.
- Preserve manual YH/PMB/RFT overrides over Navision.
- Preserve first-PMB-transfer-to-Unallocated rule.
- Preserve Parts/RFT gates; RFT requires required jobs including Parts.
- Preserve PMB bay capacity constants and internal stage keys.
- Add/update tests whenever a business rule changes.

## Fragile areas
- `app.js` is large and contains duplicated concepts across Dashboard, Parts, PMB, RFT and modal code.
- Version strings are duplicated across HTML/JS test files.
- `localStorage` schema is implicit in constants and save/load helpers.
- Parts and PMB workflow rules are tightly coupled to tests; update tests with code.
- GitHub Pages can temporarily serve old `index.html` with new assets or vice versa.

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
