# PDC Email AI v2 — foundation handoff

This handoff is the contract baseline for the isolated STAGING v2 lanes.

## Delivered

- Immutable evidence, typed AI plan, least-authority action request/result, authoritative readback and Board projection schemas under `contracts/`.
- Versioned work taxonomy `contracts/work-taxonomy-v2.json`, incorporating the operator-provided frozen-100 taxonomy audit handoff. Wheel Nut Indicator Set is Tyre; fire-extinguisher hardware/mounting is Fabrication and decal-only is review; FMG signage/safety stripping/GVM-GCM-Tare decals are review-only and must not infer Hoist/Sublet; Long Ranger/Long Range fuel tanks are Hoist.
- Synthetic fixture catalogue for all 14 owner scenarios plus 10 hostile negatives under `fixtures/v2-scenario-catalog-v1.json`.
- Threat/authority model and immutable legacy freeze/inventory.

## Downstream binding decisions

1. Use the exact version strings in `contracts/CONTRACT-INDEX.json`; mismatches fail closed.
2. Treat every instruction as independently disposed; never hide unsupported/review/conflict instructions.
3. Treat historical Board classification as evidence only, never taxonomy authority.
4. Use hosted/provider-neutral transport for v2; `.71` Windows assets are rollback-only.
5. No v2 staging write is authorized by this handoff. Shadow/zero-write and independent review gates remain mandatory.
6. Re-verify all hashes and the legacy freeze identity immediately before activation.

Machine-readable hashes are in `foundation/ARTIFACT-HASHES.json`.
