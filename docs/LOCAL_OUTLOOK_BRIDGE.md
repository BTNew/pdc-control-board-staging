# Local Outlook bridge pilot

This pilot reads the Outlook profile already configured on this Windows computer and writes received emails into the PMB AI Intake database tables.

Pilot mailbox:

```text
nwmgreception@outlook.com
```

## Important limitation

This works only with **classic Microsoft Outlook desktop** because the bridge uses Outlook COM automation.

The newer web-based **Outlook for Windows** app does not expose the classic COM API. If only the new Outlook app is installed, the bridge will fail safely with a message like:

```text
Classic Outlook COM automation is unavailable
```

In that case the options are:

1. install/configure classic Outlook desktop on this PC, or
2. use Microsoft Graph later, or
3. use another email provider/inbound parsing service.

## Why this avoids Microsoft Tenant ID

The bridge does not authenticate to Microsoft directly. It asks the local Outlook desktop profile for messages. That means:

- no Microsoft tenant ID is needed for the pilot
- no mailbox password is stored in the repo
- no mailbox password is stored in the frontend
- Outlook must remain configured and signed in on this computer

## Runtime files

Ignored local files:

```text
backend/.outlook_bridge_processed.json
backend/.outlook_attachments/
```

## Environment

Copy `backend/.env.example` to a local backend environment file and fill only backend values.

Required for real posting to Supabase:

```text
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
```

Outlook pilot defaults:

```text
OUTLOOK_BRIDGE_MAILBOX=nwmgreception@outlook.com
OUTLOOK_BRIDGE_FOLDER=Inbox
OUTLOOK_BRIDGE_UNREAD_ONLY=true
OUTLOOK_BRIDGE_SAVE_ATTACHMENTS=true
OUTLOOK_BRIDGE_MARK_READ=false
OUTLOOK_BRIDGE_LIMIT=10
```

Do not commit the real `.env` file.

## Commands

Probe Outlook without storing emails:

```bash
python backend/outlook_bridge.py --probe --mailbox nwmgreception@outlook.com
```

Dry-run email extraction without posting to Supabase:

```bash
python backend/outlook_bridge.py --dry-run --limit 3 --mailbox nwmgreception@outlook.com
```

Post unread messages into Supabase AI Intake:

```bash
python backend/outlook_bridge.py --limit 10 --mailbox nwmgreception@outlook.com
```

The bridge does not mark messages read unless `OUTLOOK_BRIDGE_MARK_READ=true` or `--mark-read` is used.

## Scheduling later

For the pilot, run manually first. After it works, schedule it with Windows Task Scheduler to run every few minutes while the PC is on.

The scheduled task should run in the same Windows user profile where Outlook is configured.

## AI processing flow

This bridge only performs the safe first step:

```text
Outlook inbox → ai_email_intake received record
```

The next backend stage should:

```text
received record → attachment text extraction → AI structured extraction → validation → review/apply
```

The bridge must not directly create/update/delete vehicles.
