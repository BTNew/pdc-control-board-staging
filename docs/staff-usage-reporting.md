# Board usage reporting

Admin → User Management includes an administrator-only Board usage report for the last 7, 30 or 90 days. It shows last sign-in, last activity, distinct sign-in sessions, active Perth calendar days, page visits, click totals and pages used. Counts begin when tracking is installed; earlier clicks and visits cannot be reconstructed.

The browser records only allowlisted page names and numeric visit/click totals. It does not collect typed text, passwords, form values, vehicle identifiers, click target labels, IP addresses or screen recordings. A short sidebar notice explains the tracking. Clicks and visits are usage indicators, not a measure of completed work.

Activity is batched every 15 seconds with best-effort flushing when a page is hidden. Each batch has a unique ID so network retries do not double count. Authentication session IDs deduplicate sign-ins across page reloads. A principal change clears unsent data; requests capture the matching bearer token before asynchronous work. Client failures or closing a page can leave small gaps in click totals.

The database derives identity from the authenticated session and checks current approved staff access. Report reads require an active administrator linked to the authenticated user ID and email. Public RPC wrappers use invoker security; privileged implementations are in the non-exposed pdc_usage_private schema. All private tables use RLS, have no direct client grants, and intentionally have no direct-read policies. Records are retained for 180 days and pruned during subsequent activity.

Validation includes database rollback checks for administrator-only reports, signed-out denial, bounded click batches, repeat-request deduplication and unique sign-in counting. Browser queue tests cover signed-out collection, changing users, page attribution and payload minimization.

Individual account provisioning and password handover are a separate owner-authorized operation. No staff password file or provisioning capability is included in this repository.
