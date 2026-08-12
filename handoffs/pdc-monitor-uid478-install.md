# PMB Email Monitor staging handoff — owning `pdc-monitor` profile only

## Approved release baseline
- Release: `pdc-monitor-staging-runtime-2026.08.12.5`
- Source: `bf403f75dd4545bbb339e444ce1a38c25c4235ee`
- Staging deployment: `4c86b319aa5f45e4cfecfe6726506b366077cc7b`
- Release migration head: 224
- Manifest SHA-256: `89ae5143d5a24210d6bcec22fd04f3e111b9353a984dfa9b3eb9ab17452140bd`
- Current staging database head: 231; never downgrade.
- Staging project only: `cdsmnqxtyyoeoznmbidd`.

## Compatibility gate
Migrations 225–231 are append-only Auditor tables/functions, privilege hardening, Realtime publication, and Telegram delivery reconciliation. The owning profile must still run the release verifier and a read-only smoke test against head 231 before startup. Do not modify approved release bytes merely to change the expected ledger head; record head-231 compatibility as a separate attestation.

Required checks:
```bash
python runtime_release/verify_release.py \
  --bundle <verified-release-directory> \
  --expected-manifest-sha256 89ae5143d5a24210d6bcec22fd04f3e111b9353a984dfa9b3eb9ab17452140bd
```
Then, using only scoped identities inside `pdc-monitor`, verify:
- project ref is exactly `cdsmnqxtyyoeoznmbidd`;
- remote migration ledger is exactly 231 or a later separately approved staging head;
- release-required RPC signatures still exist;
- direct Monitor DML remains denied;
- outbound-email policy remains disabled;
- queue claim/receipt dry run succeeds without mailbox mutation.

## Required protected secret names
Provision values only in the owning profile’s protected secret store; never print them:
- `PDC_MONITOR_ACCESS_TOKEN`
- `PDC_SUPERVISED_MONITOR_JWT`
- `PDC_SUPERVISED_ACTOR_JWT`
- `PDC_MONITOR_GATEWAY_INSTANCE_ID`

The supervised actor must be a separately enrolled scoped identity. Never reuse an Importer session or any development/work-receipting identity.

## Mailbox boundary and replay point
- Mailbox UIDVALIDITY: 1.
- UIDs 1:470 through 1:477 are permanently excluded from this activation and must not be fetched, flagged, marked, requeued or otherwise touched.
- Retained item: UID 1:478 only, subject `Fw: New Vehicle Builds`.
- Do not resend the email and do not change mailbox flags.
- Advance durable high-water to 478 only after every attachment has an immutable terminal receipt (`applied` or `review`) and the message-level aggregate receipt is committed.

Expected attachments:
- `12658679.pdf`: JC J139124174, 20 lines, VIN MR0MABAVX02401646; Stock absent from PDF body. Require filename + JC + VIN + backend evidence; filename alone is insufficient.
- `12661296.pdf`: JC J139125297, 5 lines.
- `12550488.pdf`: JC J139124665, 23 lines.
- `12535460.pdf`: JC J139125061, 14 lines.

## Attachment-atomic contract
For each attachment independently:
1. Hash original bytes before parsing.
2. Persist mailbox, UIDVALIDITY, UID, received date, filename, byte hash and original extracted values.
3. Resolve with reliable Stock, JC, Key, VIN and backend evidence.
4. Apply through the canonical importer only when one exact vehicle is proven.
5. Preserve completed/protected/manual/Auditor changes, Parts/Sublet/Job Stoppage/location/booking history, RFT and Completed lifecycle.
6. Queue ambiguity for review without blocking other attachments.
7. Replays return the existing attachment receipt and create no duplicate vehicle, line, history or revision.
8. Publish successful updates through the existing revision/Realtime path.

## Startup and restart recovery
- Persist claim token, delivery attempt, attachment receipts and aggregate message receipt before acknowledging UID 478.
- Configure bounded retry and automatic startup only in `pdc-monitor`.
- Kill/restart between attachment receipts during rehearsal; prove already-receipted attachments are not repeated and the next unresolved attachment resumes.
- Keep outbound email disabled throughout.

## Exact remaining activation step
The `pdc-monitor` owner must provision the four scoped values, verify approved release `.5` against head 231, then replay UID 1:478 under the attachment-atomic gate. Until those checks and receipts exist, report `PMB Email Monitor runtime: blocked on owning-profile scoped provisioning`.

## Handoff authenticity limitation
This development profile has no configured Git/GPG signing identity. The committed handoff and SHA-256 manifest provide byte integrity and Git provenance, not an identity signature. The owning profile must countersign the verified manifest with its trusted release identity; never copy or create signing secrets here.
