# Fitter-only access

The `fitter` role opens directly in Fitters bay. Other navigation and direct/hash routes cannot open other board sections. Fitter accounts can select an active mechanic and use the existing assigned-job workflow.

The database role has no ordinary viewer, controller, importer or administrator authority. Fitter authorization is bound to the authenticated user ID, email, approved account status and the dedicated PostgREST fitter endpoint. The existing start/stop/resume/complete routines retain their assignment, version, lifecycle and scheduling checks. An additional pre-request allowlist denies legacy RPCs, views and tables outside the fitter workflow and own-role/usage endpoints. Ordinary account permissions are unchanged. Direct-table/Realtime/Storage checks do not receive fitter endpoint authority.

Validation: 876 JavaScript checks passed; fitter-only permission rollback checks passed, including disabled-account rejection and controller parity. The fitter lifecycle rollback suite passed with synthetic fixtures and unchanged existing vehicles/bookings. Frontend secret scan reported no findings. No real vehicle work was changed by testing.

Account creation is a separate administrator action. Passwords are not stored in the repository. The fitter account must receive this dedicated role, never the controller role.
