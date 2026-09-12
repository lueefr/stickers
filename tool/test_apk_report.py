import tempfile
import unittest
from pathlib import Path
import zipfile

from apk_report import ABIS, category, inspect_apk


class ApkReportTest(unittest.TestCase):
    def make_apk(self, path, abis, debug=False, fonts=11):
        with zipfile.ZipFile(path, 'w') as apk:
            for abi in abis:
                for lib in ('app', 'flutter', 'stickers'):
                    apk.writestr(f'lib/{abi}/lib{lib}.so', b'fixture')
            for i in range(fonts):
                apk.writestr(f'assets/flutter_assets/assets/fonts/font{i}.ttf', b'font')
            apk.writestr('assets/flutter_assets/assets/fonts/OFL.txt', b'license')
            for name in ('hue', 'saturation', 'lightness'):
                apk.writestr(f'assets/flutter_assets/assets/shaders/{name}_gradient.frag', b'shader')
            if debug:
                apk.writestr('assets/flutter_assets/kernel_blob.bin', b'debug')

    def test_split_and_universal(self):
        with tempfile.TemporaryDirectory() as tmp:
            for suffix, abis in [('arm64-v8a', ['arm64-v8a']), ('universal', ABIS)]:
                path = Path(tmp) / f'stickers-{suffix}-release.apk'
                self.make_apk(path, abis)
                result = inspect_apk(path, check_native=False)
                self.assertEqual(result['abis'], sorted(abis))
                self.assertEqual(result['bytes'], path.stat().st_size)

    def test_rejects_debug_missing_fonts_and_wrong_abi(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'stickers-arm64-v8a-release.apk'
            for kwargs in ({'debug': True}, {'fonts': 10}, {'abis': ABIS}):
                options = {'abis': ['arm64-v8a'], **kwargs}
                self.make_apk(path, **options)
                with self.assertRaises(AssertionError):
                    inspect_apk(path, check_native=False)

    def test_categories(self):
        self.assertEqual(category('lib/arm64-v8a/libapp.so'), 'lib/arm64-v8a')
        self.assertEqual(category('classes2.dex'), 'dex')
