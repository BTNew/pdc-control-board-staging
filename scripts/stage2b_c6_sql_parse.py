"""Parse the guarded Stage 2B SQL migrations with pglast."""
from pathlib import Path

from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = [ROOT / "supabase/migrations" / f"{number}_{name}.sql" for number, name in (
    ("028", "stage2b_vehicle_master_foundation"),
    ("029", "stage2b_vehicle_master_operations"),
    ("030", "stage2b_lifecycle_identity_resolver"),
    ("031", "stage2b_importer_identity_export"),
)]
statement_count = 0
for path in MIGRATIONS:
    statements = parse_sql(path.read_text(encoding="utf-8"))
    if not statements:
        raise SystemExit(f"no SQL statements parsed: {path.name}")
    statement_count += len(statements)
print(f"SQL parser passed: {len(MIGRATIONS)} migrations, {statement_count} statements")
