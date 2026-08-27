# Staging second Navision delivery security closure — 2026-08-27

Staging only: Supabase project `cdsmnqxtyyoeoznmbidd`. Production was not changed.

## Applied successors

- `20260827113000` — `709_close_navision_delivery_overloads_and_body_location_bypass`
- `20260827115000` — `710_body_location_intake_alias_repair`
- `20260827116000` — `711_body_location_canonical_delivery_eligibility`
- `20260827117000` — `712_body_location_collected_visibility_eligibility`
- `20260827118000` — `713_close_navision_prefixed_family_acl_bypass`

The chain was applied append-only after observed concurrent Monitor heads 678 and 679, and later re-read after concurrent heads 680–682. Migrations 700–708 were preserved; none was rewritten, reapplied, reset, or rolled back.

## Security result

709 records a complete `pg_proc`/`pg_namespace` overload inventory for both Navision delivery families and revokes all family permissions, including default-bearing predecessors. 713 adds the complete prefixed-family inventory and closes historical/private predecessors, including the observed service-role `pre134` legacy 169 path. Only the exact authenticated one-argument delivery route and exact authenticated three-argument compatibility wrapper remain callable; no default, named-argument, anon, service-role, monitor-role, or wrong-actor bypass remains.

The full completion/location inventory records all matching public functions and Navision/body-location triggers, including the legacy 169 path. The authenticated body-location function retains ETA, Yard Hold, and Body Builder processing. Exact `Delivered - At Dealer` is no longer a direct body-location completion write: it requires live authenticated identity/scope, one exact current linked Navision record, and routes through canonical 700 delivery logic. 710 repairs the existing intake alias collision; 711–712 allow only the legitimate `rft`/`Collected`/`visible_on_board=false` tuple to reach that canonical route; 713 closes the prefixed legacy family, including the observed service-role pre134 path.

## Verification

- Focused contract: 6/6 passed.
- Live staging suite: 3/3 passed; final read-back after concurrent heads 680–682 remained secured.
- Hostile calls: generic, viewer, operator, administrator, anon, service role, wrong actor, overload/default/named-argument paths denied as expected.
- HERMES-TEST rollback-only behavior: canonical delivery succeeded once; replay returned the immutable result; timer duration was non-negative; exactly one delivery receipt, audit event, and movement were produced; body-location exact status reached the canonical result; ETA non-delivery remained active and moved to IT; synthetic rows were rolled back.
- Repository gates: `npm run test` — 226 passed, 0 failed, 1 skipped. `npm run check` — 226 passed, 0 failed, 1 skipped.

## Source hashes

- 709: `eb6dfa6271cd30bdd3b06e9d55db4ca0879348ccddeee46b3afee21f1336b0a7`
- 710: `124293ace468dcacaa49338ad2657dafa75ddeec382bbd5bb0546502d6b7526c`
- 711: `720f2112c7ab2b314101bd947989e41529a54b974f48a79bfd4c8d37badf3a50`
- 712: `496e06141becfdc9937f99c602d67819d672663b5b183525f50b4d39c64c25ef`
- 713: `d5f237112fe3dbe75d86d97361e3a9dc3009d9b518a274a35d020107b4c7ed08`
- Contract test: `fda5c2e29d4b27ea8cf85c0199d720884a3e3a9bc21870e7de5b1b823021d1f5`
- Live test: `9570b2a4ba1bf541af71ac18ae231962d1c453e5f69ed3c1eee3508ba6301bdd`
