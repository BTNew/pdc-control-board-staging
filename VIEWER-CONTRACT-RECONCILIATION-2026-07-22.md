# Viewer contract reconciliation — 2026-07-22

This records the approved hardened role contract used to correct stale staging expectations. No viewer privilege or implementation was widened.

## Vehicle rows

- **Approved role contract:** authenticated `viewer` users receive zero rows from direct `public.vehicles` REST reads. `operator`, `importer`, and `administrator` remain eligible under RLS.
- **Approved viewer interface:** `get_restricted_pilot_vehicle_snapshot(uuid)` for the exact retained restricted-pilot source batch only.
- **Intended viewer fields:** exactly `id`, `version`, `current_location`, `lifecycle_state`, `workshop_status`, and `active_workshop_booking_id`.
- **Intended result:** direct `GET /rest/v1/vehicles?...` returns HTTP 200 with `[]`; the restricted RPC returns HTTP 200 with a list containing only the six approved fields (an empty list is valid when the retained batch has no matching row).
- **Why the old expectations were wrong:** they predated migration 032, which deliberately replaced the broad `vehicles_select_approved` policy with operator-only direct reads and introduced the restricted six-field viewer RPC. Expecting arbitrary direct vehicle rows contradicted that approved restricted-pilot boundary.

Corrected tests:

- `_staging_test_tools/test_account_approval_staging.py`
- `_staging_test_tools/test_role_access_matrix_staging.py`

## Workshop reference lists

- **Approved role contract:** `list_technicians`, `list_salespeople`, `list_sublet_providers`, and `list_workshop_bays` require `operator` or higher. Viewer access is denied inside each security-definer function.
- **Intended fields:** no reference-list fields are returned to viewers. Operators receive each RPC's declared table row type; inactive inclusion remains controlled by `p_include_inactive`.
- **Intended result:** viewer RPC calls return HTTP 403 with PostgreSQL code `42501`; operator/administrator calls return HTTP 200.
- **Why the old expectations were wrong:** migration 035 intentionally hardened these RPCs from viewer-readable active-only lists to operator-only lists. The old final-remediation assertions still expected the superseded migration-025 behavior.

Corrected test:

- `_staging_test_tools/test_stage2a_final_remediation_staging.py`

## Security decision

The database implementation matches the approved restricted-pilot policy. Only stale test expectations were changed; no RLS policy, RPC role check, grant, or viewer-readable field was relaxed.