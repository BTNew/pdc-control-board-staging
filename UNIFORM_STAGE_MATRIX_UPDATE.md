# Uniform Stage Matrix update

**Build:** `2026.07.10.23-uniform-stage-matrix`  
**Date:** 10 July 2026

## Decision

The production-grid pages now use a header-only stage matrix. The stage names are written in full once in the sticky header and angled at 45 degrees. Every vehicle row beneath the header uses eight identical status cells.

Removing vowels was deliberately avoided. Abbreviations such as `FBRCTN` and `ELCTRCL` reduce immediate recognition and create avoidable training and accessibility problems. The angled header preserves the real workshop names while using substantially less width.

## Stage matrix

The stage order remains:

1. Parts
2. Tint
3. Hoist
4. Fitting
5. Fabrication
6. Electrical
7. Tyre Bay
8. Pit Inspection

Each status cell is exactly **52 px wide × 30 px high**, with a 4 px gap. The complete matrix is 444 px wide, reduced from the previous 574 px variable-width strip.

Row symbols are:

- `✓` — complete
- `•` — required and outstanding
- `!` — blocked
- `–` — not required

Colours continue to reinforce the same state. Every cell retains its full station-and-status text through an accessible label and a native hover tooltip.

## Pages covered

The shared matrix is used wherever the universal production row appears:

- Vehicle Locations
- Control Board
- Vehicle Pipeline
- Production Schedule
- Department work lists
- RFT

Pages that do not present a stage matrix, such as Parts, Completed vehicles and Back End Data, retain their purpose-built compact tables.

## Long names

The width recovered from the stage strip flows back into the flexible Customer column. Long business and government names remain complete and wrap only when needed. Key, Stock, Job Card, Vehicle, stage status, age/status and action columns remain aligned.

## Validation

Static checks passed:

```text
node --check app.js
node test_data_integrity.js
node test_navision_confirm.js
node test_parts_production_principles.js
node test_review_update_alignment.js
node test_production_grid_v2.js
node test_uniform_stage_matrix.js
```

Browser-render validation at 1920 × 1080 confirmed the same eight 52 px × 30 px stage cells on Vehicle Locations, Control Board, Pipeline, Schedule, the Tint department list and RFT. All visible headers retained the full stage names, every matrix had eight cells, and no browser console or page errors were recorded.
