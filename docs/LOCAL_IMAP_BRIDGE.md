# Local IMAP bridge pilot

This pilot reads the `nwmgreception@outlook.com` mailbox over IMAP and writes received messages into the PMB AI Intake Supabase tables.

It replaces the earlier classic Outlook COM pilot path. New Outlook for Windows can remain installed for normal manual use, but it cannot be automated locally. IMAP talks to the mailbox server instead of automating the app.

## Security rules

Do not paste mailbox passwords, app passwords, recovery codes, MFA codes or Supabase service keys into chat.

Store secrets only in the ignored local file:

```text
backend/.env
```

The committed template is:

```text
backend/.env.example
```

## Outlook.com settings to check

For a personal Outlook.com mailbox, IMAP details are normally:

```text
Host: outlook.office365.com
Port: 993
Security: SSL/TLS
Username: nwmgreception@outlook.com
Folder: Inbox
```

If login fails:

- check Outlook.com settings allow POP/IMAP access;
- if two-step verification is enabled, create an app password and use that in `backend/.env`;
- if Microsoft blocks basic password login for the account, we will need OAuth/Graph or another intake mailbox provider.

## Local environment

Create local env file from Git Bash:

```bash
cd /c/Users/nwmgr/pdc-control-board
cp backend/.env.example backend/.env
```

Edit `backend/.env` locally and set:

```text
SUPABASE_URL=https://vjdtsswhroyguxyfjdkt.supabase.co
SUPABASE_SERVICE_ROLE_KEY=...
IMAP_BRIDGE_HOST=outlook.office365.com
IMAP_BRIDGE_PORT=993
IMAP_BRIDGE_USERNAME=nwmgreception@outlook.com
IMAP_BRIDGE_PASSWORD=...
IMAP_BRIDGE_FOLDER=Inbox
IMAP_BRIDGE_LIMIT=10
IMAP_BRIDGE_MARK_READ=false
```

Notes:

- `SUPABASE_SERVICE_ROLE_KEY` is secret. Do not commit it.
- `IMAP_BRIDGE_PASSWORD` is secret. Do not commit it.
- `IMAP_BRIDGE_MARK_READ=false` is safer for initial testing.

## Commands

Probe login and folder access only:

```bash
python backend/imap_bridge.py --probe
```

Dry-run parse unread emails without posting to Supabase:

```bash
python backend/imap_bridge.py --dry-run --limit 3
```

Post unread messages into Supabase AI Intake:

```bash
python backend/imap_bridge.py --limit 10
```

Read all recent messages instead of unread only:

```bash
python backend/imap_bridge.py --dry-run --all --limit 3
```

## Runtime files

Ignored local runtime files:

```text
backend/.imap_bridge_processed.json
backend/.imap_attachments/
```

The state file prevents re-posting the same email repeatedly after a successful Supabase insert.

## Current responsibility boundary

This bridge only performs the safe first step:

```text
IMAP Inbox → ai_email_intake received record
```

It does not:

- create vehicles;
- update vehicles;
- delete records;
- send emails;
- mark email as read unless explicitly enabled.

Next backend stages handle:

```text
received record → attachment text extraction → AI structured extraction → validation → review/apply
```

Every actual vehicle mutation must go through controlled backend validation/RPC and audit history.
