# AI Auditor operation-control verification matrix

This matrix binds the source implementation and later staging acceptance. Static/source checks do not substitute for database installation or live two-session evidence.

| Requirement | Source artifact | Local proof | Later staging proof |
|---|---|---|---|
| Review creates no mutation | migration 253 proposal RPC | body/write allowlist test | transaction snapshots unchanged |
| Explicit one-batch Apply | runtime confirmation + 253 Apply RPC | runtime call-sequence and RPC body tests | one instruction applies selected unambiguous set |
| Typed add/edit/split/combine/reorder/deduplicate | migration 253 plan/apply | action/schema/static contracts | fixture readback for every action |
| Department, description, deterministic code, hours | typed edit schema | allowlist/quarter-hour/determinism tests | exact line readback |
| Ordered effective-set receipts | 253 scope receipts | required receipt-column/snapshot assertions | canonical before/after set comparison |
| Aggregate and department hours | 253 snapshot helpers/receipts | aggregate-contract assertions | authoritative readback parity |
| Required-work recalculation | controlled helper call | write allowlist and completed protection | exact required-key before/after |
| Correct Realtime source | app + migration 229/253 RLS | two-consumer harness and static target test | two authenticated sessions, once/run |
| Atomic Apply | 253 preflight-before-write | source-order/write-boundary test | forced failure causes zero writes/history |
| Strict atomic Undo | 253 full preflight and restore | no partial-result/source-order test | conflict causes zero writes; success exact restore |
| Signed gateway envelope | runtime + 253 verifier | one shared canonical-byte/HMAC test vector, expiry and scope tests | real gateway key/signature acceptance |
| Delivery/nonce replay protection | 253 reservation/receipts | unique constraints/idempotency tests | duplicate and conflicting replay probes |
| Manual/completed/later protection | 253 preflight | protection inventory tests | negative fixtures |
| Ambiguity isolation | proposal dispositions and exact selected scope | typed proposal tests | ambiguous lines queued; authorised safe scope applies |
| Forbidden vehicle/user/booking/location/completed writes | 253 write allowlist and revoked helpers | static mutation/grant inventory | role-denial and before/after snapshots |
| Migrations 225–231 contract coverage | focused migration contract test | local aggregate runner | rollback-only install and denial rehearsal |
| Migration immutability | baseline-to-feature Git comparison | exact blob comparison | ledger/hash readback |

## Acceptance rule

A local PASS means the reviewed source contract is internally consistent and regression-clean. Deployment readiness remains blocked until every later-staging proof is completed against the same exact source/migration identities under separate authorisation.
