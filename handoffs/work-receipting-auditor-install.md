# AI Auditor staging installation handoff — owning `work-receipting` profile only

## Immutable approved input
- Source repository: `BTNew/pdc-control-board`
- Approved source commit: `c4183d54583fdb6253f5c6575031de63a79ba82b`
- Staging project: `cdsmnqxtyyoeoznmbidd`
- Database migration head: `231`
- Production/main/DNS: forbidden

## Integrity gate
The owning profile must fetch the source commit and verify:

```bash
git rev-parse HEAD
git status --porcelain
git cat-file -e c4183d54583fdb6253f5c6575031de63a79ba82b^{commit}
git diff --exit-code c4183d54583fdb6253f5c6575031de63a79ba82b -- \
  backend/pdc_auditor_telegram_runtime.py \
  supabase/staging_only/225_ai_auditor_telegram_plans.sql \
  supabase/staging_only/226_ai_auditor_atomic_apply_undo.sql \
  supabase/staging_only/227_ai_auditor_versioned_rules.sql \
  supabase/staging_only/228_proven_duplicate_source_evidence.sql \
  supabase/staging_only/229_auditor_realtime_publication.sql \
  supabase/staging_only/230_auditor_authorization_hardening.sql \
  supabase/staging_only/231_auditor_delivery_registry_reconciliation.sql
```

Do not install if any command fails or if the staging ledger is not exactly 231.

## Required owning-profile secret names
Values must be created/read only inside `work-receipting` protected secret storage and must never be printed:
- `PDC_AUDITOR_ACCESS_TOKEN` — ordinary scoped Viewer/service identity only
- `PDC_AUDITOR_TELEGRAM_BOT_TOKEN`
- `PDC_AUDITOR_TELEGRAM_CHAT_ID`
- `PDC_AUDITOR_BOT_IDENTITY`
- `PDC_AUDITOR_GATEWAY_INSTANCE_ID`
- `PDC_AUDITOR_EVIDENCE_SIGNING_KEY_ID`
- signing key material in the owning gateway secret provider, never in the repo or environment dump

## Required gateway-signature envelope
Activation is forbidden until the gateway creates and the database verifies an asymmetric or keyed signature over a canonical byte representation containing:
- schema/version identifier;
- gateway instance ID;
- bot identity;
- Telegram update ID;
- immutable delivery UUID;
- verified sender ID;
- private chat ID;
- message ID;
- exact UTF-8 command SHA-256;
- Telegram message timestamp;
- gateway received timestamp;
- nonce/key ID.

The database must reject unsigned, malformed, altered, expired, wrong-instance, wrong-bot, wrong-chat, wrong-sender and replayed envelopes. The delivery UUID/update/message identities must share the global operation/rule reservation domain established by migrations 230–231.

## Runtime installation and durable operation
1. Verify the exact source/ledger gates above.
2. Install only `backend/pdc_auditor_telegram_runtime.py` plus a new owning-profile gateway wrapper that produces the signed envelope.
3. Persist raw Telegram update hash, delivery state, attempt count, processing receipt and response receipt before acknowledgement.
4. Configure bounded retry and automatic startup in `work-receipting`; never use development or pdc-monitor secrets.
5. Restart and prove queued-delivery recovery before activation approval.

## Mandatory real staging tests
- Real Review command; zero operational mutation.
- One controlled reversible Apply; exact Apply replay causes zero additional mutation.
- Undo; exact Undo replay causes zero additional mutation.
- Unauthorised sender denied.
- Unsigned, altered, expired, wrong-instance and cross-domain replay denied.
- Gateway restart with one queued command; exactly one final receipt.
- Two distinct authenticated website users receive the same Realtime revision without refresh.
- Roll back temporary mutations.

## Exact remaining activation step
The `work-receipting` owner must implement and independently review the gateway-signature migration/wrapper, then install and run the mandatory real tests. Until that occurs, report `AI Auditor Telegram activation: blocked`.

## Handoff authenticity limitation
This development profile has no configured Git/GPG signing identity. The committed file and generated SHA-256 manifest provide byte integrity and Git provenance, not an identity signature. The owning profile must countersign the verified manifest with its already-trusted gateway/release signing identity; do not generate or copy a private key into this profile.
