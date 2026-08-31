# PDC Email AI Successor — AI Intake UI implementation plan

Status: authoritative STAGING UI design updated; implementation is subordinate to `recovery-pack/ARCHITECTURE.md` and is not authorized against the superseded contract.
Environment: STAGING only
Dashboard: `20260831_095314_64feeb`
Worktree: `C:/Users/nwmgr/HermesWorkspaces/development/pdc-email-ai-transaction-successor`
Branch: `feature/pdc-email-ai-transaction-successor`
Fallback: hosted transport is preferred; the current Windows `.68/.69/.71` Email Monitor lineage remains untouched as a temporary rollback transport only.

## Grounded current state

- `staging.html:383-403` mounts the legacy AI Intake panel and loads the staging config, `pdc-ai-intake-service.js`, `app.js`, and review overlay.
- `app.js:20848-21122` calls legacy `get_pdc_ai_intake_snapshot`, renders proposal rows and short technical details, and subscribes to legacy `pdc_ai_intake_revision`.
- `pdc-ai-intake-service.js:75-84,120-131` is a legacy proposal snapshot/decision client, not the successor receipt/read-model client.
- Successor source tables live in `pdc_email_ai_successor_runtime_identities`, `pdc_email_ai_successor_transaction_receipts`, and `pdc_email_ai_successor_action_receipts`. Evidence remains rooted in `ai_email_intake` and `ai_email_attachments`; vehicle/work/Parts/Sublet state remains in the existing canonical Board snapshot RPC.
- The successor currently has no runtime identity and no transaction/action receipts. The UI must therefore show synchronized empty state without fabricating processing.
- `npm run test` and `npm run check` are the project-wide regression commands. Existing Node tests are static/contract oriented; new UI tests must also exercise rendered DOM-like behavior for loading/error/empty, parent/vehicle separation, details, refresh and Realtime.

## Requested UI contract

The UI must represent the authoritative architecture: replaceable hosted
transport, normal AI planner/model interpretation, conditional evidence gates,
independent action outcomes and clean-room-safe provenance. It must not imply
that Windows, deterministic interpretation or a global Job Card gate is a
normal path.

Replace only the staging AI Intake surface with the successor view while retaining the old `.68` runtime and data as untouched fallback code. The visible view will:

1. Read one authenticated, paginated chronological snapshot RPC.
2. Render one parent email row per `ai_email_intake` source receipt.
3. Render one child vehicle result per distinct typed successor action/vehicle, including multi-vehicle mail.
4. Show received time, sender, subject, Stock/vehicle, intake UID, attachment/Job Card summary, AI disposition, concise before → requested → result summary and verification status.
5. Expand to show complete typed plan, per-decision planner/model/prompt/business-rule/ruleset/taxonomy/transport/action-contract versions, every action/RPC, conditional evidence requirements, old/requested/result values, blocked/ambiguous instructions, retries/quarantine, immutable receipt references/digests and authoritative readback.
6. Provide Refresh, loading, synchronized-empty, unavailable/error and Realtime revision states. Show planner/model unavailable and deterministic-fallback-not-used states explicitly. Never expose raw body, attachment bytes, secrets, access tokens or Windows logs.
7. Use existing authoritative snapshot fields for vehicle/location/work/Parts/Sublet/lifecycle labels, with no browser-local authority or mutation controls.

## Append-only backend read contract

Add append-only migrations after live `20260831320000` with observed current-head guards. No `.68` task/runtime change or production object is permitted.

RPC:

`public.get_pdc_email_ai_transaction_successor_inbox_v2(p_cursor jsonb default null, p_page_size integer default 100)`

Properties:

- `SECURITY DEFINER`, fixed `search_path`, authenticated-only, approved `viewer|operator|administrator` read role; no service-role execution.
- STAGING sentinel and production-sentinel fail-closed guard.
- Returns `{ok, code, revision, has_more, next_cursor, items}`.
- Parent query is `ai_email_intake` ordered by `received_at desc nulls last, created_at desc, id desc`; the v2 cursor is server-generated from all three ordering fields and page-bounded.
- Each parent contains safe metadata only: intake UID/provider UID, source/message/thread IDs, sender, subject, received time, attachment names/count/digests and extraction summary; raw body is excluded.
- Left-join successor transaction receipt by `source_receipt_id`, then action receipts grouped under each parent. A parent with no successor receipt remains `RECEIVED_WAITING`, never “processed”.
- Child vehicle results are grouped by canonical vehicle UUID and include Stock/vehicle labels from an approved bounded Board snapshot/read-model projection, not browser data. If authoritative identity is absent, child result is `UNRESOLVED` and remains visible.
- `typed_plan` and receipt response are returned as bounded JSON only after redacting forbidden keys/values. The RPC must reject/exclude secret-like keys and raw email body/attachment content from the returned projection.
- Every action includes `action_type`, `instruction_id`, `canonical_rpc`, independent disposition, reason, before/requested/after, expected/actual verification, conditional evidence refs, retry/quarantine fields, action receipt ID/key and one action-level AI Intake audit reference.
- Transaction details include immutable transaction/source/evidence/plan digests, plan, independent planner/model/prompt/business-rule/ruleset/taxonomy/action-contract/transport versions, aggregate disposition, readback and parity. Mixed results are `PARTIAL_FAILURE`, never transaction-level success.
- Include `retry_state` from `ai_email_intake` (`queue_attempts`, `next_attempt_at`, `retry_class`, `permanent_failure`, `last_error_code`) and quarantine marker; do not expose `raw_body`, `parsed_text`, storage paths or attachment text.
- Returns revision from `pdc_email_ai_successor_ui_revision`, a new successor-owned revision table. Trigger/function increments it on source/receipt/action changes; publication is added to `supabase_realtime` if available.
- RLS: force RLS on the revision table, no table grants, authenticated SELECT through a narrow policy; read RPC execute only to authenticated. Successor receipt tables remain direct-DML denied.

