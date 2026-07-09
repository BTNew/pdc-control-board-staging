# Changelog

## 2026-07-10 — Worker review clean version

- Prepared a cache-busted worker review version after the Vehicle Locations and Control Board row-chip alignment update.
- Re-verified JavaScript syntax, core regression checks, whitespace checks, live asset loading, and the main worker-facing pages.

## 2026-07-09 — Coding and visual stability fix

- Added defensive startup/data guards so the board does not silently fail if data loading is delayed or malformed.
- Added visible startup error banner for runtime failures instead of leaving blank panels.
- Exposed `window.PDC_APP` / `window.app` for debugging from the browser console.
- Bumped saved table column storage keys so old wide column settings do not distort the refreshed layout.
- Tightened dashboard tables, PMB buckets, bay tiles, cards, markers and modal forms to stop boxes from overflowing or becoming disproportionate.
- Updated test page cache-busting references.


## 2026-07-05 — Review recommendations applied

- Renamed staff-facing navigation to Control Board, PMB Workflow, Reports, Parts, RFT, and Uploads.
- Added exception-led Fix First cards to Control Board and PMB Workflow.
- Hid dashboard quick-import panels so import work is focused under Uploads.
- Updated default vehicle table columns to current stage IDs and bumped saved column-order storage to v3.
- Added explicit Parts required/complete import mappings.
- Changed main CSV export to generate job columns dynamically from current PDC job definitions.
- Updated mobile stage/job model to Tint, Hoist, Fitting, Fabrication, Electrical, Tyre bay, Pit Inspection, and Parts.
- Cleaned visible old-stage wording and updated import guidance text.
- Removed CDN script tags for QZ Tray/PDF.js so the package stays self-contained; printing/PDF extraction now use existing graceful fallbacks when those libraries are unavailable.

## 2026-06-23 — Dashboard Parts stoppage bucket
- Added a dashboard Parts Stoppage bucket for vehicles with an active Parts stoppage flag or blocker reason.
- Kept completed Parts vehicles out of the active stoppage bucket and added regression coverage.

## 2026-06-23 — Dashboard Parts tick visual states
- Added dashboard Parts tick styling for required/not ordered, ordered/confirmed and received/issued states.
- Added regression coverage so Parts visual classes stay limited to the Parts job tick.

## 2026-06-21 — Parts and production rule alignment
- Aligned Parts statuses to PDC wording: Not Required, Not Ordered, On Order, Issued, Misc Acc and Stoppage.
- Kept Parts search/table/export focused on parts and production by removing salesperson fields from those views.
- Removed the RFT salesperson notification prompt so RFT transfer stays production-only.
- Added regression coverage for parts status rules and no-salesperson RFT prompts.

## 2026-06-20 — Role-focused visual management refresh
- Reworked the Parts department page copy so it clearly hides Navision notes and production-only noise.
- Reordered Parts summary cards to surface Stoppages first, then open/order/waiting/complete work.
- Reordered Parts table columns around actionability: status, stock, ETA/age, blocker, actions, then supporting context.
- Highlighted stoppage rows and cards more strongly so blockers are visible first.
- Added focused PMB bay guidance per work stream; current visible stages are Tint, Hoist, Fitting, Fabrication, Electrical, Tyre bay and Pit Inspection.
- Simplified PMB bay cards to show the current station status rather than all department job markers.
- Clarified PMB board guidance that vehicles land in Unallocated first and are manually assigned to production streams.
- Added documentation set: PROJECT_BRIEF, CHANGELOG, TODO, BUGS and SECURITY.

## 2026-06-20 — Startup and PMB landing fixes
- Fixed missing runtime references for status tabs/header mapping/status category labels.
- Preserved PMB first-landing behaviour so imported requirements do not auto-bucket vehicles.
- Historical note: older releases used the previous job-marker order; current marker/job order is T, H, F, Fa, E, Ty, PI, P.
- Added local browser console and Navision/PMB validation helpers.
