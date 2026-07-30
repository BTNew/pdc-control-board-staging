#!/usr/bin/env python3
"""Configure approved staging AI Auditor reviewer scopes and one finding publisher."""
from __future__ import annotations

import json
import os

import psycopg

DEALER = "14450"
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
ACCOUNT_ENV = [
    "PDC_STAGING_ADMIN_EMAIL",
    "PDC_STAGING_CONTROLLER_A_EMAIL",
    "PDC_STAGING_VIEWER_EMAIL",
]


def main():
    dsn = os.environ.get("PDC_STAGING_DATABASE_URL", "")
    emails = [os.environ.get(name, "").strip().lower() for name in ACCOUNT_ENV]
    if not dsn or any(not email for email in emails) or len(set(emails)) != len(emails):
        raise RuntimeError("staging access environment incomplete")
    with psycopg.connect(dsn, autocommit=False) as conn:
        cur = conn.cursor()
        cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
        if cur.fetchone()[0] != PROJECT_REF:
            raise RuntimeError("staging sentinel mismatch")
        cur.execute("select max(version::bigint)::text from supabase_migrations.schema_migrations")
        if cur.fetchone()[0] != "122":
            raise RuntimeError("migration 122 is not current")
        configured = []
        for email in emails:
            cur.execute("""select auth_user_id,role::text from public.pdc_user_roles
              where lower(email)=%s and active and account_status='approved'""", (email,))
            rows = cur.fetchall()
            if len(rows) != 1 or rows[0][0] is None or rows[0][1] not in ("viewer", "operator", "administrator"):
                raise RuntimeError("approved auth-bound staging role is not exact")
            uid, role = rows[0]
            cur.execute("""insert into public.pdc_auditor_user_dealer_scopes(
              auth_user_id,normalized_email,dealer_code,environment,active)
              values(%s,%s,%s,'staging',true)
              on conflict(auth_user_id,normalized_email,dealer_code,environment)
              do update set active=true""", (uid, email, DEALER))
            configured.append(role)
        admin_email = emails[0]
        cur.execute("select auth_user_id from public.pdc_user_roles where lower(email)=%s", (admin_email,))
        admin_uid = cur.fetchone()[0]
        cur.execute("""insert into public.pdc_auditor_worker_identities(
          auth_user_id,normalized_email,dealer_code,environment,active)
          values(%s,%s,%s,'staging',true)
          on conflict(auth_user_id,normalized_email,dealer_code,environment)
          do update set active=true""", (admin_uid, admin_email, DEALER))
        cur.execute("""select count(*),count(*) filter(where active) from public.pdc_auditor_user_dealer_scopes
          where dealer_code=%s and environment='staging'""", (DEALER,))
        total, active = cur.fetchone()
        cur.execute("""select count(*) from public.pdc_auditor_worker_identities
          where dealer_code=%s and environment='staging' and active""", (DEALER,))
        workers = cur.fetchone()[0]
        conn.commit()
    print(json.dumps({
        "status": "configured",
        "environment": "staging",
        "dealer_code": DEALER,
        "configured_roles": sorted(configured),
        "active_reviewer_scopes": active,
        "scope_rows": total,
        "active_finding_publishers": workers,
        "credentials_exposed": False,
        "production_changed": False,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
