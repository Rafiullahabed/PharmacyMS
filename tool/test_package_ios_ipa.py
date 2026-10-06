"""Archive-level tests only; fixtures are not real iOS builds."""

import hashlib
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

from package_ios_ipa import package_ipa


class IpaPackagingTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / 'Runner.app'
        self.app.mkdir()
        self.output = self.root / 'output' / 'pharmacy.ipa'
        self.info = {
            'CFBundleSupportedPlatforms': ['iPhoneOS'],
            'CFBundleExecutable': 'Runner',
            'CFBundleIdentifier': 'com.example.pharmacyms',
            'CFBundleShortVersionString': '0.8.0',
            'CFBundleVersion': '8',
            'MinimumOSVersion': '13.0',
        }
        self.write_plist()
        for name in ['Runner', 'Frameworks/App.framework/App', 'Frameworks/Flutter.framework/Flutter']:
            path = self.app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'\xcf\xfa\xed\xfearchive-test-fixture-only')
        (self.app / 'persian.txt').write_text('دارو — Pharmacy', encoding='utf-8')

    def write_plist(self):
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info, fmt=plistlib.FMT_BINARY))

    def test_payload_and_exact_contents_and_checksum(self):
        result = package_ipa(self.app, self.output)
        self.assertFalse(result['device_installation_verified'])
        self.assertIn('Unsigned', result['signing'])
        self.assertEqual(result['sha256'], hashlib.sha256(self.output.read_bytes()).hexdigest())
        with zipfile.ZipFile(self.output) as archive:
            self.assertIsNone(archive.testzip())
            self.assertTrue(all(name.startswith('Payload/Runner.app/') for name in archive.namelist()))
            self.assertEqual(archive.read('Payload/Runner.app/persian.txt'), (self.app / 'persian.txt').read_bytes())
            self.assertEqual(archive.read('Payload/Runner.app/Runner'), (self.app / 'Runner').read_bytes())

    def test_simulator_rejected_without_overwriting_existing_ipa(self):
        self.output.parent.mkdir()
        self.output.write_bytes(b'previous-ipa')
        self.info['CFBundleSupportedPlatforms'] = ['iPhoneSimulator']
        self.write_plist()
        with self.assertRaisesRegex(ValueError, 'device build'):
            package_ipa(self.app, self.output)
        self.assertEqual(self.output.read_bytes(), b'previous-ipa')

    def test_missing_framework_rejected(self):
        (self.app / 'Frameworks/App.framework/App').unlink()
        with self.assertRaises(FileNotFoundError):
            package_ipa(self.app, self.output)
        self.assertFalse(self.output.exists())

    def test_source_placeholder_is_not_packaged_as_binary(self):
        (self.app / 'Runner').write_text('not a compiled app')
        with self.assertRaisesRegex(ValueError, 'Mach-O'):
            package_ipa(self.app, self.output)
        self.assertFalse(self.output.exists())

    def test_output_inside_bundle_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'outside'):
            package_ipa(self.app, self.app / 'nested.ipa')


if __name__ == '__main__':
    unittest.main()
