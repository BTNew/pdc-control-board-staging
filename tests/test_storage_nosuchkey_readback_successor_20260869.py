from __future__ import annotations

import importlib.util
import io
import json
import time
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "backend/imap_bridge_successor_20260865.py"


def load_bridge():
    spec = importlib.util.spec_from_file_location("imap_bridge_storage_retry_20260869", SOURCE)
    if spec is None or spec.loader is None:
        raise RuntimeError("bridge source could not be loaded")
    module = importlib.util.module_from_spec(spec)
    import sys
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class Response:
    status = 200
    headers = {"Content-Type": "image/jpeg"}

    def __init__(self, payload: bytes):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def read(self, _limit):
        return self.payload


def no_such_key_error(body: dict) -> urllib.error.HTTPError:
    return urllib.error.HTTPError(
        "https://cdsmnqxtyyoeoznmbidd.supabase.co/storage/v1/object/authenticated/pdc-email-intake-private/x",
        400,
        "Bad Request",
        {},
        io.BytesIO(json.dumps(body).encode()),
    )


class StorageNoSuchKeyReadbackSuccessorTests(unittest.TestCase):
    def test_exact_nosuchkey_retries_and_accepts_verified_bytes(self):
        module = load_bridge()
        calls = 0

        def opener(_request, timeout):
            nonlocal calls
            self.assertEqual(timeout, 60)
            calls += 1
            if calls < 3:
                raise no_such_key_error({"code": "NoSuchKey", "statusCode": 404, "message": "Object not found"})
            return Response(b"jpeg")

        with patch.object(module.urllib.request, "urlopen", side_effect=opener), patch.object(module.time, "sleep") as sleeper:
            module._read_storage_object("https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon", "token", "hash/image.jpg", b"jpeg", "image/jpeg")

        self.assertEqual(calls, 3)
        self.assertEqual([call.args[0] for call in sleeper.call_args_list], [0.25, 0.5])

    def test_nosuchkey_is_bounded_and_fails_closed(self):
        module = load_bridge()
        def opener_side_effect(_request, **_kwargs):
            raise no_such_key_error({"code": "NoSuchKey", "statusCode": 404, "message": "Object not found"})

        with patch.object(module.urllib.request, "urlopen", side_effect=opener_side_effect) as opener, patch.object(module.time, "sleep") as sleeper:
            with self.assertRaisesRegex(RuntimeError, r"Storage object readback failed HTTP 400"):
                module._read_storage_object("https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon", "token", "hash/image.jpg", b"jpeg", "image/jpeg")
        self.assertEqual(opener.call_count, 3)
        self.assertEqual(sleeper.call_count, 2)

    def test_near_miss_storage_error_is_not_retried(self):
        module = load_bridge()
        error = no_such_key_error({"code": "NoSuchKey", "statusCode": 404, "message": "Not found"})
        with patch.object(module.urllib.request, "urlopen", side_effect=error) as opener, patch.object(module.time, "sleep") as sleeper:
            with self.assertRaisesRegex(RuntimeError, r"Storage object readback failed HTTP 400"):
                module._read_storage_object("https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon", "token", "hash/image.jpg", b"jpeg", "image/jpeg")
        self.assertEqual(opener.call_count, 1)
        sleeper.assert_not_called()

    def test_mismatch_after_retry_remains_fail_closed(self):
        module = load_bridge()
        with patch.object(module.urllib.request, "urlopen", return_value=Response(b"wrong")), patch.object(module.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, r"does not match verified attachment"):
                module._read_storage_object("https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon", "token", "hash/image.jpg", b"jpeg", "image/jpeg")


if __name__ == "__main__":
    unittest.main(verbosity=2)
