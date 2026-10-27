# Faults waiting for an automated check

Craig, 28 Oct 2026 06:29 AWST: make sure these faults do not happen, and keep a log so the tests can be run.

A row under **Open** has no `test_*.js` file in the website run (`node --test test_*.js` in `.github/workflows/pages-runtime.yml`) and no `pdc_ops.regression_checks` row. A row under **Cleared** has one of those checks and is not an open gap.

## Open

None in this preview.

## Cleared

| Fault | Check |
|---|---|
| #542 / r560 / F174. Clicking a stock number opened the centred Vehicle detail card. It must open the Vehicle Locations side panel. More details is the only way to the old card. | `test_stock_opens_side_panel_560.js` in the website regression run. No SQL. |
