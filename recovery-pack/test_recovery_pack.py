import hashlib
import importlib.util
from pathlib import Path
import re
import unittest

PACK = Path(__file__).resolve().parent


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RecoveryPackTests(unittest.TestCase):
    def test_binary_checkout_attributes_are_present(self):
        text = (PACK / '.gitattributes').read_text(encoding='utf-8')
        self.assertIn('*.pdf -text', text)
        self.assertIn('*.gz -text', text)

    def test_hash_contract_matches_windows_and_posix_text(self):
        builder = load('builder', PACK / 'build_manifest.py')
        bootstrap = load('bootstrap', PACK / 'bootstrap_recovery.py')
        for module, function in ((builder, 'canonical_digest'), (bootstrap, 'sha256_bytes')):
            digest = getattr(module, function)
            self.assertEqual(digest(b'alpha\r\nbeta\r\n', Path('x.json')), digest(b'alpha\nbeta\n', Path('x.json')))
            self.assertEqual(digest(b'alpha\r\nbeta\r\n', Path('.gitattributes')), digest(b'alpha\nbeta\n', Path('.gitattributes')))
            self.assertNotEqual(digest(b'alpha\r\nbeta\r\n', Path('x.pdf')), digest(b'alpha\nbeta\n', Path('x.pdf')))

    def test_acl_pattern_covers_real_icacls_forms(self):
        source = (PACK / 'FAILURE-MODES.md').read_text(encoding='utf-8')
        self.assertIn('NT AUTHORITY', source)
        pattern = re.compile(r'(?:S-1-5-19|NT AUTHORITY\\LOCAL SERVICE):(?:\(OI\)\(CI\))?\(RX\)')
        self.assertRegex('NT AUTHORITY\\LOCAL SERVICE:(OI)(CI)(RX)', pattern)
        self.assertRegex('S-1-5-19:(OI)(CI)(RX)', pattern)

    def test_bootstrap_scans_manifest_files_not_generated_workspace_dirs(self):
        source = (PACK / 'bootstrap_recovery.py').read_text(encoding='utf-8')
        self.assertIn('for relative in sorted(expected)', source)
        self.assertNotIn('for path in pack.rglob', source)


if __name__ == '__main__':
    unittest.main()
