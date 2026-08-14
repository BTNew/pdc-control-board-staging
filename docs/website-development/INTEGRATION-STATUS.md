# Integration status

## Approved baseline

- Commit: `2f89fa5e93425ec22babf01065889d0611c6d817`
- Tree: `17cc47a4edbcc7bc7ceb422ce170e5ca070508a3`
- Branch: `feature/website-development-lead`
- Initial assessment started from an exact clean worktree at that commit/tree.

## Hermes security integration

- The approved baseline is the only supplied integration point.
- No later Hermes security SHA or reviewed backend contract was supplied to this task.
- No authentication, Supabase configuration/client, environment loading, role authority, RLS/grant, migration, database, Realtime authority, deployment, artifact, header, rollback/recovery or production file was changed.
- No integration, rebase, merge, push, deployment or staging mutation was performed.

## Website integration state

| Area | State | Notes |
|---|---|---|
| QC mobile | Frontend reliability implemented locally | Parent `015aa0a`; existing lifecycle functions/payloads unchanged. Final IA/copy decisions remain blocked. |
| Workshop schedule | Assessed; implementation not started | Existing shared service/Realtime contracts inspected only. |
| Work & Bookings | Assessed; implementation not started | Existing narrow detail/mutation interfaces inspected only. |
| Vehicle identifiers | Assessed; implementation not started | Frontend projection identified. |
| General responsive/accessibility | Vehicle Details ordinary lifecycle implemented | Focus trap/inert/return while auth state is unchanged; BCR-001 blocks the protected auth-refresh inert-ownership race. Remaining overlays not changed. |
| Test harness | QC fixture runner implemented | Six Chrome viewports, keyboard, rerender-safe rapid action, print failure, resource/console/no-external checks; full matrix remains. |

## Current boundary verification

- Website work is based on assessment parent `015aa0a0ef3c5d26ee4310959a749d5c24957f78`, whose approved security ancestor is `2f89fa5e93425ec22babf01065889d0611c6d817` / tree `17cc47a4edbcc7bc7ceb422ce170e5ca070508a3`.
- No later Hermes security SHA or backend contract was integrated.
- Modified application surfaces are limited to `app.js` rendering/interaction/print presentation and the final `styles.css` responsive cascade, plus frontend tests/docs.
- No Supabase/config/auth, migrations/SQL, backend, Realtime authority, workflow, package inventory, artifact, release, deployment, staging or production file was edited.
- BCR-001 is pending Hermes review because `pdc-auth.js` can remove `#app-shell` inertness during auth refresh while Vehicle Details remains open. The protected file was not edited and no universal auth-transition isolation claim is made.

## Gate before future integration

1. Craig resolves the relevant decision IDs.
2. Website Lead classifies frontend-only versus Backend Contract Request.
3. Hermes supplies the exact reviewed interface and approved security SHA for any protected dependency.
4. Shared-file register names exact touched symbols/selectors.
5. Required local matrix passes with zero production requests/private package inputs.
6. Integration remains a separate authorized action; never infer push/deploy permission from code approval.
