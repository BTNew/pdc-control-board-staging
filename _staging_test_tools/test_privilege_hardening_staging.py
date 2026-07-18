"""
Real (non-mocked) staging test for independent-review remediation
item #10/#7 (database privilege hardening -- TRUNCATE and excess
anon/authenticated write grants).
"""
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from staging_conn import get_conn

PASS = []
FAIL = []


def check(label, condition, detail=""):
    if condition:
        PASS.append(label)
        print(f"PASS  {label}")
    else:
        FAIL.append((label, detail))
        print(f"FAIL  {label}  {detail}")


def test_no_truncate_grants_remain_anywhere():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        select table_name, grantee from information_schema.role_table_grants
        where table_schema='public' and grantee in ('anon','authenticated') and privilege_type='TRUNCATE'
    """)
    rows = cur.fetchall()
    conn.close()
    check("1a zero TRUNCATE grants remain for anon/authenticated on any public table", rows == [], f"found: {rows[:10]}")


def test_anon_has_zero_write_grants_anywhere():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        select table_name from information_schema.role_table_grants
        where table_schema='public' and grantee='anon' and privilege_type in ('INSERT','UPDATE','DELETE')
    """)
    rows = cur.fetchall()
    conn.close()
    check("2a anon has zero direct INSERT/UPDATE/DELETE grants on any public table", rows == [], f"found: {rows[:10]}")


def test_authenticated_write_grants_are_limited_to_intended_rls_governed_tables():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        select distinct table_name from information_schema.role_table_grants
        where table_schema='public' and grantee='authenticated' and privilege_type in ('INSERT','UPDATE','DELETE')
        order by table_name
    """)
    rows = [r[0] for r in cur.fetchall()]
    conn.close()
    # Stage 2A (independent-review remediation, fix/independent-review-
    # production-blockers, migration 022) revoked the direct
    # administrator write grants on salespeople/sublet_providers that
    # this test originally expected -- those two tables now go through
    # the protected add_salesperson/edit_salesperson/
    # set_salesperson_active/add_sublet_provider/edit_sublet_provider/
    # set_sublet_provider_active RPCs exclusively, matching every other
    # workshop reference table's posture (workshop_technicians/
    # workshop_bays/workshop_settings never had a direct write grant in
    # the first place). Zero direct write grants for 'authenticated' on
    # ANY public table is now the expected, more secure state.
    check(
        "3a authenticated has zero direct write grants remaining on any public table (Stage 2A migration 022 revoked the last two, salespeople/sublet_providers, in favour of protected RPCs)",
        rows == [],
        f"found: {rows}",
    )


def test_pdc_user_roles_has_no_write_grants():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        select grantee, privilege_type from information_schema.role_table_grants
        where table_schema='public' and table_name='pdc_user_roles' and grantee in ('anon','authenticated')
          and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')
    """)
    rows = cur.fetchall()
    conn.close()
    check("4a pdc_user_roles retains zero write grants for anon/authenticated (locked down in migration 020, reconfirmed after 021)", rows == [], f"found: {rows}")


if __name__ == "__main__":
    test_no_truncate_grants_remain_anywhere()
    test_anon_has_zero_write_grants_anywhere()
    test_authenticated_write_grants_are_limited_to_intended_rls_governed_tables()
    test_pdc_user_roles_has_no_write_grants()
    print()
    print(f"TOTAL: {len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        sys.exit(1)
