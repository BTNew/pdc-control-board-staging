#!/usr/bin/env python3
"""Authenticated, read-only HTTP role smoke for installed migration 065."""
from __future__ import annotations
import json
import os
import urllib.error
import urllib.request
import uuid

PROJECT = "cdsmnqxtyyoeoznmbidd"
PRODUCTION = "vjdtsswhroyguxyfjdkt"


def required(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing {name}")
    return value


def post(url, headers, body):
    request = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), headers={"Content-Type": "application/json", **headers}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = {"message": raw}
        return error.code, body


def main():
    base = required("PDC_STAGING_SUPABASE_URL").rstrip("/")
    anon = required("PDC_STAGING_ANON_KEY")
    if PROJECT not in base or PRODUCTION in base:
        raise RuntimeError("Refusing non-staging endpoint")

    def token(label):
        status, auth = post(base + "/auth/v1/token?grant_type=password", {"apikey": anon}, {
            "email": required(f"PDC_STAGING_{label}_EMAIL"),
            "password": required(f"PDC_STAGING_{label}_PASSWORD"),
        })
        if status != 200 or not auth.get("access_token"):
            raise AssertionError(f"{label} login failed with HTTP {status}")
        return auth["access_token"]

    def rpc(access_token, name, payload):
        return post(base + "/rest/v1/rpc/" + name, {"apikey": anon, "Authorization": "Bearer " + access_token}, payload)

    invalid = {
        "p_idempotency_key": "pdc-ai-intake-" + uuid.uuid4().hex,
        "p_proposal_id": str(uuid.uuid4()),
        "p_expected_version": 1,
        "p_expected_inbox_revision": 0,
        "p_expected_action": "board_activate_only",
        "p_decision": "reject",
        "p_fingerprint": "A065A065A065A065",
        "p_expected_navision_revision": None,
        "p_reason": "Authenticated role-matrix smoke with a nonexistent proposal",
    }
    admin = token("ADMIN")
    admin_status, admin_snapshot = rpc(admin, "get_pdc_ai_intake_snapshot", {"p_status": "pending", "p_page_size": 10})
    assert admin_status == 200 and admin_snapshot.get("ok") is True and admin_snapshot.get("code") == "snapshot"
    assert isinstance(admin_snapshot.get("data", {}).get("navision_revision"), int)
    invalid["p_expected_inbox_revision"] = admin_snapshot["data"]["revision"]
    invalid["p_expected_navision_revision"] = admin_snapshot["data"]["navision_revision"]
    admin_decision_status, admin_decision = rpc(admin, "decide_pdc_ai_intake_proposal", invalid)
    assert admin_decision_status == 200 and admin_decision.get("ok") is False and admin_decision.get("code") == "proposal_not_found"

    denied = {}
    for label in ("VIEWER", "CONTROLLER_A", "CONTROLLER_B", "UNAPPROVED"):
        access = token(label)
        snapshot_status, snapshot = rpc(access, "get_pdc_ai_intake_snapshot", {"p_status": "pending", "p_page_size": 1})
        decision_status, decision = rpc(access, "decide_pdc_ai_intake_proposal", invalid)
        assert snapshot_status == 200 and snapshot.get("ok") is False and snapshot.get("code") == "unauthorized", (label, snapshot_status, snapshot)
        assert decision_status == 200 and decision.get("ok") is False and decision.get("code") == "unauthorized", (label, decision_status, decision)
        denied[label.lower()] = True

    anonymous_snapshot_status, anonymous_snapshot = rpc(anon, "get_pdc_ai_intake_snapshot", {"p_status": "pending", "p_page_size": 1})
    assert anonymous_snapshot_status in (401, 403) or anonymous_snapshot.get("ok") is False
    print(json.dumps({
        "admin_snapshot": "allowed",
        "admin_nonexistent_decision": "proposal_not_found",
        "denied_roles": denied,
        "anonymous_denied": True,
        "state_mutated": False,
        "production_contacted": False,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