## UI implementation shape

Add `pdc-email-ai-successor-inbox.js` and `pdc-email-ai-successor-inbox.css`.

- Client calls only the new RPC with the staging publishable key/access token; validates exact project ref and response shape. It is read-only and cannot select, invoke or silently fall back to a deterministic planner.
- Subscription listens only to `pdc_email_ai_successor_ui_revision`; callback invalidates and refreshes the currently open inbox with generation/lifecycle protection. `SUBSCRIBED`, connecting and failure states are visible; startup retries are bounded and teardown-aware.
- Renderer uses `textContent`/escaped values and bounded detail sections; no `innerHTML` with raw backend values. Parent/vehicle rows and detail sections carry stable data attributes.
- Detail disclosure is native `<details>` with accessible summaries. The compact summary remains usable on phone width; desktop uses a two-column parent/detail layout without horizontal overflow.
- No Apply/Reject/mutation buttons in this successor view. The command runtime is separately commissioned and natural proof is performed out of band.
- Existing legacy `pdc-ai-intake-service.js` and `.68` proposal handlers remain present but are not used by the successor panel. The Windows lane is displayed, if at all, as temporary rollback status rather than the normal transport.

## TDD checkpoints

A. Red/green client contract: staging-only target, exact RPC/cursor/page shape, forbidden secret/body omission, error/empty/loading states.

B. Red/green rendering: parent/vehicle split, two vehicles under one email, received metadata, UID/attachment summary, before→requested→result, verification badges, details for every action/version/provenance/evidence/retry/quarantine/audit/readback, safe escaping.

C. Red/green lifecycle: in-place refresh, Realtime revision refresh, stale callback suppression, unsubscribe on auth loss/view teardown, no duplicate subscriptions.

D. Red/green responsive/browser: compact phone layout, desktop layout, accessible details/labels, no horizontal overflow, no console/resource errors, no non-staging requests, explicit planner-unavailable/no-silent-fallback state.

E. Red/green backend: exact read RPC schema, cursor ordering, safe projection, role/RLS/execute ACL, revision publication, unrelated source/vehicle isolation.

## Commissioning and natural proof gates

1. Apply read migration with exact live-head guard and read back function/ACL/RLS/publication.
2. Provision one dedicated authenticated STAGING runtime identity plus independently versioned hosted transport and AI planner binding through the protected connector. It must not be Administrator, service-role, direct DML/SQL or browser authority. Keep the Windows `.68/.69/.71` rollback lane untouched except for an explicitly approved temporary rollback.
3. Run hostile identity/action rejection and typed plan/apply/readback/replay/isolation tests.
4. Run one authorized `pdc-emails` natural email only after the above gates: full thread/Job Card, no manual enqueue/import/activation/OneCycle/forced task, natural successor pickup, versioned AI interpretation, controlled command RPC, exact readback and Board/UI parity.
5. Prove exact replay has zero effects and unrelated vehicle remains unchanged. Record Stock, intake UID, typed plan/instruction version, per-action evidence/provenance/audit, resulting state and readback. State explicitly that Windows made no business classification decision and deterministic code did not silently replace the planner.
6. Keep `.68` disabled fallback through soak; no production activity.

## Release evidence

- Source commit contains only requested staging UI/read RPC/tests/docs/release metadata.
- `npm run test`, `npm run check`, focused Node/Python/UI tests and SQL parser pass.
- Staging branch and workflow/live assets are independently verified. Backend migration/read RPC is separately read back.
- Browser proof distinguishes source/assets from live data. No raw secrets, Windows logs, production endpoints or outbound email are used.

## Concrete implementation delta and acceptance criteria

- Render action-level AI Intake audit and independent terminal dispositions, not
  only a transaction summary.
- Show per-decision planner/model/prompt/business-rule/ruleset/taxonomy,
  transport and Supabase action-contract provenance, including blocked and
  not-applicable actions.
- Keep Job Card and attachment evidence conditional by action and expose the
  exact blocked reason; do not make the UI imply a global attachment gate.
- Treat hosted transport as the normal replaceable path, Windows as temporary
  rollback-only, and deterministic interpretation as fixtures/regression/
  validation/fail-safe only.
- Keep the read surface free of raw body, attachment bytes, credentials and
  business mutation controls.

Acceptance requires a mixed-result multi-action fixture to show independent
  action audit/provenance/readback and `PARTIAL_FAILURE`, a planner outage to
  show an explicit no-silent-fallback state, and a clean-room-compatible
  staging-only projection with all retained safety controls intact.
