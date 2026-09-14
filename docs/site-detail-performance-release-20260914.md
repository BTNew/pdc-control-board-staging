# Staging vehicle details and performance release

Stock 13073094's report used the Owner Name column, which the Tune normalizer did not recognize. The existing customer aliases now retain their precedence and Owner Name is accepted as a fallback. An exact-source, receipt-backed repair restored that vehicle's customer while preserving its 18 operations, 18.75 hours, Yard Hold location and zero bookings. No model or VIN was present in either available source, so neither was inferred.

The board now requests an additive compact snapshot. It retains all displayed operation, QC, booking, lifecycle and per-job Parts data and drops only unused duplicate payload members. The original endpoint remains available to existing clients. Independent post-deployment verification measured 103 vehicles at 6,751,759 bytes originally and 4,060,567 bytes compact: 39.86% less JSON. All retained values, row order and response metadata matched. This measures payload size, not a promised reduction in total page load time.

Direct dashboard redraws reuse parsed saved notes only during the synchronous render, and group vehicles once before rendering. The 102-row synthetic benchmark reduced note reads from 1,462 to 102 and median HTML generation from 27.43 to 21.84 milliseconds; output was identical. Page helpers avoid rebuilding unrelated hidden pages. Fresh reads after changes and session transitions remain covered by regression checks.

The authorization tests also exposed an existing NULL-role fall-through in the base snapshot. A one-condition repair now rejects missing staff roles while retaining the original allowed roles, query and permissions. Both old and compact endpoints return unauthorized with missing claims.

Validation: 591 Node checks pass. Independent read-only SQL checks pass for 9 authorization cases, 11 response shapes, execution grants, live original/compact parity, zero retained-field mismatches and unchanged original endpoint definition. Supabase security-advisor counts match the pre-change baseline; no new warnings were introduced by these functions. All comparison fixtures and test transactions were rolled back. Only the reviewed functions and exact customer repair were committed to staging.

Local CLI migration files were generated first, then named to match the actual Supabase ledger versions after apply: 20260914053929 (compact read), 20260914054015 (Owner Name alias), and 20260914054444 (NULL-role guard). Deployment identity retains the previously applied migration history and hashes.
