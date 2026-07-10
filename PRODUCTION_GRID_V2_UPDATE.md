# Production Grid V2 update

**Build:** `2026.07.10.23-uniform-stage-matrix`  
**Date:** 10 July 2026

## What changed

Vehicle rows now use one shared production-grid layout throughout the application. The layout is intentionally closer to a dealership or workshop data grid than a card-based website.

The shared row order is:

1. Expand control
2. Selection checkbox where applicable
3. Key
4. Stock
5. Job Card
6. Customer
7. Vehicle
8. Parts
9. Tint
10. Hoist
11. Fitting
12. Fabrication
13. Electrical
14. Tyre Bay
15. Pit Inspection
16. Page-specific age, ETA or date
17. Page-specific status
18. Actions

The **Customer** field is the flexible identity column. Long customer or organisation names remain complete and wrap onto additional lines. The row grows only when needed. Key, Stock and Job Card stay fixed and aligned.

## Pages updated

The shared production row is used on:

- Vehicle Locations
- Control Board
- Pipeline
- Production Schedule
- Department work lists
- RFT
- Deleted vehicles

The following pages now use matching compact data-grid tables with separate identity columns:

- Parts
- Completed vehicles
- Back End Data

PMB bay tiles also keep full customer names and full outstanding-station names.

## Station display

All eight station names remain visible in the sticky header:

- Parts
- Tint
- Hoist
- Fitting
- Fabrication
- Electrical
- Tyre Bay
- Pit Inspection

The names are shown once at a 45-degree angle. Every row beneath uses eight identical 52 px × 30 px cells instead of repeating the names in variable-width chips. This reduces the stage strip from 574 px to 444 px and gives the flexible Customer column more room.

The status states are:

- Grey dash: not required
- Red/pink dot: required and outstanding
- Strong red exclamation: blocked
- Green tick: complete

Each vehicle row itself has no horizontal scrollbar. On a screen that is narrower than the production grid, the containing list or table provides a single horizontal scrollbar for the whole section so column alignment is preserved.

## Density and readability

- Standard row text: 13 px
- Standard minimum row height: 46 px
- Compact table text: 12.5 px
- Long names: wrapping enabled, no ellipsis
- Headers: sticky and aligned to the row tracks
- Alternating row background and restrained hover state improve scanning
- Sidebar, page header, controls and KPI cards use less space so more working data is visible

The existing Compact, Standard, Wide and Extra Wide row-width modes are retained.

## Business logic

This update changes presentation and row composition only. Navision import rules, manual PMB/RFT protection, drag-and-drop, station completion, Parts stoppages, RFT gates, collection, deletion, backup and restore logic remain in place.

## Validation completed

The following checks passed:

```text
node --check app.js
node --check data.js
node test_data_integrity.js
node test_navision_confirm.js
node test_parts_production_principles.js
node test_review_update_alignment.js
node test_production_grid_v2.js
```

Browser rendering was also checked at 1920 × 1080 using synthetic vehicle data. Vehicle Locations, Control Board, Parts, RFT, Completed, Deleted, Back End Data, Pipeline, Schedule and Department views rendered without browser console or page errors. The rendered Control Board row measured 13 px text, a 46 px minimum height, eight identical 52 px × 30 px stage cells, and no row-level horizontal overflow.
