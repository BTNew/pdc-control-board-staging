from __future__ import annotations

from pathlib import Path

from inspect_pdc14_staging import STAGING_REF, management_query
from pilbara_service_open_jobcards import EXPECTED_SOURCE_HASH, build_database_payload, parse_source
from apply_pilbara_service_open_jobcards_staging import SOURCE, _literal

if STAGING_REF != "cdsmnqxtyyoeoznmbidd":
    raise RuntimeError("refusing non-STAGING target")
parsed = parse_source(Path(SOURCE), EXPECTED_SOURCE_HASH)
payload_literal = _literal(build_database_payload(parsed))
result = management_query(
    f"select encode(extensions.digest(convert_to('{payload_literal}'::jsonb::text,'UTF8'),'sha256'),'hex') payload_hash"
)[0]
print(result["payload_hash"])
