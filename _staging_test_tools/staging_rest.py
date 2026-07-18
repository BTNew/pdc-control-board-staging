import json
import urllib.request
import urllib.error

from staging_env import assert_staging_target, required

# Every value comes from the process environment or the ignored local .env.
# No project-specific key or credential is stored in committed test source.
PROJECT_URL = required("PDC_STAGING_SUPABASE_URL").rstrip("/")
SERVICE_KEY = required("PDC_STAGING_SERVICE_ROLE_KEY")
ANON_KEY = required("PDC_STAGING_ANON_KEY")
assert_staging_target(project_url=PROJECT_URL)


def _req(method, path, headers=None, body=None, base=PROJECT_URL):
    url = base + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = raw.decode(errors="replace")
        return e.code, parsed


def admin_create_user(email, password, email_confirm=True):
    status, body = _req(
        "POST", "/auth/v1/admin/users",
        headers={"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}"},
        body={"email": email, "password": password, "email_confirm": email_confirm},
    )
    return status, body


def admin_delete_user(user_id):
    return _req(
        "DELETE", f"/auth/v1/admin/users/{user_id}",
        headers={"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}"},
    )


def sign_in(email, password):
    status, body = _req(
        "POST", "/auth/v1/token?grant_type=password",
        headers={"apikey": ANON_KEY},
        body={"email": email, "password": password},
    )
    return status, body


def rpc(access_token, fn_name, params):
    status, body = _req(
        "POST", f"/rest/v1/rpc/{fn_name}",
        headers={"apikey": ANON_KEY, "Authorization": f"Bearer {access_token}"},
        body=params,
    )
    return status, body


def rest_select(access_token, table, query=""):
    status, body = _req(
        "GET", f"/rest/v1/{table}{query}",
        headers={"apikey": ANON_KEY, "Authorization": f"Bearer {access_token}"},
    )
    return status, body


def rest_insert(access_token, table, row):
    status, body = _req(
        "POST", f"/rest/v1/{table}",
        headers={"apikey": ANON_KEY, "Authorization": f"Bearer {access_token}", "Prefer": "return=representation"},
        body=row,
    )
    return status, body
