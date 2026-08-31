# Secretless environment contract

Names only. Values are supplied by the protected owner/runtime connector at execution time and are never recorded in this pack.

## STAGING Supabase owner provisioning

- `PDC_STAGING_SUPABASE_URL`
- `PDC_STAGING_ANON_KEY`
- `PDC_STAGING_ADMIN_EMAIL`
- `PDC_STAGING_ADMIN_PASSWORD`
- `PDC_STAGING_SERVICE_ROLE_KEY` — owner provisioning only; never runtime

## Dedicated runtime

- `PDC_SUCCESSOR_RUNTIME_SECRET_STORE` — protected DPAPI/ACL path supplied by the owner profile
- `PDC_SUCCESSOR_RUNTIME_EMAIL` — identity metadata only; not a password
- `PDC_SUCCESSOR_RUNTIME_GATEWAY`
- `PDC_SUCCESSOR_RUNTIME_MAILBOX_SCOPE`

## Mailbox/sender owner lane

- `PDC_EMAIL_AI_NATURAL_PROOF_SESSION`
- `PDC_EMAIL_AI_SENDER_CONNECTOR`
- `PDC_EMAIL_AI_RECIPIENT_MAILBOX`
- `PDC_EMAIL_AI_UIDVALIDITY`
- `PDC_EMAIL_AI_ACTIVATION_HIGH_WATER_UID`
- `PDC_EMAIL_AI_TRANSPORT_COMMAND`
- `PDC_EMAIL_AI_SAFE_SEND_COMMAND`
- `PDC_EMAIL_AI_OBSERVER_COMMAND`

The sender connector remains owned by the `pdc-emails` profile. This website-development profile must not copy or read its mailbox secret.

## Gate command handoff

- `PDC_RECOVERY_INSTALL_COMMAND`
- `PDC_RECOVERY_PROVISION_COMMAND`
- `PDC_RECOVERY_MAILBOX_VERIFY_COMMAND`
- `PDC_RECOVERY_SAFE_EMAIL_COMMAND`
- `PDC_RECOVERY_READBACK_COMMAND`
- `PDC_RECOVERY_BOARD_VERIFY_COMMAND`

Each command must be an absolute path or a reviewed executable supplied by the owner. Missing commands fail closed. Command output must be sanitized JSON and must not contain secret-shaped values.
