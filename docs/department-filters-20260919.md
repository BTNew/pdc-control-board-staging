# Department filters — staging

New Vehicles and Vehicle Locations now offer All departments, 138 — Bus 4×4, and 139 — PD. The browser remembers one selection for these two views. The Control Board, station planners, Tint, bays and booking records remain combined.

Membership uses active imported operation departments, including all source lines before display limits. Mixed vehicles appear in both relevant views without duplication. Unknown departments remain in All departments. These are display filters, not account access restrictions.

New Vehicles queue, updates, unidentified groups, counts and bulk preflight filter on the server before pagination. Quick and bulk approval within a department require exclusively confirmed work for that department. Mixed or unknown work requires explicit Review, showing all operations before the existing whole-card approval. Pending responses from an old selection are discarded. Selection changes during an approval are deferred until its result is handled.

Vehicle Locations filters rows, bucket counts, stoppages and selected-vehicle actions locally using uncapped server membership. The global workshop data is untouched.

Validation:

- 1,173 JavaScript regression tests passed, including 30 new department tests and existing booking, planner and approval tests.
- 43 transaction-scoped database assertions passed and all fixtures rolled back. Covers pagination, mixed/unknown/inactive work, 251-line membership, counts, approved-reader authorization, denied roles, exact legacy response/hash parity and unchanged bookings.
- Three-sample database timing comparison: location snapshot minimum 1,688.50 ms before / 1,690.09 ms after; queue mean 74.15 / 74.77 ms. Department counts 1–2 ms. No measurable regression in this sample.
- Desktop and 390-pixel mobile browser fixture: both selections, preference persistence after reload, Clear filters, mixed card approval state, stoppage counts and hidden selection clearing verified. Synthetic data only; no live approvals made.
- Changed frontend assets contain no privileged keys. Database advisor notices for the four new authenticated SECURITY DEFINER APIs are intentional: each requires an approved active reader with matching user/email; anonymous execution and direct helper execution are revoked. Existing unrelated notices remain unchanged. [Supabase function access guidance](https://supabase.com/docs/guides/database/functions#function-privileges).

Migration was created using the Supabase CLI, then its filename aligned to hosted apply version `20260919064604`. SQL SHA-256: `70e9a5ff4014fb6a90e4c3b73a7f03a4307aa8a18742d49c7fed6eb0c5c16206`. Staging only. No booking, vehicle, technician or approval data was changed by the migration.

The two pre-existing Control Board search tests now use their fixture clock for live carry-over projections, avoiding calendar-dependent failures. Production Control Board behavior is unchanged.
