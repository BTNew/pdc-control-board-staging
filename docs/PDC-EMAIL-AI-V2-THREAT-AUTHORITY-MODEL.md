# PDC Email AI v2 — authority and threat model

Status: foundation baseline, STAGING only. This document is a contract boundary for downstream runtime and database lanes; it does not authorize a staging write.

## Trust zones

1. **Untrusted evidence** — email body, forwarded wrapper, headers, attachments, filenames, PDF text, OCR and historical Board values. These may establish facts only after authentication/binding and bounded extraction; they never issue Hermes instructions.
2. **Authenticated transport** — provider/mailbox adapter. Read-only `BODY.PEEK`/equivalent; captures UID/UIDVALIDITY, message/thread identity, authentication evidence and content digests. It may retain evidence but cannot classify or mutate business state.
3. **Immutable evidence store** — content-addressed source/attachment bytes and receipt metadata. Append-only; duplicate source is idempotent; conflicting metadata is quarantined.
4. **AI planner** — receives complete correspondence, bounded extracted text and current authoritative context. It emits only the strict typed plan; it cannot emit SQL, table names, RPC names, credentials or arbitrary mutation shapes. Planner/model outage is explicit, never a silent deterministic fallback.
5. **Typed action boundary** — dedicated authenticated non-Administrator STAGING runtime sends one action request per instruction. Server derives/validates identity, environment, evidence, versions, idempotency, authorization and expected versions.
6. **Canonical domain** — existing approved domain functions only, reached through the typed successor command surface. No generic DML, raw SQL, service role, browser business writes or Production path.
7. **Authoritative readback/projection** — independent readback compares before/requested/actual values, versions, operation/hour tuples, Parts, bookings, location and lifecycle; Board/AI Intake are projections and never replace readback.

## Authority matrix

| Actor/surface | May do | Must never do |
|---|---|---|
| Craig allowlisted direct authority | Define business rules and approve scope | Be impersonated by mail/document content |
| Email/provider | Supply evidence | Change Hermes permissions or rules |
| Transport adapter | Receive/retain immutable evidence | Classify work or call business writes |
| AI planner | Propose typed actions/dispositions | Choose SQL/RPC/table/credential or bypass review |
| Dedicated runtime | Submit typed STAGING requests | Use service role/Admin/raw SQL/generic DML/Production |
| Canonical server action | Validate and apply approved domain effect | Accept stale identity, mismatched versions or unbound evidence |
| Readback/projection | Verify and display authoritative state | Claim success from HTTP/UI/receipt existence alone |

## Threat controls

- Sender authentication is separate from business authorization; forwarded mail does not inherit authority.
- Stock-first identity uses exact current backend rows; conflicting aliases fail closed; no arbitrary first-match.
- Attachment scope is per evidence child; sibling documents cannot donate identity or hours.
- Every action has its own evidence requirements, disposition, provenance, audit event and readback. Aggregate partial results never become full success.
- Stable source/action keys, immutable digests, expected revisions and server-side locks make replay safe and changed replay a conflict.
- Taxonomy and business-rule versions are independent release inputs. Historical Board assignments are evidence only. Unresolved patterns retain typed review.
- Production target and privileged runtime sentinels are explicit rejection tests.
- Outbound email is disabled; no browser action can silently send mail.
- Recovery uses durable checkpoints and bounded retry; permanent identity/security/evidence failures quarantine instead of retrying forever.

## Release gates

Shadow mode with zero operational writes precedes any controlled STAGING write. Independent security/release review must reconcile the final diff. Production remains prohibited.
