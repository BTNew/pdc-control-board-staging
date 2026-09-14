# Completed vehicle history and turnaround

Staging-only presentation repair, 14 September 2026. No database migration or vehicle mutation.

## Restored visibility

A thinner Navision mirror replaced the canonical completed vehicle and then failed a second delivery filter. The table became empty while its independently calculated statistics still counted the vehicle. History now retains canonical identity and evidence, includes completed records independently of current import-file presence, and merges only explicit record links. Same-stock vehicles from different dealers remain separate. Search, statistics and CSV use the same retained rows.

The existing completed record is restored to view. Existing completed vehicles, transport receipts, transit statistics and lifecycle events remain stored. Seven database rollback assertions verified repeated OD, later non-OD and missing-source retention without changing stock or milestone dates. No record was recreated, delivered or moved during this repair.

## Milestones and precision

The table shows stock/job card, customer/vehicle, PMB recorded, RFT, OD recorded, PMB-to-RFT, RFT-to-OD, and total PMB-to-OD. Details retain key, separate collection timestamp/actor and completed stations. Open vehicle is offered only when its existing local lookup resolves a unique matching identity.

- PMB uses its retained lifecycle timestamp, or the explicitly recorded PMB date with date-only precision. ETA is never treated as arrival.
- RFT uses the retained first RFT milestone, falling back to the saved RFT transfer or recorded date.
- OD uses the retained delivery confirmation timestamp. It means the application first recorded Navision's Delivered to dealer status, not proof of physical delivery at that instant. Collection is never substituted for delivery.
- Mixed date-only intervals use Perth calendar days and do not fabricate exact seconds. Exact timestamps retain elapsed hours/minutes. Missing, invalid or reversed endpoints remain unknown and are excluded from averages.
- The CSV preserves milestone values, precision, days and exact seconds where supported, alongside the separate pickup evidence.

For the restored record, the saved PMB date is 12 September (date only), RFT is 14 September 10:30 Perth, and OD was recorded at 14:26 Perth: RFT-to-OD is 3h 56m. The Navision source's older status date precedes this work cycle, so it does not replace the preserved delivery confirmation.

## Verification

614 frontend checks passed, including 17 new runtime regression cases. These exercise the actual Navision mapper, identity selection, string dates, null/zero/reversed durations, three intervals, filtered statistics, CSV, retained noncurrent rows and unambiguous Open actions.

Seven database retention checks ran under rollback. Existing customer data, receipts and timestamps were retained. Desktop browser verification using the real render functions confirmed the restored row, independent collection details, matching search/statistics and compact table layout. A 200-row helper timing probe completed in 39 ms; date formatters are reused and no new server requests are added.

Files: `test_completed_history_timing_20260914.js`, `test_completed_vehicle_history_20260914.js`, and `tests/verify_completed_retention_rollback.sql`.
