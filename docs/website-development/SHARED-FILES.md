# Shared-file register

## Modified by the initial assessment

| File | Classification | Change | Coordination |
|---|---|---|---|
| `AGENTS.md` | Repository instruction | Added Website Development Lead and Hermes security boundary because no repository-local AGENTS.md existed. | Do not broaden into release/security instructions without Hermes. |
| `docs/website-development/*` | Website management | Added durable assessment/control record. | Website Development Lead owned. |

No application, authentication, Supabase, migration, Realtime authority, workflow, artifact, header, production or deployment file was modified.

## High-contention files inspected but not modified

| File | Website interest | Boundary / coordination rule |
|---|---|---|
| `app.js` | QC, Vehicle Locations, Work & Bookings, navigation, dialogs and controls | Shared monolith. Register exact functions/regions before editing; do not alter auth/Supabase/security bridges. |
| `styles.css` | Global responsive layout, production grids, identities and dialogs | Shared global CSS with many override layers. General-interface commit only unless change is strictly QC scoped. |
| `index.html` | Navigation, views and modal shells | Security meta/config order is Hermes-owned. Do not alter CSP or environment/config script order. |
| `workshop-planner.js` | Planner UI and interaction | UI changes allowed; data/RPC/authority semantics are Hermes-owned. Workshop-schedule commit only. |
| `workshop-planner.css` | Planner responsive layout | Workshop-schedule commit only. |
| `workshop-navigation.js` | Work & Bookings/planner navigation and highlight | Frontend contract; coordinate consumers/tests. |
| `workshop-data-service.js` | State displayed by website | Read-only unless Hermes supplies an exact reviewed interface change. |
| `workshop-realtime.js` | Realtime status displayed by website | Realtime authority is Hermes-owned; inspect/test only. |
| `vehicle-lifecycle-actions.js` | QC/PIT action bridge | Hermes-owned integration boundary; do not change independently. |
| `pdc-auth.js`, `pdc-supabase-config.*.js` | Role/config inputs to UI | Hermes-owned; never modify for website work. |
| `package.json`, `.npmignore`, `scripts/verify_npm_pack_inputs.js` | Tests/package exposure | Artifact/release boundary. Changes require Hermes review. |

## Required entry for future changes

For each touched shared file record: backlog ID, commit stream, exact symbols/selectors, reason, tests, Hermes contract SHA if applicable, and collision/integration notes.
