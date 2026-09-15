# Board usage reporting

Admin → User Management includes an administrator-only Board usage report for the last 7, 30 or 90 days. It shows last sign-in, last activity, distinct sign-in sessions, active Perth calendar days, page visits, click totals and pages used. Counts begin when tracking is installed; earlier clicks and visits cannot be reconstructed.

The report starts with the most recent last activity first. Each name, date or count header can be selected to sort, and selected again to reverse its order. The Sort by and direction controls stay in sync with the headers. Missing dates stay at the bottom in both directions. Search matches staff names or emails. Activity filters show all staff, staff active now, those who used the board in the selected period, or those with no recorded usage in that period. Usage in a period means any positive sign-in, active-day, page-visit or click count; a historical last-activity date alone does not qualify. Search, filtering and sorting reuse the loaded report without additional requests.

A green dot and “Active now” indicate a recent click or page visit within the last two minutes in a signed-in session. An inactive status does not establish that someone has signed out; an open, idle board is not active. Presence is supplied by the report's `active_now`, `presence_last_active_at`, `active_window_seconds` and `generated_at` fields. The browser expires the status as time passes and considers report snapshots older than 60 seconds, missing presence information or failed refreshes unavailable. It measures elapsed time from the server report timestamp using a monotonic browser clock so an inaccurate workstation clock does not change the result.

While an administrator has User Management visible, the report refreshes every 30 seconds. Background refreshes retain the table, selected filters, sorting, expanded page details, keyboard focus and horizontal scroll. Hidden pages do not refresh or render the report. Failed refreshes retain the last loaded counts with a stale-data message and unavailable current status. Switching accounts or roles clears the report and its view settings; late replies from a previous request or account cannot restore them.

The browser records only allowlisted page names and numeric visit/click totals. It does not collect typed text, passwords, form values, vehicle identifiers, click target labels, IP addresses or screen recordings. Clicks and visits are usage indicators, not a measure of completed work. No idle heartbeat or additional interaction tracking is added for presence.

Activity is batched every 15 seconds with best-effort flushing when a page is hidden. Each batch has a unique ID so network retries do not double count. Authentication session IDs deduplicate sign-ins across page reloads. A principal change clears unsent data; requests capture the matching bearer token before asynchronous work. Client failures or closing a page can leave small gaps in click totals.

The database derives identity from the authenticated session and checks current approved staff access. Report reads require an active administrator linked to the authenticated user ID and email. Public RPC wrappers use invoker security; privileged implementations are in the non-exposed pdc_usage_private schema. All private tables use RLS, have no direct client grants, and intentionally have no direct-read policies. Records are retained for 180 days and pruned during subsequent activity.

Validation includes database rollback checks for administrator-only reports, signed-out denial, bounded click batches, repeat-request deduplication and unique sign-in counting. Browser queue tests cover signed-out collection, changing users, page attribution and payload minimization.

Individual account provisioning and password handover are a separate owner-authorized operation. No staff password file or provisioning capability is included in this repository.

