# Current State

Generated for handover on 2026-07-13.

## What currently works
- Static GitHub Pages app loads from `https://btnew.github.io/pdc-control-board/`.
- Baseline bundled dataset contains 200 random/test vehicles, not the older online dataset.
- Vehicle Locations view loads and shows 200 vehicles.
- Control Board view renders without browser-console errors in smoke testing.
- Parts page active queue, status filters, ETA countdown labels and email-sales action are implemented.
- Parts ETA update stores current ETA in `pdcPartsWorstEta` and previous value in `pdcPartsPreviousWorstEta`.
- Parts ETA email draft includes vehicle details, previous ETA, new ETA and revised countdown.
- Navision import tests, Parts/production tests, data integrity tests and review alignment tests pass locally.
- PMB stage data uses internal keys including `TYRE` and `PIT_INSPECTION`.

## What is partially working
- Salesperson email routing is centralised through `salespersonEmail(vehicle)` and currently returns the configured RFT salesperson email constant. If true per-salesperson email mapping is required, add fields/mapping and tests.
- `CHATGPT_HANDOVER.md` in the committed repo may not contain its own final commit hash because Git commit hashes are content-addressed. The handover ZIP includes a generated copy with the final commit hash filled in.
- The app is static and browser-local; it has no server-side user accounts, database, or multi-user sync.

## What is broken
- No known broken automated tests at handover.
- No known live deployment blocker at handover.

## What was being worked on at handover
- Handover documentation and packaging.
- Parts page ETA countdown/email feature was reviewed and completed with previous-ETA handling and tests.

## Exact next action for another agent
1. Unzip the handover package.
2. Read `CHATGPT_HANDOVER.md`, `BUSINESS_RULES.md`, `MAINTENANCE_INSTRUCTIONS.md`, and this file.
3. Clone or open `https://github.com/BTNew/pdc-control-board` on branch `main`.
4. Run the test commands in `CHATGPT_HANDOVER.md` before making changes.
5. If continuing product work, next priority is to add a real salesperson-email mapping if Craig wants emails addressed to each actual salesperson instead of the current central contact.

## Local cleanup note
- A pre-existing untracked backup ZIP may exist in Craig's local repo folder. It is not part of the committed repository and is intentionally excluded from the handover ZIP.
