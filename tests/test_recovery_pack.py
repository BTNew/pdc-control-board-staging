import hashlib
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RecoveryPackPortabilityTests(unittest.TestCase):
    def test_binary_fixtures_are_marked_binary_for_git_checkouts(self):
        attributes = (ROOT / 'recovery-pack' / '.gitattributes').read_text(encoding='utf-8')
        self.assertIn('*.pdf -text', attributes)
        self.assertIn('*.gz -text', attributes)

    def test_manifest_hashing_canonicalizes_windows_text_line_endings(self):
        builder = load('recovery_pack_builder', ROOT / 'recovery-pack' / 'build_manifest.py')
        self.assertEqual(builder.canonical_digest(b'alpha\r\nbeta\r\n', Path('x.md')), builder.canonical_digest(b'alpha\nbeta\n', Path('x.md')))
        self.assertNotEqual(builder.canonical_digest(b'alpha\r\nbeta\r\n', Path('x.pdf')), builder.canonical_digest(b'alpha\nbeta\n', Path('x.pdf')))

    def test_bootstrap_uses_the_same_canonical_hashing_rule(self):
        bootstrap = load('recovery_bootstrap', ROOT / 'recovery-pack' / 'bootstrap_recovery.py')
        self.assertEqual(bootstrap.sha256_bytes(b'alpha\r\nbeta\r\n', Path('x.json')), bootstrap.sha256_bytes(b'alpha\nbeta\n', Path('x.json')))


if __name__ == '__main__':
    unittest.main()
