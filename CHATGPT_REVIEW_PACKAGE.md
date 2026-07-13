# PDC Control Board — Review Package for Another ChatGPT Session

## What this is

This is a static website/app for managing vehicle flow through PDC / PMB / Yard Hold / Parts / RFT operations.

Historical public/demo URL (unauthenticated; do not serve operational data here):
- https://btnew.github.io/pdc-control-board/?v=12cca86-rft-live

Repository:
- https://github.com/BTNew/pdc-control-board

Original commit included before this review-update pass:
- `12cca86` — `Add RFT home and fix workflow collapse`

This package has since had the 2026-07-05 review recommendations applied directly in the static files.

The app is currently a plain static site using:
- `index.html`
- `styles.css`
- `app.js`
- `data.js`
- local browser storage for user-side state/persistence

There is no backend database in this package.

---

## Your task

Please review this website/app and suggest practical improvements for a real dealership/workshop environment.

Focus on:
1. Making the workflow simpler for workshop/admin staff.
2. Improving the UI layout and readability.
3. Making the PMB workflow board easier to use.
4. Improving Control Board, Parts, RFT and import flows.
5. Reducing clutter and confusion.
6. Making status, blockers and next actions obvious.
7. Preserving the existing business rules listed below.

Please provide:
- A concise diagnosis of what is confusing or weak.
- A prioritised improvement list.
- Specific UI/UX recommendations.
- Specific code-level recommendations if you inspect files.
- Any redesign sketches or layout descriptions that would help.
- A staged plan: quick fixes, medium improvements, bigger rebuild ideas.

If you edit code, keep changes small and reviewable.

---

## How to run locally

From the unzipped folder:

```bash
python -m http.server 8765 --bind 127.0.0.1
```

Then open:

```text
http://127.0.0.1:8765/?v=review
```

If Python is unavailable, use any static file server.

Suggested checks after changes:

```bash
node --check app.js
node --check data.js
node test_navision_confirm.js
node test_parts_production_principles.js
```

---

## Current navigation / major screens

Main side navigation currently includes:
- Control Board
- PMB Workflow
- Parts
- RFT
- Reports
- Uploads

### Control Board
Purpose:
- Operational overview of incoming/non-RFT vehicles.
- Searchable/filterable vertical collapsible vehicle rows.
- Ordered buckets: PMB, Yard Hold, In Transit, Overseas / Other.
- Yard Hold rows can be transferred into PMB.
- PMB/RFT/manual statuses are protected from Navision import overwrites.

### PMB Workflow
Purpose:
- PMB-only workflow board.
- Buckets/stages: Unallocated, Tint, Hoist, Fitting, Fabrication, Electrical, Tyre, Pit Inspection.
- Compact collapsible rows.
- Drag PMB vehicles between stages/buckets.
- Open bays for detailed bay assignment.
- Collapse all rows should close all Workflow details.

Recent fix:
- Workflow zoom/scale should remain normal: CSS zoom should be `1`, transform should be `none`.
- Collapse all rows now uses explicit collapse state rather than re-opening all buckets on render.

### Parts
Purpose:
- Production-focused Parts screen.
- Shows parts-related blockers/status without salesperson or finance clutter.
- Parts stoppage means Parts required but not completed, with a stoppage flag/reason.

### RFT
Purpose:
- Ready For Transfer / final gate home screen.
- Shows RFT vehicles, readiness/completion status, blockers and outstanding jobs.
- Allows completion ticks for required RFT/PDC jobs.
- RFT requires all required jobs, including Parts and Pit Inspection when present.

### Uploads
Purpose:
- Paste/import copied Navision rows.
- Manual PMB / Yard Hold / RFT states must remain protected from imported data.

---

## Business rules that must be preserved

Please do not break these:

1. Navision import drives the main tracker.
2. Manual Yard Hold / PMB / RFT overrides take priority over Navision.
3. PMB transfer lands in Unallocated.
4. Job ticks must not auto-allocate vehicles to bays/stages.
5. `pmbStage` is the production bucket assignment.
6. Current PMB/production stages:
   - Tint internal
   - Hoist
   - Fitting
   - Fabrication
   - Electrical
   - Tyre bay
   - Pit Inspection
