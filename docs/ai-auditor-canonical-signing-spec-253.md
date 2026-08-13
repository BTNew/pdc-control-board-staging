# AI Auditor canonical signing specification

**Status:** draft source contract. Activation and deployment are not authorised.

The final integrated migration/runtime must implement this specification exactly and share executable golden vectors. Any byte difference is a hard failure.

## Version

`pdc-auditor-envelope-253-v1`

The version identifier is the first UTF-8 line of the signing payload and is not caller-selectable.

## Envelope fields

The top-level JSON object has exactly these keys:

1. `gateway_instance_id`
2. `delivery_uuid`
3. `key_id`
4. `nonce`
5. `issued_at`
6. `expires_at`
7. `instruction_sha256`
8. `selected_scope`
9. `telegram_evidence`
10. `signature`

The signing payload excludes only `signature`. Unknown or missing keys fail closed.

## Scalars and timestamps

- Text is Unicode encoded as UTF-8 without normalization or lossy replacement.
- UUID values use lowercase canonical hyphenated text.
- `issued_at` and `expires_at` use one exact UTC representation selected by the final executable contract and golden vectors. Other representations and excessive precision are rejected rather than normalized.
- Boolean values are JSON `true`/`false`.
- Null is JSON `null`.
- Numbers use the canonical JSON number grammar accepted by both implementations; NaN and infinities are forbidden. Operation hours are represented as integer quarter-hours in signed typed intent to avoid decimal ambiguity.
- Object keys are sorted by Unicode code point as proven by golden vectors. Arrays retain order.
- JSON serialization is compact: no insignificant whitespace; string escaping and non-ASCII handling must match the golden vectors byte-for-byte.

## Signing bytes

The version line is followed by one length-prefixed line for each field, in this exact order:

`gateway_instance_id`, `delivery_uuid`, `key_id`, `nonce`, `issued_at`, `expires_at`, `instruction_sha256`, `selected_scope`, `telegram_evidence`.

Each line is:

`<field-name>:<UTF-8-byte-length>:<field-bytes>`

Scalar text fields use their exact validated text bytes. The two JSON fields use canonical JSON bytes. Lines are joined with byte `0A`; there is no trailing newline unless the shared golden vector explicitly contains one.

Signature is lowercase hexadecimal HMAC-SHA256 over these bytes using the key selected by `(gateway_instance_id,key_id)`.

## Instruction and proposal hashes

- `instruction_sha256`: lowercase SHA-256 of the exact UTF-8 original instruction.
- `typed_item_set_hash`: lowercase SHA-256 of canonical JSON for the final ordered typed-item set produced by the database.
- `final_scope_hash`: lowercase SHA-256 of canonical JSON for the final authoritative proposal scope.
- `proposal_hash`: lowercase SHA-256 over a versioned, length-prefixed tuple containing proposal ID, proposal version, dealer/environment, instruction hash, typed-item-set hash, final-scope hash, operational revision and ordered expected row versions.
- Apply confirmation signs a new envelope whose `selected_scope` contains the proposal ID, proposal version, proposal hash, typed-item-set hash, final-scope hash and expected-row-version hash. It does not reuse or compare against the earlier natural-language planning scope.
- Any item, scope, version, row-version or proposal change creates a different hash and invalidates the earlier confirmation.

## Required golden vectors

Shared vectors must cover:

- ASCII baseline;
- Unicode and UTF-8 byte length;
- nested key ordering and array order;
- null and booleans;
- integer number boundaries;
- exact timestamp lower/upper validity boundaries;
- altered instruction, proposal and Apply scopes;
- invalid extra/missing fields;
- one known HMAC key/signature fixture containing no live secret.

Python executes the vectors directly. SQL source embeds or loads the identical vector values and focused PostgreSQL execution later proves exact bytes, hashes and signature under rollback-only acceptance.
