# Shared Files

## Authoritative Vehicle detail saves — 2026-08-25

- `app.js` — shared Vehicle detail Save orchestration, receipt-backed salesperson/detail RPC dispatch, authoritative reconciliation, and poisoned legacy consultant cleanup.
- `pdc-email-vehicle-location-service.js` — canonical snapshot mapping plus salesperson and allowlisted detail RPC clients.
- `index.html` — cache-busted staging asset references for the authoritative detail tranche.
- `supabase/staging_only/20260825230000_386_authoritative_salesperson_assignment.sql` through `20260825235000_391_detail_stale_receipt_repair.sql` — staging-only authoritative detail contracts, synthetic route containment, snapshot convergence, and stale receipt repair.
- `test_authoritative_salesperson_assignment_386.js`, `test_email_authoritative_board.js` — contract, RPC-body, and poisoned-local-storage negative coverage.

## Parts ordered authority closure — 2026-08-25

- `app.js` — shared Parts projection, queue rendering and mutation handlers; this change keeps canonical Parts requirement and viewer access fail-closed.
- `pdc-email-vehicle-location-service.js` — shared Parts RPC error normalization.
- `styles.css` — not changed by this task.
- `supabase/staging_only/20260825220000_385_parts_order_authority.sql` — append-only staging trigger correction for ordered Parts writes.
