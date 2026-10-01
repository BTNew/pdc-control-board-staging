# CodeRabbit Initial Audit

Full staging-code audit requested. Do not approve, merge, deploy, or alter configuration.

Before reviewing code, read `deployment-identity.json` from the audited checkout and verify that its `source_commit` and `frontend_source_commit` match the reviewed source revision, and that its `staging_project_ref` matches the read-only Supabase target. Stop the audit and report the mismatch if any value cannot be verified or differs. Do not change the manifest to make a mismatch disappear.

Review the entire PDC Control Board/Supabase codebase for:

1. Browser-local saves that bypass authoritative Supabase RPCs.
2. Broken or duplicated vehicle save, move, delete, restore, completion-tick, or import paths.
3. Unsafe RLS, SECURITY DEFINER, RPC, or privilege-escalation paths.
4. Realtime failures, stale state, reconnect/resync gaps, and two-user conflicts.
5. Import replay/deduplication failures and duplicate vehicle creation.
6. Missing error handling, race conditions, and failed optimistic-update rollback.
7. Staging-versus-production configuration leaks.
8. Critical business workflows not covered by meaningful automated tests.

Use read-only checks where possible. For a write-path reproduction, use disposable staging fixtures only and verify cleanup or transaction rollback before closing the test. Do not mutate shared operational records.

For each finding provide: severity, exact file/line, real-world effect, reproducible scenario, and the smallest safe fix. Do not make cosmetic-only comments.
