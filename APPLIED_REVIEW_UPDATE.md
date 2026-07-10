# Applied Review Update — 2026-07-05

This package applies the practical recommendations from the review pass.

## Updated in the website

- Staff navigation renamed to: Control Board, PMB Workflow, Parts, RFT, Reports, Uploads.
- Control Board now has a Fix First exception panel before the main vehicle list.
- PMB Workflow now has a Fix First strip above the stage buckets.
- Dashboard quick Navision / PD import panels are hidden so Uploads is the import home.
- Main table default column order now matches current columns: Tint, Hoist, Fitting, Fabrication, Electrical, Tyre, Pit Inspection, Navision Notes, JITA, Action.
- Saved column-order storage key bumped to v3 so stale old stage layouts do not keep loading.
- Explicit import parsing now accepts Parts required and Parts complete columns.
- Main CSV export now generates job columns from `PDC_JOB_DEFS` instead of hard-coded old headers.
- RFT email action now explains why the button is disabled when gate issues remain.
- Separate mobile page has been removed; the main board is the maintained interface.
- Visible documentation and user-facing wording have been updated to the current stage list.
- External CDN script tags removed from the packaged site.

## Current stage/job list

- Tint
- Hoist
- Fitting
- Fabrication
- Electrical
- Tyre bay
- Pit Inspection
- Parts

## Still intentionally retained

Some internal legacy aliases remain in code so older saved browser data and older spreadsheet columns still map safely into the current Fitting/specialist workflow. These are compatibility aliases, not visible PMB stages.

External CDN script tags for QZ Tray and PDF.js have been removed from `index.html`. Optional printing/PDF extraction now relies on graceful fallbacks unless approved local vendored libraries are added later.

## Checks run

```bash
node --check app.js
node --check data.js
node test_navision_confirm.js
node test_parts_production_principles.js
node test_review_update_alignment.js
```

All checks passed in this update package.
