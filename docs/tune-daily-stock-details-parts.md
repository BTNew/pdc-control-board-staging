# Daily Tune intake — STAGING contract

Craig's 10 September 2026 instructions apply to the existing dynamic Tune/Revolution route in `BTNew/pdc-control-board-staging`, Supabase `cdsmnqxtyyoeoznmbidd` only.

## Vehicle identity and details

Use exact Stock to create/reuse one canonical vehicle. An unambiguous current Navision match supplies the customer name and vehicle description, regardless of conflicting Tune descriptions. Current Navision client/customer and vehicle/model fields are authoritative; the New Vehicles view reads those live fields rather than blank intake placeholders.

When there is no Navision match, use the Tune customer's name and vehicle description. This includes used vehicles and non-franchise stock such as Isuzu. Do not infer identity from make, customer or description. Blank Stock is still unbound review. Conflicting identities, multiple Navision matches, conflicting nonblank Tune details, or conflicting VIN evidence require review. VIN remains optional. Valid supplied VIN is checked against existing canonical/Navision evidence and is retained as evidence.

Daily exports may refresh already-approved active vehicles without creating another vehicle, resetting approval, changing location, or creating workshop bookings/completions. Closed/QC/RFT vehicles require review. Operation identity remains Department + R/O + Stock + Line + normalized description; absent operation codes remain null. The Dept 138 Bus 4x4 override, Dept 139 per-operation routing and one-hour pre-delivery standard remain in force.

## Parts colours

| Current source evidence | Vehicle Parts state |
| --- | --- |
| Explicit no parts on back order | Green |
| Outstanding parts without a purchase order | Red |
| Outstanding parts with purchase order numbers | Orange |
| Missing or unclear evidence | Review; no automatic green |

An explicit No takes precedence over a historical PO number. Across rows, any unordered outstanding part keeps the vehicle red. Otherwise any unresolved row requires review; all remaining outstanding parts with POs produce orange; all explicit No rows produce green. A purchase order means ordered, not received. Do not invent an ETA. Existing manual stoppages are retained. Unclear fresh parts evidence does not overwrite an earlier known Parts state.

Parts status and customer metadata can change across daily files without altering immutable operations or duplicating them. Each applied file retains separate metadata evidence, original workbook and partition hashes, and the original source rows. The Parts tick can change; workshop operation completions do not.

## Export adapter fields for Hermes

Retain all source columns in `raw_row`. For each operation row provide the existing identity/hours/station fields plus, when available:

- `customer_name`: the actual Tune customer name, propagated only within the exact Stock/R/O header group.
- `vehicle_description`: Tune vehicle/model description, never the operation description.
- `vin`: actual source VIN, when present.
- `parts_on_backorder_raw`: actual Yes/No/blank source value.
- `purchase_order_number`: actual PO reference for that row's outstanding parts, when present.

Recognized raw-header aliases include Customer Name / Customer / Client, Vehicle Description / Vehicle / Model Description, Parts on Backorder / Parts on Back Order, and PO Number / PO No / Purchase Order Number. Canonical adapter fields avoid ambiguity when the new export's headers differ. Do not convert blanks to No, invent PO numbers, or copy a PO onto unrelated rows.

Use the existing preview/apply RPCs, inspect the preview's `pmg_stock_v5` contract and counts, then read back via `pdc_pmg_intake_readback_v3`. Exact replay reuses its receipt. Previously applied v3/v4 receipts remain immutable and replayable; unapplied old previews need a fresh preview. Do not re-import the retained test file as a substitute for the forthcoming fresh export.

## Deployment and validation

Applied STAGING migrations: `20260910083644_tune_navision_details_parts_daily` and `20260910084014_tune_navision_stock_lookup_indexes`.

Full-file transactional regression passed for 121 reused vehicles and 1,395 immutable operations, exact preview/apply replay, Navision precedence, Tune fallback, and red → orange → green changes without duplicate operations or invented ETAs. Checks preserved visibility, location, lifecycle, all bookings, workshop completions and non-Parts work items. Separate rollback tests passed for first-time external Stock creation, supplied VIN, conflicting/duplicate VIN, conflicting Tune customer headers including blank-Stock continuation rows, manual ETA enforcement, legacy receipt replay and unauthorized access rejection. All 342 JavaScript tests passed.

Live readback after deployment: 78 matched Tune vehicles have Navision customer names and descriptions; 43 unmatched vehicles await those fields in the richer Tune export. No test metadata or synthetic vehicles were retained, and no new workbook has been imported. Exact/normalized current Navision Stock lookups are indexed.

New evidence tables are internal, RLS-enabled and denied to application roles; their no-policy advisor entries are intentional. New internal helpers are not exposed to application roles. Existing importer authorization remains unchanged. For Parts acceptance, compare the intake evidence with the latest `parts_update` in the existing vehicle snapshot and the resulting board colour.
