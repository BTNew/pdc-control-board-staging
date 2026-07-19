# Stage 2B C5 — Controlled Real-Data Staging Pilot Approval Manifest

- Exact staging project: `cdsmnqxtyyoeoznmbidd`
- Approved C4 package SHA-256: `980bab0cc0bf79a8156fb78b2587df165406d3fd7d92929468fda66e2ba81016`
- Selected records: `5`
- Preview checksum: `4b7c7ff52ce3fc2a765d94526909b2e59a5fce114a62126cf3e7fba1fa93379d`
- Zero ambiguity: `true`
- Zero conflict: `true`
- Approval basis: Craig's direct C5 instruction; apply is permitted only while this exact preview remains unchanged.

| Source record ID | Legacy key | Proposed action | Expected version | Proposed version | Vehicle UUID | Inclusion reason |
|---|---|---|---:|---:|---|---|
| `added:000001` | `12704351` | `insert` | `None` | `1` | `781c3923-8a5d-4ea8-aa32-f9bd777008b0` | C4 clean and deterministic; unique valid stock/VIN/Toyota-order claims; no ambiguity, conflict, malformed/placeholder identity, deletion/archive, manual-review row, workflow/Parts/booking attachment, orphan, or parse error |
| `added:000002` | `12704345` | `insert` | `None` | `1` | `3dc17450-52d1-4051-a76d-f5e6476c9ba6` | C4 clean and deterministic; unique valid stock/VIN/Toyota-order claims; no ambiguity, conflict, malformed/placeholder identity, deletion/archive, manual-review row, workflow/Parts/booking attachment, orphan, or parse error |
| `added:000003` | `12704341` | `insert` | `None` | `1` | `410c6976-a59f-4152-a329-dd77dd9a3a63` | C4 clean and deterministic; unique valid stock/VIN/Toyota-order claims; no ambiguity, conflict, malformed/placeholder identity, deletion/archive, manual-review row, workflow/Parts/booking attachment, orphan, or parse error |
| `added:000004` | `12704337` | `insert` | `None` | `1` | `97db090a-270d-4cf8-abf4-9c8acf37c943` | C4 clean and deterministic; unique valid stock/VIN/Toyota-order claims; no ambiguity, conflict, malformed/placeholder identity, deletion/archive, manual-review row, workflow/Parts/booking attachment, orphan, or parse error |
| `added:000005` | `12704333` | `insert` | `None` | `1` | `b33c209e-9907-4216-a9aa-71190dd9c886` | C4 clean and deterministic; unique valid stock/VIN/Toyota-order claims; no ambiguity, conflict, malformed/placeholder identity, deletion/archive, manual-review row, workflow/Parts/booking attachment, orphan, or parse error |

**Apply gate:** all five previews are deterministic inserts with zero ambiguity, zero conflict, and no manual-review or attached-record dependency.
