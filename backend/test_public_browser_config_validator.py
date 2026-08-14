import json
import tempfile
import unittest
from pathlib import Path

from scripts.validate_public_browser_config import ConfigValidationError, load_and_validate_public_browser_config


PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PRODUCTION_URL = f"https://{PRODUCTION_REF}.supabase.co"


def canonical_config(**overrides):
    config = {
        "environment": "production",
        "projectRef": PRODUCTION_REF,
        "url": PRODUCTION_URL,
        "publishableKey": "sb_publishable_" + ("A" * 32),
        "auth": {"mode": "password", "provider": "azure"},
        "workshop": {"sharedData": True},
        "vehicleLifecycle": {"sharedData": True},
    }
    config.update(overrides)
    return config


def script_for(config, suffix=""):
    return "window.PDC_SUPABASE_CONFIG = " + json.dumps(config, separators=(",", ":"), sort_keys=True) + ";\n" + suffix


class PublicBrowserConfigValidatorTests(unittest.TestCase):
    def validate(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "pdc-supabase-config.production.js"
            path.write_text(text, encoding="utf-8", newline="\n")
            return load_and_validate_public_browser_config(path)

    def assert_rejected(self, text):
        with self.assertRaises(ConfigValidationError):
            self.validate(text)

    def test_canonical_public_config_passes(self):
        self.assertEqual(self.validate(script_for(canonical_config()))["projectRef"], PRODUCTION_REF)

    def test_real_repository_config_passes(self):
        root = Path(__file__).resolve().parents[1]
        config = load_and_validate_public_browser_config(root / "pdc-supabase-config.production.js")
        self.assertEqual(config["projectRef"], PRODUCTION_REF)

    def test_cross_project_config_fails_even_if_production_ref_is_elsewhere(self):
        wrong = canonical_config(projectRef="aaaaaaaaaaaaaaaaaaaa", url="https://aaaaaaaaaaaaaaaaaaaa.supabase.co")
        self.assert_rejected(script_for(wrong, suffix=f"// {PRODUCTION_REF}\n"))

    def test_unapproved_gateway_or_extra_field_fails(self):
        self.assert_rejected(script_for(canonical_config(auditorOperationGateway={"url": "https://gateway.example"})))

    def test_jwt_secret_key_and_database_dsn_fail(self):
        for value in (
            "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature",
            "sb_secret_" + ("A" * 32),
            "postgresql://user:password@example.invalid/database",
        ):
            self.assert_rejected(script_for(canonical_config(publishableKey=value)))

    def test_staging_and_rollback_fields_fail(self):
        bad = canonical_config(environment="staging", vehicleLifecycle={"sharedData": True, "resolverRollbackDirectRead": True})
        self.assert_rejected(script_for(bad))

    def test_expression_and_trailing_executable_code_fail(self):
        expression = script_for(canonical_config()).replace('"provider":"azure"', '"provider":window.location.origin')
        self.assert_rejected(expression)
        self.assert_rejected(script_for(canonical_config(), suffix="window.leak = true;\n"))


if __name__ == "__main__":
    unittest.main()
