# Bugs / Watch List

## Open watch items
- GitHub Pages is unauthenticated and ignores `staticwebapp.config.json`; the operational `data.js` baseline must not be served there.
- RFT gate logic should be reviewed with real-world examples to confirm every required job blocks RFT until signed off.
- Browser localStorage data depends on each PC/browser. Users must export backups before clearing browser data or switching machines.
- Parts currently treats imported vehicles as needing Parts follow-up until signed off; confirm with Craig if exceptions are needed.
- Completed and Back End Data tables may still require horizontal scrolling on narrower desktop screens; Parts now owns its scrolling inside the queue.

## Recently addressed
- Missing/ambiguous vehicle selection now fails closed, with dedicated wrong-row regression coverage.
- Navision, PO/job-card, removal and restore changes use a storage recovery journal with rollback and startup recovery tests.
- `test_all.js` now auto-discovers regressions and treats unavailable external PDF fixtures as an optional skip.
- Missing app references causing startup/runtime issues were fixed.
- PMB first-landing protection was added so imported requirements do not bypass Unallocated.
- Parts page was cleaned up to avoid irrelevant Navision/production-only fields.
- Parts was rebuilt as an eight-column desktop queue and direct row deletion was removed from Parts and RFT.
- Test-only local-data reset URLs can no longer clear the live index page by default.

## Regression checks required before an approved deployment
- JavaScript syntax checks pass.
- Navision/import validation helper passes.
- Local browser console has no errors.
- The approved authenticated production environment has no browser/API errors after deployment; Pages checks are synthetic-data demos only.
- PMB Unallocated and manual bucket rules still work.
