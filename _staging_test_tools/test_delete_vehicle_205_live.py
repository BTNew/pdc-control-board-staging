"""Staging-only migration 205/206 live acceptance using one disposable vehicle."""
import json, os, sys, time, uuid
from urllib import request, error
import psycopg2

REF = "cdsmnqxtyyoeoznmbidd"
URL = os.environ["PDC_STAGING_SUPABASE_URL"].rstrip("/")
ANON = os.environ["PDC_STAGING_ANON_KEY"]
SERVICE = os.environ["PDC_STAGING_SERVICE_ROLE_KEY"]
STOCK = "DELTEST" + str(int(time.time()))[-7:]
CUSTOMER = "Disposable Delete Acceptance"
REASON = "Disposable staging Delete Vehicle acceptance test"


def http(method, path, token=None, body=None):
    payload = None if body is None else json.dumps(body).encode()
    headers = {"apikey": ANON, "Content-Type": "application/json"}
    if token: headers["Authorization"] = "Bearer " + token
    req = request.Request(URL + path, data=payload, headers=headers, method=method)
    try:
        with request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return r.status, json.loads(raw) if raw else None
    except error.HTTPError as exc:
        raw = exc.read().decode()
        try: parsed = json.loads(raw)
        except Exception: parsed = raw
        return exc.code, parsed


def login(email, password):
    status, body = http("POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": password})
    assert status == 200, (status, body)
    return body["access_token"]


def create_test_user(email, password):
    payload = json.dumps({"email": email, "password": password, "email_confirm": True}).encode()
    req = request.Request(URL + "/auth/v1/admin/users", data=payload,
        headers={"apikey": SERVICE, "Authorization": "Bearer " + SERVICE, "Content-Type": "application/json"}, method="POST")
    with request.urlopen(req, timeout=30) as r: return json.loads(r.read().decode())["id"]


def delete_test_user(user_id):
    req = request.Request(URL + "/auth/v1/admin/users/" + user_id,
        headers={"apikey": SERVICE, "Authorization": "Bearer " + SERVICE}, method="DELETE")
    try: request.urlopen(req, timeout=30).read()
    except Exception: pass


def rpc(token, name, params):
    return http("POST", "/rest/v1/rpc/" + name, token, params)


def response_ok(result, code=None):
    status, body = result
    assert status == 200 and body.get("ok") is True, result
    if code: assert body.get("code") == code, result
    return body


def denied(result):
    status, body = result
    return status in (401, 403) or (status == 200 and body.get("ok") is False and body.get("code") == "administrator_required")


