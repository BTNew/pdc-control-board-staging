# HermesRevolution Stage A runtime boundary

Status: **BETA – READ ONLY / APPROVAL REQUIRED**

## Existing runtime

- Hermes profile: `work-receipting`
- Telegram interface: existing `@hermesrevolution_bot` (`HermesRevolution`)
- Existing gateway service: Windows Scheduled Task `Hermes_Gateway_work-receipting`
- Gateway command: profile-local `gateway-service/gateway.cmd`
- Role instructions: profile-local `SOUL.md`
- Tool configuration: profile-local `config.yaml`
- Scheduled Hermes jobs: none
- Additional Telegram/Discord/WhatsApp interfaces: none configured for this profile
- Mailbox credentials: absent from this profile
- PDC/Supabase writer credentials: absent from this profile

The existing Telegram bot remains in place. No new bot, profile, token or interface is introduced.

## Stage A runtime permissions

The role may inspect only a dealer-scoped authoritative auditor snapshot and may submit deterministic findings only through the narrow Stage A submission RPC after staging deployment. It must not use PMB Monitor intake, mailbox, booking, work-item, Parts, location, QC/RFT/completion or messaging authority.

The Telegram platform exposes only `browser`, `clarify`, `file`, `memory`, `session_search`, `skills`, `todo`, `vision`, and `web`. It exposes neither `cronjob`, `code_execution`, nor `terminal`; a Telegram message therefore cannot invoke arbitrary local commands or schedule future Hermes runs. No Hermes cron job exists. The remaining read-only tools preserve question answering, approved PMB inspection, recommendation explanation, and links/referrals to the staging AI Auditor page. The profile has no mailbox variables and no PDC/Supabase credential variables.

The profile validates with `hermes --profile work-receipting config check`. The existing Windows task last launched successfully (`Last Result: 0`) and the profile gateway was observed running as `pythonw.exe -m hermes_cli.main --profile work-receipting gateway run`. No secret values are recorded here.

## Preserved non-conflicting Revolution capabilities

- Work receipting research and reversible preparation
- Vehicle sales research and draft preparation
- Facebook advertising research and drafts
- General dealership administration
- Existing knowledge/skills and cached training material

All high-impact existing functions retain their pre-existing exact confirmation boundary. Within the PMB Auditor module, Stage A is stricter: read-only regardless of confirmation.

## Backup

The exact pre-change role and configuration are preserved outside the application repository at:

`C:\Users\nwmgr\AppData\Local\hermes\profiles\work-receipting\backups\pre-pmb-ai-auditor-stage-a-20260729T122704+0800`

The backup contains the previous `SOUL.md`, `config.yaml`, gateway launch definitions, environment key-name inventory without values, interface metadata and hashes. Secret values were not duplicated.
