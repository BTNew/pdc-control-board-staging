# PDC Control Board handoff for another ChatGPT

Use this file to brief another ChatGPT/developer on the current PDC Control Board work.

## Project

- Local repo: `C:\Users\nwmgr\pdc-control-board`
- GitHub repo: `https://github.com/BTNew/pdc-control-board`
- Branch: `main`
- Live site: `https://btnew.github.io/pdc-control-board/`
- 75-vehicle test board: `https://btnew.github.io/pdc-control-board/test-75.html?clearLocalData=1`
- Fresh main-board URL for current visibility/fitting fix: `https://btnew.github.io/pdc-control-board/?v=2026.07.08.5`

## Current confirmed commit state

Latest commits:

- `24509a9 Fix PMB bay move controls`
- `aa35b66 Add 75 vehicle test board`
- `8075f8a Finish checklist cache-bust and workflow UI updates`

Visible app version after the movement fix should be:

- `2026.07.08.5`

## What Craig wants preserved

Craig uses this as a live PMB/PDC control board. Keep reports concise: changed files, tests, live/deploy status, and any clear next step.

Important workflow rules:

- Navision import drives the main tracker.
- Manual Yard Hold / PMB / RFT overrides take priority over Navision.
- PMB transfer lands in `Unallocated`.
- PMB vehicles must be movable between work buckets/bays and back to `Unallocated`.
- Craig specifically needs to move a vehicle back to `Unallocated` when work is done and it is waiting for another bay/process.
- Numbered bays are physical capacity: do not allow a second active PMB vehicle into an occupied numbered bay.
- If drag/drop is unreliable, use visible direct buttons instead of relying only on drag/drop.
- Current PMB work/stage order: `TINT`, `HOIST`, `FITTING`, `FAB`, `ELEC`, `TYRE`, `PIT`.
- Parts issued/completed vehicles should be hidden from the default open Parts queue.
- `FIX FIRST` should only show PMB/Parts stoppages.
- Completed/RFT collected vehicles should be locked from being accidentally unticked back into active work.
- Parts still gates RFT until issued or not required.
- Do not change DNS, Pages source/domain/CNAME, repo visibility/access, secrets, dependencies, destructive git/file ops, analytics/tracking, privacy-sensitive storage, or dangerous settings without explicit approval.

## Test-board requirement

When updating the PDC Control Board, keep/provide a separate 75-vehicle random/varied-position test board so changes can be tested across all statuses.

Current test files:

- `test-75.html`
- `data-test-75.js`

Current test board link:

- `https://btnew.github.io/pdc-control-board/test-75.html?clearLocalData=1`

The test board should remain separate from the live/normal data.

## Recently completed user checklist

The following was implemented before this handoff:

- Parts screen hides vehicles once Parts are issued/completed from the active list.
- Control Board has work-type filters/tick boxes for `TINT`, `HOIST`, `FITTING`, `FAB`, `ELEC`, `TYRE`, `PIT`.
- Navision import no longer auto-ticks PMB work based on bad assumptions; required PMB work is manually confirmed.
- Parts ordered is separated from issued; `partsOrdered()` ignores JITA `Yes`.
- Manual override allows vehicles to move to PMB from Yard Hold/In Transit when Navision glitches.
- Parts screen shows ETA to Kewdale and days until/since ETA.
- Completed vehicles/RFT collected vehicles are locked.
- Parts and completed tables are full-width/scrollable.
- `FIX FIRST` is a collapsible row-style list restricted to PMB/Parts stoppages.
- Vehicle card PMB work stream dropdown was removed/simplified into job chips/status indicators.
- Required/completed work display uses grey/red/green job indicators.
- JC Jobcard Number was added near Key Number and should be searchable/editable.
- `pmbAgeDays()` uses PMB entered timestamp, not Kewdale ETA.

## Latest specific issue/fix

Craig reported he still could not move vehicles to/from bays and back to `Unallocated`.

Fix pushed in commit:

- `24509a9 Fix PMB bay move controls`

Expected behavior now:

- PMB vehicle cards show clear `Move:` buttons.
- Vehicles can move:
  - from a work bucket/bay back to `Unallocated`
  - from `Unallocated` into `TINT / HOIST / FITTING / FAB / ELEC / TYRE / PIT`
  - between work buckets
- Numbered bay view should always expose `Unallocated` and `No bay` controls.

Verified after fix:

- On 75-vehicle test board, vehicle `TEST032` moved from `TINT Bay 02` to `Unallocated`.
- Then moved from `Unallocated` to `HOIST`.
- Browser console had no errors.

## 2026-07-08 visibility follow-up

Craig reported the updates were not visible even after Ctrl+F5. The likely causes found were:

- The previous answer overstated completion; several follow-up patches had not actually been pushed yet.
- `pdFlagsFromTasks()` still marked `FITTING` required for any imported PD task.
- PO upload inference still marked `FITTING` required for any uploaded file/task.
- PMB card job sign-off still blocked completion unless the job was already marked required.

Patch applied for version `2026.07.08.5`:

- Removed broad “any task/file means fitting” inference.
- PMB card sign-off can now mark the job required and complete in one confirmed action.
- Completed/RFT-collected vehicles remain locked from removing sign-offs.
- Cache-busted `index.html`, `test-75.html`, and `app.js` to visible version `2026.07.08.5`.

## Files most likely involved

- `index.html` — shell, version marker, asset cache-busting, UI fields.
- `app.js` — core PMB/Parts workflow logic, movement functions, renderers.
- `styles.css` — PMB card/button/status styling.
- `data.js` — live/default data source.
- `test-75.html` — separate 75-vehicle test board page.
- `data-test-75.js` — 75-vehicle synthetic fixture data.

## Validation commands

From `C:\Users\nwmgr\pdc-control-board`, run:

```bash
node --check app.js
node --check data.js
node --check data-test-75.js
node test_navision_confirm.js
node test_parts_production_principles.js
node test_review_update_alignment.js
git diff --check
git status --short --branch
```

For UI changes:

1. Start local server:

```bash
python -m http.server 8765 --bind 127.0.0.1
```

2. Open:

```text
http://127.0.0.1:8765/test-75.html?clearLocalData=1
```

3. Browser-test movement between PMB stages/bays and `Unallocated`.
4. Check browser console for errors.
5. Push only after tests pass.
6. Verify GitHub Pages live URL with a cache-busted query string.

## Reporting to Craig

Keep responses short. Include only:

- changed files
- tests/browser status
- GitHub/live status
- link to test board or fresh live URL
- any next step needed

Do not give long internal reasoning unless asked.
