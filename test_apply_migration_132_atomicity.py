from pathlib import Path

SRC=(Path(__file__).parent/'scripts'/'apply_migration_132_staging.py').read_text(encoding='utf-8')
LOWER=SRC.lower()
for text in (
    'migration_body = sql.replace("begin;", "", 1).rsplit("commit;", 1)[0]',
    'cur.execute(migration_body)',
    'fault-inject-postcheck-failure',
    'intentional postcheck failure before commit',
    'legacy_signature',
    'pdc_email_single_receipt_source_guard',
    'pdc_email_batch_receipt_source_guard',
    'conn.rollback()',
):
    assert text.lower() in LOWER, text
assert LOWER.index('cur.execute(migration_body)') < LOWER.index('conn.commit()')
assert LOWER.index('if args.fault_inject_postcheck_failure:') < LOWER.index('conn.commit()')
assert LOWER.index('if not ledger or not auth_exec') < LOWER.index('conn.commit()')
assert 'cur.execute(sql)\n        conn.commit()' not in LOWER
print('Migration 132 guarded installer atomicity contract: ok')
