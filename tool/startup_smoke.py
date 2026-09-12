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
            return {'iteration': index, 'home_ready_ms': int(ready[1]),
                    'am_total_ms': int(total[1]) if total else None}
        time.sleep(0.25)
    (OUT / f'logcat-{index}.txt').write_text(logs)
    raise AssertionError('No real home frame within 30s')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    try:
        adb('install', '-r', args.apk, timeout=90)
        results = [run_start(i) for i in range(6)]
        # Separate first-install initialization from process-cold/cache-warm
        # restarts. Emulator load fluctuates: no fabricated "instant" threshold.
        summary = {'first_install': results[0], 'restarts': results[1:],
                   'restart_median_ms': statistics.median(r['home_ready_ms'] for r in results[1:]),
                   'restart_max_ms': max(r['home_ready_ms'] for r in results[1:])}
        (OUT / 'startup.json').write_text(json.dumps(summary, indent=2) + '\n')
        message = (f"First install home: {results[0]['home_ready_ms']}ms; "
                   f"cold-process median: {summary['restart_median_ms']}ms; "
                   f"max: {summary['restart_max_ms']}ms (emulator, not phone)")
        print(f'::notice title=Startup smoke::{message}')
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as f:
                f.write(f'\n### Release startup smoke\n\n{message}\n')
    finally:
        (OUT / 'final-logcat.txt').write_text(adb('logcat', '-d', '-v', 'threadtime'))
        (OUT / 'device.txt').write_text(adb('shell', 'getprop'))


if __name__ == '__main__':
    main()