def main():
    assert REF in URL and "vjdtsswhroyguxyfjdkt" not in URL
    admin = login(os.environ["PDC_STAGING_ADMIN_EMAIL"], os.environ["PDC_STAGING_ADMIN_PASSWORD"])
    conn = psycopg2.connect(os.environ["PDC_STAGING_DATABASE_URL"])
    conn.autocommit = False
    cur = conn.cursor()
    test_users = []
    try:
        cur.execute("select auth_user_id,email,id from public.pdc_user_roles where lower(email)=lower(%s) and role='administrator' and active and account_status='approved'", (os.environ["PDC_STAGING_ADMIN_EMAIL"],))
        actor, actor_email, actor_role_id = cur.fetchone()
        password = "Delete205!" + uuid.uuid4().hex + "aA1"
        tokens = {}
        for label, role, monitor_scope in (("viewer","viewer",False),("auditor","importer",False),("monitor","viewer",True)):
            email = f"pdc-delete-205-{label}-{uuid.uuid4().hex[:8]}@example.invalid"
            user_id = create_test_user(email,password); test_users.append((user_id,email))
            cur.execute("update public.pdc_user_roles set display_name=%s,role=%s,active=true,approved_by=%s,approved_at=clock_timestamp(),auth_user_id=%s,account_status='approved',full_name=%s where lower(email)=lower(%s)",( "Delete 205 "+label,role,actor_role_id,user_id,"Delete 205 "+label,email))
            assert cur.rowcount == 1
            if monitor_scope: cur.execute("insert into public.pdc_monitor_stage_activation_writers(user_id,active,reason,granted_by) values(%s,true,'delete 205 denial acceptance',%s)",(user_id,actor))
            conn.commit(); tokens[label]=login(email,password)
        vehicle_id = str(uuid.uuid4())
        cur.execute("insert into public.vehicles(id,permanent_vehicle_id,stock_number,customer_name,vehicle_description,lifecycle_state,visible_on_board,current_location,workshop_status,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by) values(%s,%s,%s,%s,'Disposable staging vehicle','active',true,'PMB','queued','staging_acceptance','delete-205',%s,'{}',%s,%s) returning version", (vehicle_id, "DELETE-"+STOCK, STOCK, CUSTOMER, STOCK, actor, actor))
        version = cur.fetchone()[0]
        cur.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,notes) values(%s,'FITTING',true,false,'preserved acceptance operation')", (vehicle_id,))
        cur.execute("select s.id,b.id from public.workshop_stages s join public.workshop_bays b on b.stage_id=s.id where s.active and b.is_active and upper(s.code)='FITTING' limit 1")
        stage_id, bay_id = cur.fetchone()
        booking_id = str(uuid.uuid4())
        cur.execute("insert into public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,source,created_by,updated_by) values(%s,%s,%s,null,'queued',date_trunc('day',clock_timestamp())+interval '365 days',date_trunc('day',clock_timestamp())+interval '365 days 1 hour',60,'delete-205-acceptance',%s,%s)", (booking_id, vehicle_id, stage_id, actor, actor))
        cur.execute("insert into public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_stoppage,parts_stoppage_reason,updated_by) values(%s,true,true,true,'preserved acceptance stoppage',%s)", (vehicle_id, actor))
        cur.execute("insert into public.vehicle_movements(vehicle_id,from_location,to_location,reason,moved_by) values(%s,'Other','PMB','acceptance history evidence',%s)", (vehicle_id, actor))
        cur.execute("insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,created_by,updated_by) values(%s,'acceptance-overlay','manual','FITTING','Disposable active overlay',1.25,true,%s,%s)", (vehicle_id, actor, actor))
        cur.execute("insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,metadata) values('insert','vehicles',%s,%s,%s,%s,jsonb_build_object('source','delete-205-live-acceptance'))", (vehicle_id, vehicle_id, actor, actor_email))
        conn.commit()

        # Active before delete.
        status, active_before = http("GET", f"/rest/v1/vehicles?id=eq.{vehicle_id}&select=id,stock_number,visible_on_board,lifecycle_state,version", admin)
        assert status == 200 and len(active_before) == 1

        # Viewer, AI-Auditor/importer and monitor-scoped Viewer cannot archive.
        params = {"p_vehicle_id": str(vehicle_id), "p_expected_version": version, "p_confirmation_stock": STOCK, "p_reason": REASON, "p_kind": "manual_delete"}
        viewer_denial = rpc(tokens["viewer"], "pdc_admin_archive_vehicle", params)
        auditor_denial = rpc(tokens["auditor"], "pdc_admin_archive_vehicle", params)
        monitor_denial = rpc(tokens["monitor"], "pdc_admin_archive_vehicle", params)
        assert denied(viewer_denial), viewer_denial
        assert denied(auditor_denial), auditor_denial
        assert denied(monitor_denial), monitor_denial

        deleted = response_ok(rpc(admin, "pdc_admin_archive_vehicle", params), "vehicle_soft_deleted")
        tombstone_id = deleted["data"]["tombstone_id"]

        cur.execute("select lifecycle_state::text,visible_on_board,stock_number,deleted_at is not null from public.vehicles where id=%s", (vehicle_id,))
        assert cur.fetchone() == ("deleted", False, None, True)
        cur.execute("select deleted_at is not null from public.workshop_bookings where id=%s", (booking_id,)); assert cur.fetchone()[0]
        cur.execute("select active from public.vehicle_workshop_line_adjustments where vehicle_id=%s", (vehicle_id,)); assert cur.fetchone()[0] is False
        preserve = {}
        for table in ("workshop_bookings","workshop_booking_history","vehicle_work_items","vehicle_parts_updates","vehicle_movements","audit_events"):
            column = "vehicle_id"
            cur.execute(f"select count(*) from public.{table} where {column}=%s", (vehicle_id,)); preserve[table] = cur.fetchone()[0]
            assert preserve[table] > 0, (table, preserve)
        status, snapshot = rpc(admin, "get_pdc_email_vehicle_location_snapshot", {})
        assert status == 200 and all(str(row.get("id")) != str(vehicle_id) for row in snapshot.get("data",{}).get("vehicles",[]))

        # Simulated Navision/import INSERT is blocked by the tombstone.
        conn.rollback()
        blocked = False
        try:
            cur.execute("insert into public.vehicles(permanent_vehicle_id,stock_number,customer_name,lifecycle_state,visible_on_board,current_location,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by) values(%s,%s,'Blocked import','active',true,'PMB','microsoft_navision','simulated-import',%s,'{}',%s,%s)", ("BLOCK-"+STOCK, STOCK, "BLOCK-"+STOCK, actor, actor))
            conn.commit()
        except psycopg2.Error as exc:
            conn.rollback(); blocked = "PDC_RECREATION_AUTHORIZATION_REQUIRED" in str(exc) or "PDC_VEHICLE_TOMBSTONED" in str(exc)
        assert blocked

        # Same UUID restore, no duplicate, preserved history remains.
        restored = response_ok(rpc(admin, "pdc_admin_restore_vehicle", {"p_tombstone_id": tombstone_id,"p_confirmation_stock": STOCK,"p_reason": "Restore disposable acceptance vehicle"}), "vehicle_restored")
        assert restored["data"]["vehicle_id"] == str(vehicle_id)
        cur.execute("select count(*),min(id::text),max(id::text) from public.vehicles where stock_number_normalized=public.normalize_vehicle_stock_number(%s)", (STOCK,)); count,min_id,max_id=cur.fetchone(); assert count==1 and min_id==max_id==str(vehicle_id)
        cur.execute("select deleted_at is not null from public.workshop_bookings where id=%s", (booking_id,)); assert cur.fetchone()[0]

        # Reset and one-time Email Monitor recreation permission.
        cur.execute("select version from public.vehicles where id=%s", (vehicle_id,)); reset_version=cur.fetchone()[0]
        reset = response_ok(rpc(admin,"pdc_admin_reset_staging_test_vehicle",{"p_vehicle_id":str(vehicle_id),"p_expected_version":reset_version,"p_confirmation_stock":STOCK,"p_reason":"Reset disposable Email Monitor acceptance vehicle"}),"vehicle_reset")
        reset_tombstone = reset["data"]["tombstone_id"]
        response_ok(rpc(admin,"pdc_admin_allow_vehicle_recreation_once",{"p_tombstone_id":reset_tombstone,"p_confirmation_stock":STOCK,"p_reason":"Allow controlled disposable Email Monitor recreation","p_ttl_minutes":30}),"recreation_authorized_once")
        recreated_id=str(uuid.uuid4())
        cur.execute("insert into public.vehicles(id,permanent_vehicle_id,stock_number,customer_name,lifecycle_state,visible_on_board,current_location,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by) values(%s,%s,%s,'Recreated disposable vehicle','active',true,'PMB','authenticated_email','pdc-monitor',%s,'{}',%s,%s)", (recreated_id,"EMAIL-"+STOCK,STOCK,"EMAIL-"+STOCK,actor,actor)); conn.commit()
        cur.execute("select consumed_at is not null,consumed_vehicle_id::text from public.pdc_vehicle_recreation_permissions where tombstone_id=%s",(reset_tombstone,)); consumed,consumed_id=cur.fetchone(); assert consumed and consumed_id==recreated_id
        second_blocked=False
        try:
            cur.execute("insert into public.vehicles(permanent_vehicle_id,stock_number,customer_name,lifecycle_state,visible_on_board,current_location,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by) values(%s,%s,'Second duplicate','active',true,'PMB','authenticated_email','pdc-monitor',%s,'{}',%s,%s)",( "EMAIL2-"+STOCK,STOCK,"EMAIL2-"+STOCK,actor,actor));conn.commit()
        except psycopg2.Error:
            conn.rollback();second_blocked=True
        assert second_blocked
        result={"schema":"pdc.delete-vehicle-live-acceptance/v1","project_ref":REF,"production_accessed":False,"stock":STOCK,"original_vehicle_id":str(vehicle_id),"recreated_vehicle_id":str(recreated_id),"delete_tombstone":tombstone_id,"reset_tombstone":reset_tombstone,"role_denials":["viewer","auditor_importer","monitor_viewer"],"preserved_rows":preserve,"simulated_import_blocked":blocked,"restore_same_uuid":True,"one_time_recreation_consumed":True,"second_duplicate_blocked":second_blocked,"passed":True}
        print(json.dumps(result,indent=2))
    finally:
        conn.rollback()
        for user_id,email in reversed(test_users):
            try:
                cur.execute("delete from public.pdc_monitor_stage_activation_writers where user_id=%s",(user_id,))
                cur.execute("delete from public.audit_events where actor_id=%s or metadata->>'target_email'=%s",(user_id,email))
                cur.execute("delete from public.pdc_user_roles where auth_user_id=%s",(user_id,));conn.commit()
            except Exception: conn.rollback()
            delete_test_user(user_id)
        cur.close();conn.close()

if __name__ == "__main__": main()
