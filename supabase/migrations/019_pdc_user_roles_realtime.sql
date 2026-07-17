begin;

-- Migration 019: add pdc_user_roles to the Supabase realtime publication
-- so account-status changes (approve/reject/disable/restore/role
-- change) can be pushed live to any open browser session -- e.g. a
-- pending user's "awaiting approval" screen updating automatically the
-- moment an administrator approves them, and the User Management screen
-- refreshing across two open administrator sessions without a manual
-- reload. RLS on pdc_user_roles (unchanged by this migration) still
-- governs exactly which rows each realtime subscriber receives: a
-- signed-in user only ever receives their own row; an administrator
-- receives every row.
alter publication supabase_realtime add table public.pdc_user_roles;

commit;
