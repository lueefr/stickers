#!/usr/bin/env python3
"""Inspect final APK ZIP bytes (not intermediate Gradle estimates)."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

ABIS = ('arm64-v8a', 'armeabi-v7a', 'x86_64')
JNI_METHODS = ('nativeGetInfo', 'nativeDecode', 'nativeInitEncoder',
               'nativeAddFrameYuv', 'nativeAddFrame', 'nativeReleaseEncoder')


def category(name):
    if name.startswith('lib/'):
        return '/'.join(name.split('/')[:2])
    if name.endswith('.dex'):
        return 'dex'
    if name.startswith('assets/flutter_assets/'):
        return 'flutter assets'
    return 'android resources / metadata'


def inspect_apk(path, check_native=True):
    path = Path(path)
    with zipfile.ZipFile(path) as apk:
        names = apk.namelist()
        assert not any(n.endswith(('kernel_blob.bin', 'vm_snapshot_data', 'isolate_snapshot_data'))
                       for n in names), 'Debug/JIT payload found in release APK'
        abis = sorted({n.split('/')[1] for n in names if n.startswith('lib/')})
        expected = [a for a in ABIS if a in path.name]
        if expected:
            assert abis == expected, f'Wrong split ABIs: {abis}, expected {expected}'
        else:
            assert abis == sorted(ABIS), f'Universal must preserve all ABIs: {abis}'
        fonts = [n for n in names if n.startswith('assets/flutter_assets/assets/fonts/') and n.endswith('.ttf')]
        assert len(fonts) == 11, f'Bundled font lost: {fonts}'
        for shader in ('hue', 'saturation', 'lightness'):
            assert any(n.endswith(f'{shader}_gradient.frag') for n in names), f'Missing {shader} shader'
        assert any(n.endswith('assets/fonts/OFL.txt') for n in names), 'Missing font license'
        for abi in abis:
            assert f'lib/{abi}/libapp.so' in names, 'Missing AOT application'
            assert f'lib/{abi}/libflutter.so' in names, 'Missing Flutter engine'
            native = f'lib/{abi}/libstickers.so'
            assert native in names, 'Missing animated sticker codec'
            if check_native:
                with tempfile.TemporaryDirectory() as tmp:
                    so = Path(tmp) / 'libstickers.so'
                    so.write_bytes(apk.read(native))
                    symbols = subprocess.check_output(['readelf', '--dyn-syms', '--wide', str(so)], text=True)
                    for method in JNI_METHODS:
                        symbol = 'Java_de_loicezt_stickers_video_LibWebP_' + method
                        assert symbol in symbols, f'JNI entry stripped: {abi}/{method}'
        groups = {}
        for entry in apk.infolist():
            key = category(entry.filename)
            groups[key] = groups.get(key, 0) + entry.compress_size
        largest = sorted(apk.infolist(), key=lambda e: e.compress_size, reverse=True)[:12]
        return {
            'apk': path.name, 'bytes': path.stat().st_size, 'abis': abis,
            'compressed_groups': groups,
            'largest_entries': [{'name': e.filename, 'bytes': e.compress_size} for e in largest],
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apks', nargs='+')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    reports = [inspect_apk(p) for p in args.apks]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(reports, indent=2) + '\n')
    print('### Final release APK size\n\n| APK | MiB | Bytes |\n|---|---:|---:|')
    for r in reports:
        print(f"| {r['apk']} | {r['bytes'] / 2**20:.2f} | {r['bytes']} |")
        # Also annotations: available through the checks API when log/artifact
        # downloads are blocked by a restricted developer network.
        print(f"::notice title=APK size::{r['apk']}: {r['bytes']} bytes")
    print('\nValidated AOT, ABIs, all 11 fonts, licenses, shaders and exported WebP JNI methods.')


if __name__ == '__main__':
    main()
