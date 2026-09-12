#!/usr/bin/env python3
"""Cold-process startup smoke on a connected device; never a phone benchmark.

Retains app data between runs, force-stops the process, waits for the first real
home frame marker, and fails on timeout/crash. Animations remain enabled.
"""
import argparse
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import time
import xml.etree.ElementTree as ET

PACKAGE = 'de.loicezt.stickers'
OUT = Path('build/startup')


def adb(*args, timeout=45):
    return subprocess.check_output(['adb', *args], timeout=timeout, text=True)


def run_start(index):
    adb('shell', 'am', 'force-stop', PACKAGE)
    adb('logcat', '-c')
    launch = adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity')
    (OUT / f'launch-{index}.txt').write_text(launch)
    assert 'Status: ok' in launch, launch
    deadline = time.monotonic() + 30
    logs = ''
    while time.monotonic() < deadline:
        logs = adb('logcat', '-d', '-v', 'threadtime')
        if 'FATAL EXCEPTION' in logs or 'Fatal signal' in logs or '[ERROR:flutter' in logs:
            raise AssertionError('Runtime crash/error; see logcat')
        ready = re.search(r'StickersStartup.*home_ready_ms=(\d+)', logs)
        if ready:
            (OUT / f'logcat-{index}.txt').write_text(logs)
            subprocess.run(['adb', 'exec-out', 'screencap', '-p'], check=True,
                           stdout=(OUT / f'home-{index}.png').open('wb'), timeout=15)
            total = re.search(r'TotalTime:\s*(\d+)', launch)
            data_ready = re.search(r'Startup data ready: (\d+)ms', logs)
            first_frame = re.search(r'Startup first frame: (\d+)ms', logs)
            return {'iteration': index,
                    'dart_data_ready_ms': int(data_ready[1]) if data_ready else None,
                    'dart_first_frame_ms': int(first_frame[1]) if first_frame else None,
                    'home_ready_ms': int(ready[1]),
                    'am_total_ms': int(total[1]) if total else None}
        time.sleep(0.25)
    (OUT / f'logcat-{index}.txt').write_text(logs)
    raise AssertionError('No real home frame within 30s')


def ui_node(label, attempts=4):
    for attempt in range(attempts):
        adb('shell', 'uiautomator', 'dump', '/sdcard/stickers-window.xml')
        xml = adb('shell', 'cat', '/sdcard/stickers-window.xml')
        (OUT / 'window.xml').write_text(xml)
        root = ET.fromstring(xml)
        for node in root.iter('node'):
            text = node.get('text', '') + node.get('content-desc', '')
            if label in text:
                return node
        time.sleep(0.5)
    raise AssertionError(f'UI element not found: {label}; see window.xml')


def tap_node(node):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.attrib['bounds']))
    adb('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))


def check_lazy_fonts():
    # Exercise the actual shrunk native font-registration plugin on first use,
    # not just a mocked FutureBuilder. The app and emulator use English here.
    tap_node(ui_node('Settings'))
    tap_node(ui_node('Fonts manager'))
    ui_node('Lobster', attempts=8)
    with (OUT / 'fonts.png').open('wb') as screenshot:
        subprocess.run(['adb', 'exec-out', 'screencap', '-p'], check=True,
                       stdout=screenshot, timeout=15)
    logs = adb('logcat', '-d', '-v', 'threadtime')
    (OUT / 'fonts-logcat.txt').write_text(logs)
    assert 'FATAL EXCEPTION' not in logs and '[ERROR:flutter' not in logs, 'Font page runtime error'
    print('::notice title=Lazy fonts smoke::First-use font manager rendered Lobster after native registration')


def baseline_starts(apk):
    adb('install', '-r', apk, timeout=90)
    times = []
    for index in range(6):
        adb('shell', 'am', 'force-stop', PACKAGE)
        launch = adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity')
        (OUT / f'baseline-launch-{index}.txt').write_text(launch)
        assert 'Status: ok' in launch, launch
        total = re.search(r'TotalTime:\s*(\d+)', launch)
        assert total, launch
        times.append(int(total[1]))
        time.sleep(1)
    (OUT / 'baseline-logcat.txt').write_text(adb('logcat', '-d', '-v', 'threadtime'))
    return {'first_install_am_total_ms': times[0], 'restart_am_total_ms': times[1:],
            'restart_median_am_total_ms': statistics.median(times[1:])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk')
    parser.add_argument('--baseline', help='Optional old APK; tests in-place update with the same signing key')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    try:
        baseline = baseline_starts(args.baseline) if args.baseline else None
        adb('install', '-r', args.apk, timeout=90)
        results = [run_start(i) for i in range(6)]
        # Separate first-install initialization from process-cold/cache-warm
        # restarts. Emulator load fluctuates: no fabricated "instant" threshold.
        summary = {'first_launch': results[0], 'baseline': baseline, 'restarts': results[1:],
                   'restart_median_ms': statistics.median(r['home_ready_ms'] for r in results[1:]),
                   'restart_max_ms': max(r['home_ready_ms'] for r in results[1:]),
                   'restart_median_am_total_ms': statistics.median(r['am_total_ms'] for r in results[1:])}
        (OUT / 'startup.json').write_text(json.dumps(summary, indent=2) + '\n')
        message = (f"First launch home: {results[0]['home_ready_ms']}ms; "
                   f"cold-process median: {summary['restart_median_ms']}ms; "
                   f"max: {summary['restart_max_ms']}ms (emulator, not phone)")
        dart_data = [r['dart_data_ready_ms'] for r in results[1:] if r['dart_data_ready_ms'] is not None]
        dart_frames = [r['dart_first_frame_ms'] for r in results[1:] if r['dart_first_frame_ms'] is not None]
        if dart_data and dart_frames:
            message += (f"; Dart data median: {statistics.median(dart_data)}ms; "
                        f"Dart first frame median: {statistics.median(dart_frames)}ms")
        print(f'::notice title=Startup smoke::{message}')
        if baseline:
            comparison = (f"Same-emulator am start median: debug baseline "
                          f"{baseline['restart_median_am_total_ms']}ms -> release "
                          f"{summary['restart_median_am_total_ms']}ms; in-place upgrade succeeded")
            print(f'::notice title=Startup comparison::{comparison}')
            message += '\n\n' + comparison
        check_lazy_fonts()
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as f:
                f.write(f'\n### Release startup smoke\n\n{message}\n')
    finally:
        (OUT / 'final-logcat.txt').write_text(adb('logcat', '-d', '-v', 'threadtime'))
        (OUT / 'device.txt').write_text(adb('shell', 'getprop'))


if __name__ == '__main__':
    main()
