# TODO

## High priority
- Add browser-level import → PMB → Parts → RFT and backup/restore failure-path coverage at the supported desktop sizes.
- Plan permanent canonical vehicle IDs and alias-conflict migration as part of the shared backend rather than changing live identities piecemeal.
- Remove operational data from unauthenticated public hosting and complete the requirements/ownership decisions in `BACKEND_MIGRATION_PLAN.md`.
- Re-test Navision upload/paste workflow after every production-board change.
- Validate the new **Fix First** cards with the workshop team using real active vehicles.
- Confirm whether every imported stock vehicle should continue to require Parts sign-off by default.
- Keep Parts, RFT, and PMB screens role-focused so each team sees only fields and actions they can act on.

## Next visual improvements
- Tune the Control Board card density after live review on the actual workshop screen.
- Add stronger ageing bands on PMB and Parts views.
- Keep layout work focused on the desktop and workshop-monitor sizes in use; mobile/tablet support is out of scope.
- Add print-friendly views only after the browser workflow stays stable.

## Keep stable
- Missing or ambiguous vehicle lookup fails closed and never selects the first row.
- Multi-key imports/restores use the recovery journal and roll back on failure.
- `test_all.js` auto-discovers the regression suite.
- PMB transfer lands in Unallocated.
- Job ticks do not auto-allocate PMB production buckets or bays.
- Manual PMB `pmbStage` remains the only production bucket assignment.
- Current marker/job order remains T, H, F, Fa, E, Ty, PI, P.
- Parts must stay production-focused: no salesperson or finance fields in Parts views/exports.
