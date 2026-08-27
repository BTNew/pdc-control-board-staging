# PDC Email Monitor .44 — exact UID514 recovery successor handoff

Date: 2026-08-27
Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` only.
Production: untouched.

## Outcome

The retained UIDVALIDITY `1`, Inbox UID `514` recovery path is now available
without lowering the generic provider UID floor and without changing sealed
`.44`. The real message remains unprocessed so pdc-emails can perform the one
reviewed authenticated replay when separately authorised.

The deployed append-only chain preserves 670–676 and adds these staging-only
successors:

- `20260827111000` — 677 exact UID514 recovery successor
- `20260827112000` — 678 seven-part authorization cardinality repair
- `20260827114000` — 679 separate recovery-effect event key repair
- `20260828000000` — 682 transaction-safe capability consumption repair
- `20260828010000` — 683 exact first-call/replay capability mint repair

Unrelated later staging ledger entries were preserved. The active mailbox is
still exactly the existing `pdc_pmb_email` / `pmbcontroller@gmail.com` Gmail
row in `test_mode=true`; the task remains Disabled under `LOCAL SERVICE`;
pilot, automatic rule application, automatic Job Card processing and outbound
email remain disabled.

## Exact pdc-emails RPC

Call this new typed RPC with the standard authenticated JWT for the exact actor
only:

`enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)`

Arguments:

- `p_recovery_event_id`: exactly `25751401`
- `p_message.provider_uid`: exactly `imap_uid:514`
- `p_message.source_hash`: exactly `440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280`
- recipient: `pmbcontroller@gmail.com`
- sender: `oleg.borodavkin@pmgwa.com.au`
- provider auth service: `mx.google.com`
- Gmail authentication result: `true`
- sender domain: `pmgwa.com.au`
- at least one authenticated SPF/DKIM/DMARC alignment, with the exact five-key authentication object

The seven attachment objects must remain in retained order with exact filename,
MIME type, byte length and SHA-256 from the retained evidence:

1. `image001.jpg`, `image/jpeg`, `161949`, `7bc4e2dec9b1c405098f1ca7b4c646bf3262158e328f9f548abb855b8ef2f21a`
2. `image002.png`, `image/png`, `119426`, `ffaa2bfbca036f9dbcbe10de9a43f8a141fd2a84f9fea75c0e114b96b87b4cf3`
3. `image.png`, `image/png`, `220912`, `c60dae99a28cdccdee51f5bdffa43382d9b7eb31af690c31caedcc8d4f66cf40`
4. `J139125482 - _13016925.pdf`, `application/pdf`, `72551`, `9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4`
5. `131 Parts Order - 13016925 - Hilux SCC WM - HERMAL Pty Ltd.pdf`, `application/pdf`, `50134`, `66b790ba3a72760e00a034bf7f5cf5a7e1defe5d6947373216f8c8dc4ed8acff`
6. `PMG Sublet Order - 13016925 - Hilux SCC WM - HERMAL Pty Ltd.pdf`, `application/pdf`, `49944`, `b297f4f9070f6c78c88aae099630b78bb5157c3094c45a30b5cfef0f263ac3b1`
7. `PD Document 48298_PDCheckform.pdf`, `application/pdf`, `17398`, `ea248634b8610f757907c519ea2f7ba243fb1602c8114cbde947707aff8407ae`

Each object must use `validation_status=verified`, an empty validation error,
the matching reported MIME type, and the reviewed private storage path
`pdc-email-intake-private/<object-path>`. The RPC adds stable server-owned
attachment IDs before calling the existing typed enqueue path. It then calls
`authorize_pdc_uid514_retained_intake_257` atomically.

First exact call returns `uid514_recovery_enqueued`; an identical replay returns
`uid514_recovery_replayed` with no duplicate intake, attachment, authorization
or selection effect. The claim remains the existing:

`claim_pdc_uid514_recovery_257(text,integer)`

with gateway `pdc-monitor-staging-sales-uid509-v1` and event `25751401`.

## Exact identity and binding

All server-side gates bind:

- actor `df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b`
- actor email `sales@broometoyota.com.au`
- JWT role `authenticated`
- server application role `importer`
- gateway `pdc-monitor-staging-sales-uid509-v1`
- release `pdc-monitor-staging-m502-2026.08.44`
- source `e850c319989d98b45b95a28aa815d78e2c2e3a4b`
- manifest `d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d`
- planner `7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348`
- trust receipt `e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227`
- mailbox `12fe383d-5c1e-5801-96e4-f67cf3e3bb57`, key `pdc_pmb_email`, Gmail,
  `pmbcontroller@gmail.com`, `Inbox`, UIDVALIDITY `1`, UID `514`
- recovery event `25751401`
- parent source hash above and exact seven-part/four-PDF inventory.

Wrong actor, gateway, role, mailbox, event, parent hash, attachment hash or
shape fails closed. `anon`, `service_role`, `pdc_email_monitor` direct access,
protected-table SELECT and direct table DML remain denied.

## Exact source hashes

- 677 migration: `ad921292bdafb3bfc25413df8c1faa803442f0c645799aac3cd42af76b0da85f`
- 678 migration: `0fab7dbc2525173aea32a5c502b249a892684bdabf4bab483da9ad6e9edacfe1`
- 679 migration: `2d11783911adf74070d2e2a15b7eaf628cead126eaf463261247dbcd280b3f9c`
- 682 migration: `271dcd6a7bbbbd3500bd55ba7388047cda779ebae27c2c55d585e26a0ca79de2`
- 683 migration: `b8fbdbf163a2acedf5c839da5e7f43af868cc05ff0d7db77fbae2aa9e615761c`
- authoritative 674 migration: `d6c57dd8f0215cff71e479b4b50e40de10dea2113216534ccc2edd9048db3bcb`
- sealed `.44` manifest: `d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d`
- sealed `.44` runner: `52affc8ea7374f6067be51f56cb633deb520b0628801b427e5215c873ec26ebd`
- external adapter: `a14a2d2b4ad3514a3367246ae9b8705762eda41987f9491980594e9c62e7d036`

Live current function hashes after the applied successors:

- enqueue RPC `enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)`:
  `34f315ee00424a55a01430bfbdd97a2ede4ddc0928bd57acd314545962e53e19`
- capability helper `pdc_uid514_recovery_enqueue_capability_677(uuid)`:
  `828d1bd6db27521ed0e6749e2b24a43edc39461f516eb30706bab156f2a0b252`
- authorize RPC `authorize_pdc_uid514_retained_intake_257(uuid,integer)`:
  `1c1a0d485659d5b6d614e2c03f7dbf93f9f87c39de1f9aa63b23ac9576718a82`
- claim RPC `claim_pdc_uid514_recovery_257(text,integer)`:
  `fe30c884f0db02f7d31d629e12af0e29bcdd2505a6451b2873f05364c5727e69`
- enqueue trigger `pdc_email_monitor_pilot_intake_guard_223()`:
  `0f93e7bc36549e14f4a5231e57a2a23b1168f6d2a32d3f4678da811cdca77955`

## Safety and rollback

677/682/683 use a private forced-RLS transaction-scoped capability consumed by
the existing enqueue trigger. There is no generic `<515` exception and no
caller-supplied actor/binding authority. 677/683 preserve all seven MIME parts
while 673/678 select exactly four PDFs and bind the Job Card only to its exact
hash.

`admin_rollback_pdc_uid514_recovery_677(text)` is authenticated Administrator
only. It disables future exact UID514 enqueue/claim, appends immutable rollback
history and does not delete intake, attachment, authorization, selection or
other evidence. The rollback path was exercised in a rolled-back synthetic
full-chain rehearsal.

## Verification state

Live staging read-back after the applied chain proved:

- staging sentinel present; Production sentinel absent;
- successors 670–676 preserved and 677, 678, 679, 682, 683 applied;
- active mailbox count `1`, exact PMB mailbox only;
- pilot/automatic rules/automatic Job Card/outbound email all disabled;
- UID514 intake `0`, authorization `0`, selection `0`, Stock `13016925` vehicle `0`;
- protected control/history tables forced RLS with no authenticated direct SELECT;
- recovery RPC execute true only for authenticated, anon/service_role denied;
- task still Disabled under `LOCAL SERVICE`, sealed `.44` and `CURRENT` untouched;
- Production untouched.

The authenticated synthetic rehearsal created seven attachment metadata rows,
one authorization and one selection, claimed/read all seven parts, exercised the
result path, replayed the exact payload, exercised wrong event/actor/gateway and
rolled back an Administrator disable—all inside a transaction rolled back at the
end. No real UID514 row or vehicle remains.
