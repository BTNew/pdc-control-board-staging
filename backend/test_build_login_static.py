"""Regression tests for the sanitised login-static production builder."""

from __future__ import annotations

import re
import shutil
import tempfile
import unittest
from pathlib import Path

from backend import build_login_static as builder


class BuildLoginStaticClosureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = Path(tempfile.mkdtemp(prefix="pdc-login-static-test-"))
        self.original_target = builder.TARGET
        self.original_files = builder.FILES
        builder.TARGET = self.temp_dir / "artifact"

    def tearDown(self) -> None:
        builder.TARGET = self.original_target
        builder.FILES = self.original_files
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    @staticmethod
    def runtime_references(root: Path) -> set[str]:
        index_text = (root / "index.html").read_text(encoding="utf-8")
        app_text = (root / "app.js").read_text(encoding="utf-8")
        references = {
            match.group(1)
            for match in re.finditer(r'(?:src|href)="([^"?]+)(?:\?[^\"]*)?"', index_text)
            if not match.group(1).startswith(("http://", "https://", "#", "data:"))
        }
        references.update(
            match.group(1)
            for match in re.finditer(r"[`'\"]([A-Za-z0-9_./-]+\.js)(?:\?[^`'\"]*)?[`'\"]", app_text)
        )
        return references

    def test_generated_login_artifact_closes_direct_and_lazy_runtime_graph(self) -> None:
        builder.main()
        references = self.runtime_references(builder.TARGET)
        missing = sorted(reference for reference in references if not (builder.TARGET / reference).is_file())
        self.assertEqual(missing, [])
        for required in (
            "vehicle-lifecycle-actions.js",
            "workshop-data-service.js",
            "workshop-realtime.js",
            "workshop-shared-actions.js",
        ):
            self.assertIn(required, references)
            self.assertTrue((builder.TARGET / required).is_file())

    def test_builder_fails_closed_when_lazy_runtime_member_is_omitted(self) -> None:
        builder.FILES = tuple(path for path in builder.FILES if path != "vehicle-lifecycle-actions.js")
        with self.assertRaisesRegex(SystemExit, "lazy-loads.*vehicle-lifecycle-actions\\.js"):
            builder.main()


if __name__ == "__main__":
    unittest.main()
