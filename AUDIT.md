# CodeRabbit Initial Audit

Full staging-code audit requested. Do not approve, merge, deploy, or alter configuration.

Review the entire PDC Control Board/Supabase codebase for:

1. Browser-local saves that bypass authoritative Supabase RPCs.
2. Broken or duplicated vehicle save, move, delete, restore, completion-tick, or import paths.
3. Unsafe RLS, SECURITY DEFINER, RPC, or privilege-escalation paths.
4. Realtime failures, stale state, reconnect/resync gaps, and two-user conflicts.
5. Import replay/deduplication failures and duplicate vehicle creation.
6. Missing error handling, race conditions, and failed optimistic-update rollback.
7. Staging-versus-production configuration leaks.
8. Critical business workflows not covered by meaningful automated tests.

For each finding provide: severity, exact file/line, real-world effect, reproducible scenario, and the smallest safe fix. Do not make cosmetic-only comments.
