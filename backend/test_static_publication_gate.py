from __future__ import annotations

import contextlib
import io
import os
import sys
import unittest
from unittest import mock

import update_website_from_email as updater


class StaticPublicationGateTests(unittest.TestCase):
    def run_main(self, argv: list[str], env: dict[str, str] | None = None):
        output = io.StringIO()
        with mock.patch.object(sys, "argv", ["update_website_from_email.py", *argv]), \
                mock.patch.dict(os.environ, env or {}, clear=True), \
                mock.patch.object(updater, "run", side_effect=[(0, "bridge"), (0, "publisher")]) as run_mock, \
                contextlib.redirect_stdout(output):
            result = updater.main()
        return result, output.getvalue(), run_mock

    def test_static_publication_is_denied_without_explicit_environment_gate(self):
        result, output, run_mock = self.run_main(["--publish-static"])
        self.assertEqual(result, 2)
        self.assertIn("Static publication is locked", output)
        run_mock.assert_not_called()

    def test_default_generation_is_private_and_never_commits(self):
        result, _output, run_mock = self.run_main([])
        self.assertEqual(result, 0)
        publisher_command = run_mock.call_args_list[1].args[0]
        self.assertIn("--output", publisher_command)
        self.assertIn(str(updater.PRIVATE_GENERATED_OUTPUT), publisher_command)
        self.assertNotIn("--commit-push", publisher_command)

    def test_explicit_gate_allows_legacy_static_publish_only_when_requested(self):
        result, _output, run_mock = self.run_main(
            ["--publish-static"],
            {"PDC_ALLOW_STATIC_PUBLICATION": updater.STATIC_PUBLISH_CONFIRMATION},
        )
        self.assertEqual(result, 0)
        publisher_command = run_mock.call_args_list[1].args[0]
        self.assertIn("--commit-push", publisher_command)
        self.assertNotIn("--output", publisher_command)


if __name__ == "__main__":
    unittest.main()
