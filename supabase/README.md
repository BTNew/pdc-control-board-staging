# Supabase Pilot Files

Project URL: `https://vjdtsswhroyguxyfjdkt.supabase.co`
Project ref: `vjdtsswhroyguxyfjdkt`

## Files

- `migrations/001_initial_schema.sql` — core tables, indexes, update triggers, realtime publication entries.
- `migrations/002_rls_policies.sql` — approved-user role helper and RLS policies.
- `migrations/003_rpc_functions.sql` — protected transactional functions for moves, delete/restore and import-run audit records.

## Apply order

Run in Supabase SQL editor in this exact order, or use the Supabase CLI after local login/link succeeds:

1. `001_initial_schema.sql`
2. `002_rls_policies.sql`
3. `003_rpc_functions.sql`

CLI status for this repo:

```bash
npx --yes supabase --version      # verified: 2.109.1
npx --yes supabase init           # completed
npx --yes supabase link --project-ref vjdtsswhroyguxyfjdkt
```

`supabase link` currently requires a local Supabase access token from `supabase login` or `SUPABASE_ACCESS_TOKEN`. Do not paste that token into chat; complete login locally or let the CLI store it in the user profile.

## First administrator

After Microsoft login is configured and the first administrator has signed in once, insert their approved role row from the SQL editor:

```sql
insert into public.pdc_user_roles (email, display_name, role, active, approved_at)
values ('admin.person@company.com.au', 'Admin Person', 'administrator', true, now());
```

Use the real Microsoft 365 email in lowercase.

## Notes

- RLS hides vehicle records from signed-out users and authenticated-but-unapproved users.
- Browser clients should use the publishable key only.
- Secret/service keys must never be placed in browser code.
- Direct vehicle deletes are intentionally not exposed; deletion is a lifecycle change via `mark_vehicle_deleted`.
