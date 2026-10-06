# Revolution automated parts report

Craig's 6 October 2026 import request identified the automated **PMG PD Parts Status Complete - Pilbara** report. The staging parts importer now accepts this specific source without disguising it as an owner email or direct attachment.

Use `revolution_automated_parts_workbook` with the original Gmail message and attachment hash, actual receiving-provider authentication, and owner-request evidence. Accepted sender is exactly `noreply@revolutionsoftware.com.au`, receiving mailbox is `pmbcontroller@gmail.com`, subject is exactly the report title above, and filename is `PMG PD Parts Status Complete.xls` or `.xlsx`. Inspect file bytes: this route accepts OOXML, including the producer's `.xls` extension, not an assumed legacy binary workbook. Preserve the complete mixed-department original privately.

Both receiving Gmail SPF for the exact sender and aligned DMARC must pass. Bind the authentication object to the same Gmail message ID, mailbox, direct sender and report. Reject alternate Reply-To, mismatched evidence, other subjects and other senders. Existing Craig and Bhavesh paths retain their rules. The route remains management-only, security invoker, and staging-only; there are no new API grants, account activations or person-confirmation privileges.

Scope is Company `01`, Division `1`, Department `138`. Aggregate valid numeric flags by exact R/O; preserve row-level evidence. Exclude Department 139 before application. The server also rejects non-138 payload rows and mixed-department target jobs. Only existing exact active visible board jobs receive parts-feed updates. Missing, hidden, completed, purged or conflicting jobs remain held: parts reports never create or approve vehicles, operations or bookings.

Retain the producer's verified timezone for the extraction timestamp. This report's extraction minute matched its originating email Date with `+1100`; do not reinterpret that hour as Perth. Existing stale/equal-snapshot, stock-conflict, numeric/PO-consistency and attachment replay protections remain active.

“Complete” in the report name is not a person confirming physical receipt. Recalculate vehicle colour across all active linked jobs and retain person-confirmed outlines and stage-readiness requirements.

## Validation

Applied staging migration `20261006033522_revolution_dept138_parts_email` contains deployment assertions with all synthetic fixtures and receipts rolled back. Cases cover accepted reports, sender/authentication binding, wrong source/company/division, Department 139 rejection, mixed/hidden/missing jobs, replay conflict, stale/equal snapshots, numeric flags, PO consistency, backorder clearing and unchanged public grants.

Nine focused parts projection checks passed. Full local suite: 1,669 passed, 14 failed; the identical 14 failures reproduce on untouched upstream `97f6d17`, including historical fixture/snapshot and touch-drag extraction failures. No frontend code changed. Security advisors reported no finding on either changed function. Live report readback verified all 42 matched job updates across 39 vehicles, three changed flags, 39 unchanged flags and 29 unmatched R/Os. A guarded transaction proved vehicles, operations, hours/adjustments, bookings, person confirmations, untargeted jobs and importer disabled state unchanged. Private mail/workbook and per-row receipts are retained outside the public repository.
