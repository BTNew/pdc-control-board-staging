"""Rollback-only installation/contract probe for staging migration 213.
Never commits and refuses every project except cdsmnqxtyyoeoznmbidd.
"""
import os
from pathlib import Path
import psycopg2

ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/staging_only/213_persistent_supervised_email_learning.sql').read_text(encoding='utf-8')

def main():
    url=os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ.get('PDC_STAGING_DATABASE_URL')
    if not url: raise SystemExit('staging database URL missing')
    # Replace only the terminal COMMIT; all effects stay in this outer transaction.
    sql=SQL.rstrip()
    assert sql.endswith('commit;')
    sql=sql[:-7]+'-- rollback-only harness owns transaction\n'
    with psycopg2.connect(url) as c:
      c.autocommit=False
      with c.cursor() as q:
        q.execute("select public.pdc_monitor_staging_guard(),(select project_ref from public.pdc_staging_environment_sentinel where singleton),to_regclass('public.pdc_production_environment_sentinel')")
        guard,project,production=q.fetchone()
        assert guard and project=='cdsmnqxtyyoeoznmbidd' and production is None,(guard,project,production)
        q.execute(sql)
        q.execute("select count(*) from public.pdc_supervised_rule_families")
        assert q.fetchone()[0]==20
        q.execute("select count(*) from public.pdc_supervised_rule_versions where estimated_hours is not null or cost_ex_gst is not null or sell_ex_gst is not null or gst_percent is not null or currency is not null")
        assert q.fetchone()[0]==0
        q.execute("select count(*) from public.pdc_supervised_rule_examples where example_kind='deleted_evidence' and source_stock in('12546480','12586645')")
        assert q.fetchone()[0]>=2
        q.execute("select count(*) from supabase_migrations.schema_migrations where version='213' and name='persistent_supervised_email_learning'")
        assert q.fetchone()[0]==1
        # Anonymous callers cannot read or apply. Administrator can apply the exact
        # seeded batch, replay without duplicate overlays, and append an undo.
        q.execute("select set_config('request.jwt.claims','{}',true)")
        try:
            q.execute("select count(*) from public.list_pdc_supervised_rules_213(false)")
            raise AssertionError('anonymous rule read allowed')
        except psycopg2.errors.InsufficientPrivilege:
            c.rollback(); q.execute(sql)
        q.execute("select auth_user_id::text,lower(email) from public.pdc_user_roles where role='administrator' and active and account_status='approved' and lower(email)='craig.watson@broometoyota.com.au'")
        actor=q.fetchone(); assert actor, 'Craig administrator missing'
        import json
        q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':actor[0],'role':'authenticated','email':actor[1]}),))
        q.execute("select batch_id from public.pdc_supervised_correction_batches where idempotency_key='migration-213-authorised-exact-active-lines'")
        batch=q.fetchone()[0]
        q.execute("select count(*) from public.workshop_bookings") ; bookings_before=q.fetchone()[0]
        q.execute("select public.apply_pdc_supervised_correction_batch_213(%s)",(batch,)); first=q.fetchone()[0]; assert first['ok'],first
        q.execute("select count(*) from public.pdc_supervised_correction_overlays where overlay_kind='apply'"); overlays=q.fetchone()[0]
        q.execute("select public.apply_pdc_supervised_correction_batch_213(%s)",(batch,)); replay=q.fetchone()[0]; assert replay['ok'],replay
        q.execute("select count(*) from public.pdc_supervised_correction_overlays where overlay_kind='apply'"); assert q.fetchone()[0]==overlays
        q.execute("select public.undo_pdc_supervised_correction_batch_213(%s,'rollback-only undo contract')",(batch,)); undone=q.fetchone()[0]; assert undone['ok'],undone
        q.execute("select count(*) from public.workshop_bookings"); assert q.fetchone()[0]==bookings_before
        q.execute('rollback')
        print(f"Migration 213 rollback-only install passed: 20 rule families, 0 invented prices/hours, deleted evidence retained; apply={first['data']['applied']}, protected={first['data']['skipped']}, replay overlays={overlays}, undo={undone['data']['undone']}")

if __name__=='__main__': main()
