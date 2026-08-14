# PDC Website Development Lead Boundary

This worktree and `feature/website-development-lead` are owned by the Website Development Lead for frontend website and layout work.

- Craig owns product and workflow decisions.
- Hermes owns authentication/authorization, Supabase client/configuration, environment loading, RLS/grants, service identities, migrations, database objects, Realtime authority, deployment/release workflows, artifact builders, security headers, rollback/recovery and production protection.
- Do not modify Hermes-owned files or integrate an unreviewed backend interface. Record a Backend Contract Request under `docs/website-development/` and continue with frontend fixtures when a website requirement crosses that boundary.
- Never use production credentials, access production, mutate staging, deploy, push, tag or merge to release/security branches without separate Craig authorization.
- Keep QC mobile, workshop schedule and general interface changes in separate commits. Keep the worktree clean between commits and register shared-file changes in `docs/website-development/SHARED-FILES.md`.
- Run the website test matrix in `docs/website-development/TEST-MATRIX.md` for every behavior change.