7. Current capacity assumptions:
   - Tint: 2 bays
   - Hoist: 3 bays
   - Fitting: 5 bays
   - Fabrication: refer Dan / non-fixed
   - Electrical: 10 bays
   - Tyre bay: 2 bays, including 1 wheel-alignment bay
   - Pit Inspection: 1 bay
8. Numbered bays are physical capacity; do not allow two active vehicles in the same numbered bay.
9. Waiting/no-bay vehicles should remain unassigned until a bay is available.
10. Pit Inspection is both a PMB/RFT checklist gate and a production bay.
11. RFT requires all required jobs, including Parts and Pit Inspection when present.
12. PMB key tag numbers are only relevant while a vehicle is active in PMB.
13. Block duplicate active PMB key tags.
14. Parts view should stay production-focused; no salesperson/finance noise.
15. Do not add tracking/analytics, hidden network calls, or sensitive customer data storage.
16. Do not add secrets, API keys or credentials to browser code.

---

## Applied review update and remaining improvement target

The app has grown through many iterations, so a fresh UX review would help.


Applied in this package:
- Control Board / PMB Workflow / Reports navigation wording.
- Fix First exception cards on Control Board and PMB Workflow.
- Dashboard quick-import panels hidden; Uploads remains the import home.
- Default vehicle table columns aligned to Tint, Hoist, Fitting, Fabrication, Electrical, Tyre, Pit Inspection, Navision Notes, JITA and Action.
- Explicit Parts import columns added.
- Main CSV export job columns generated from current PDC job definitions.
- Separate mobile page removed; the main board is the maintained interface.
- External CDN script tags were removed; optional browser integrations now rely on graceful fallbacks unless local approved libraries are provided.

Remaining watch items:
- It can feel cluttered or overwhelming.
- PMB Workflow layout has been sensitive to zoom/density changes.
- Rows/cards must stay aligned without using global CSS zoom or transform tricks.
- Collapse all rows must actually close every row/detail.
- Staff need a simple process-led view, not just lots of data.
- Control Board and PMB Workflow should make next action obvious.
- PMB cards need to be compact but still readable.
- Parts/RFT should show blockers clearly and avoid irrelevant fields.
- Import flow should clearly show what was accepted/skipped and why.

---

## Important technical notes

- This is a static app. Most state is stored in browser storage and JS data structures.
- `app.js` is large and contains most business logic/rendering.
- `styles.css` contains all layout/styling.
- `data.js` contains sample/current app data.
- `test_navision_confirm.js` and `test_parts_production_principles.js` cover some core rules.
- Keep asset cache-busting query strings updated in `index.html` if changing JS/CSS for GitHub Pages.
- Do not use global CSS `zoom` or broad transforms to shrink the app; tighten real spacing/layout CSS instead.

---

## Suggested review questions

Please answer these after inspecting/running it:

1. What further tuning should the Control Board home screen get for a workshop/admin user?
2. Which screens or controls are redundant?
3. What would make the PMB workflow easier to operate during the day?
4. How should blockers be surfaced?
5. How should RFT readiness be presented?
6. Is the current navigation too broad or about right?
7. Which fields should be hidden by default and only revealed on expand?
8. How should import results be explained to non-technical staff?
9. What layout would work best on a large workshop screen vs a desktop user?
10. What are the top 5 changes to make next?

---

## Please avoid

- Treat the authenticated backend as a separately planned production migration. Follow `BACKEND_MIGRATION_PLAN.md` and do not select a vendor without the requirements/security decision.
- Do not suggest public exposure of customer/business data without authentication.
- Do not introduce analytics/tracking.
- Do not change PMB/RFT/manual override rules.
- Do not make job ticks automatically move vehicles.
- Do not solve layout by setting browser zoom or global CSS `zoom`.

---

## Best output format

Please return:

1. **Executive summary** — 5 to 10 bullets.
2. **Top-priority fixes** — practical, ranked.
3. **Screen-by-screen feedback** — Control Board, PMB Workflow, Parts, RFT, Uploads.
4. **Suggested simplified navigation/layout**.
5. **Code hotspots / risks**.
6. **A staged implementation plan**.
7. Optional: sample wireframe descriptions or HTML/CSS snippets.
