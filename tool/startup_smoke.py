#!/usr/bin/env python3
"""Cold-process startup smoke on a connected device; never a phone benchmark.

Retains app data between runs, force-stops the process, waits for the first real
home frame marker, and fails on timeout/crash. Animations remain enabled.

`am start -W` answers "timeout"/LaunchState UNKNOWN when the activity does not
report within the ActivityManager launch window (~10s). The historical debug
baseline is a 171 MiB JIT APK: on a loaded CI emulator its first open can exceed
that window even when the app is healthy. Launches therefore retry, the baseline
gets a discarded warm-up launch, and an unmeasurable baseline degrades to a
warning instead of failing the release smoke it only exists to compare against.
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
# `am start -W` blocks until the launch settles or the framework gives up
# (~12s observed), and `adb` itself can hang on a busy emulator; the subprocess
# timeout is only the outer safety net for a wedged transport.
ADB_TIMEOUT = 120
LAUNCH_ATTEMPTS = 3
# The baseline is a debug/JIT build: its first open pays dexopt/JIT warm-up and
# is not comparable with the restarts, so it is launched once and discarded.
BASELINE_WARMUP_ATTEMPTS = 3
# Warm-up (discarded) plus six measured launches keeps the previous
# median-over-five-restarts methodology: measured[0] is the first-install
# launch, measured[1:] are the cold-process restarts the median is taken over.
BASELINE_SAMPLES = 6


def adb(*args, timeout=ADB_TIMEOUT):
    return subprocess.check_output(['adb', *args], timeout=timeout, text=True)


def parse_launch(output):
    """Classify one `am start -W` answer: ok, timeout, error or incomplete."""
    total = re.search(r'TotalTime:\s*(\d+)', output or '')
    wait = re.search(r'WaitTime:\s*(\d+)', output or '')
    reason = ''
    if 'Error: ' in (output or ''):
        reason = output.split('Error: ', 1)[1].strip().splitlines()[0]
    elif 'Status: timeout' in (output or ''):
        reason = 'activity did not report a launch state within the framework window'
    elif 'Status: ok' not in (output or ''):
        reason = 'no launch status reported'
    if 'Status: ok' in (output or '') and total:
        return {'state': 'ok', 'total_ms': int(total.group(1)),
                'wait_ms': int(wait.group(1)) if wait else None, 'reason': ''}
    if 'Status: ok' in (output or ''):
        return {'state': 'incomplete', 'total_ms': None,
                'wait_ms': int(wait.group(1)) if wait else None, 'reason': reason}
    if 'Status: timeout' in (output or '') or 'LaunchState: UNKNOWN' in (output or ''):
        return {'state': 'timeout', 'total_ms': None,
                'wait_ms': int(wait.group(1)) if wait else None, 'reason': reason}
    return {'state': 'error', 'total_ms': None,
            'wait_ms': int(wait.group(1)) if wait else None, 'reason': reason}


def crashed(logs):
    markers = ('FATAL EXCEPTION', 'Fatal signal', '[ERROR:flutter')
    return next((marker for marker in markers if marker in (logs or '')), None)


def install_apk(apk):
    path = Path(apk)
    if not path.exists():
        raise SystemExit(f'APK not found: {apk} (glob did not match; check the build step)')
    adb('install', '-r', str(path), timeout=180)


def force_stop():
    adb('shell', 'am', 'force-stop', PACKAGE)


def launch_once(prefix, attempt):
    """One instrumented `am start -W`; returns (parsed, output, crash_marker)."""
    force_stop()
    adb('logcat', '-c')
    try:
        output = adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity')
    except subprocess.TimeoutExpired:
        output = 'Status: timeout\nadb did not return within the transport timeout\n'
    (OUT / f'{prefix}-{attempt}.txt').write_text(output)
    logs = adb('logcat', '-d', '-v', 'threadtime')
    (OUT / f'{prefix}-logcat-{attempt}.txt').write_text(logs)
    return parse_launch(output), output, crashed(logs)


def launch(prefix, attempts=LAUNCH_ATTEMPTS):
    """Retry a launch that the framework timed out; never retry a real crash.

    Returns (result, attempts_used). result is None when every attempt failed.
    """
    failures = []
    for attempt in range(1, attempts + 1):
        result, _output, crash = launch_once(prefix, attempt)
        if crash:
            raise AssertionError(f'Runtime crash/error during launch: {crash}; see {prefix}-logcat-{attempt}.txt')
        if result['state'] == 'ok':
            # Leave evidence even when a later attempt recovered, so a flaky
            # emulator stays visible in the artifact instead of silently passing.
            if failures:
                (OUT / f'{prefix}-failures.txt').write_text('\n'.join(failures) + '\n')
            return result, attempt
        failures.append(f'attempt {attempt}: {result["state"]} '
                        f'(WaitTime {result["wait_ms"]}ms) {result["reason"]}'.strip())
        time.sleep(2 * attempt)
    (OUT / f'{prefix}-failures.txt').write_text('\n'.join(failures) + '\n')
    return None, attempts


def settle(seconds=8):
    """Let a timed-out launch finish in the background before the next attempt.

    Returns as soon as the activity is on screen; the deadline only bounds the
    wait for a launch that never lands.
    """
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        activities = adb('shell', 'dumpsys', 'activity', 'activities')
        if f'{PACKAGE}/.MainActivity' in activities:
            return
        time.sleep(1)


def run_start(index):
    prefix = f'launch-{index}'
    result, attempts = launch(prefix)
    if result is None:
        raise AssertionError(f'am start never reported Status: ok in {attempts} attempts; '
                             f'see {prefix}-*.txt and {prefix}-logcat-*.txt')
    deadline = time.monotonic() + 30
    logs = ''
    while time.monotonic() < deadline:
        logs = adb('logcat', '-d', '-v', 'threadtime')
        marker = crashed(logs)
        if marker:
            raise AssertionError(f'Runtime crash/error: {marker}; see logcat')
        ready = re.search(r'StickersStartup.*home_ready_ms=(\d+)', logs)
        if ready:
            (OUT / f'logcat-{index}.txt').write_text(logs)
            with (OUT / f'home-{index}.png').open('wb') as shot:
                subprocess.run(['adb', 'exec-out', 'screencap', '-p'], check=True,
                               stdout=shot, timeout=15)
            data_ready = re.search(r'Startup data ready: (\d+)ms', logs)
            first_frame = re.search(r'Startup first frame: (\d+)ms', logs)
            return {'iteration': index,
                    'dart_data_ready_ms': int(data_ready[1]) if data_ready else None,
                    'dart_first_frame_ms': int(first_frame[1]) if first_frame else None,
                    'home_ready_ms': int(ready[1]),
                    'am_total_ms': result['total_ms'],
                    'launch_attempts': attempts}
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
    marker = crashed(logs)
    assert not marker, f'Font page runtime error: {marker}'
    print('::notice title=Lazy fonts smoke::First-use font manager rendered Lobster after native registration')


def measure_baseline(samples=BASELINE_SAMPLES):
    """Warm-up launch (discarded) plus `samples` cold-process launches.

    Returns None when the baseline cannot be measured at all; the caller turns
    that into a warning because the baseline is a historical comparison, not the
    artifact under test.
    """
    warmup, warmup_attempts = launch('baseline-warmup', attempts=BASELINE_WARMUP_ATTEMPTS)
    if warmup is None:
        return None
    settle()
    times, attempts, skipped = [], [], 0
    for index in range(samples):
        result, used = launch(f'baseline-launch-{index}')
        attempts.append(used)
        if result is None:
            skipped += 1
            settle()
            continue
        times.append(result['total_ms'])
        time.sleep(1)
    (OUT / 'baseline-logcat.txt').write_text(adb('logcat', '-d', '-v', 'threadtime'))
    # first_install stays the first measured launch, restarts the ones after it.
    if len(times) < 2:
        return {'installed': True,
                'skipped_reason': f'only {len(times)} of {samples} baseline launches were measurable'}
    return {'first_install_am_total_ms': times[0], 'restart_am_total_ms': times[1:],
            'restart_median_am_total_ms': statistics.median(times[1:]),
            'warmup_am_total_ms': warmup['total_ms'], 'warmup_launch_attempts': warmup_attempts,
            'launch_attempts': attempts, 'timed_out_launches': skipped,
            'samples': len(times), 'installed': True}


def baseline_starts(apk):
    """Install and measure the old APK; never let it fail the release smoke."""
    if not Path(apk).exists():
        # The glob can miss if the historical release asset ever moves; the
        # baseline is a comparison, so skip it instead of aborting the release.
        print(f'::warning title=Debug baseline::no APK matched {apk}; comparison skipped')
        return {'installed': False, 'skipped_reason': f'baseline APK not found: {apk}'}
    try:
        install_apk(apk)
        baseline = measure_baseline()
    except AssertionError as error:
        # A crash in the historical debug build is evidence, not a reason to
        # block the release APK that is actually being shipped.
        print(f'::warning title=Debug baseline::crashed and was not measured: {error}')
        return {'installed': True, 'skipped_reason': f'runtime crash: {error}'}
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as error:
        print(f'::warning title=Debug baseline::could not be installed/measured: {error}')
        return {'installed': False, 'skipped_reason': str(error)}
    if baseline is None:
        print('::warning title=Debug baseline::am start never reported Status: ok; '
              'comparison skipped (see baseline-*.txt and baseline-logcat-*.txt)')
        return {'installed': True, 'skipped_reason': 'launch timeout on every attempt'}
    return baseline


def comparison_message(baseline, summary):
    attempts = baseline.get('launch_attempts') or []
    retried = sum(1 for used in attempts if used > 1)
    timed_out = baseline.get('timed_out_launches') or 0
    warmup_attempts = baseline.get('warmup_launch_attempts', 1)
    notes = []
    if warmup_attempts > 1:
        notes.append(f'warm-up took {warmup_attempts} attempts')
    if retried:
        notes.append(f'{retried} measured launch(es) retried')
    if timed_out:
        notes.append(f'{timed_out} unmeasurable')
    note = f" ({'; '.join(notes)}; debug/JIT on a loaded emulator)" if notes else ''
    upgrade = '; in-place upgrade succeeded' if baseline.get('installed') else ''
    return (f"Same-emulator am start median: debug baseline "
            f"{baseline['restart_median_am_total_ms']}ms -> release "
            f"{summary['restart_median_am_total_ms']}ms{note}{upgrade}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk')
    parser.add_argument('--baseline', help='Optional old APK; tests in-place update with the same signing key')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    try:
        baseline = baseline_starts(args.baseline) if args.baseline else None
        install_apk(args.apk)
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
        if baseline and 'restart_median_am_total_ms' in baseline:
            comparison = comparison_message(baseline, summary)
            print(f'::notice title=Startup comparison::{comparison}')
            message += '\n\n' + comparison
        elif baseline:
            skipped = (f"Debug baseline not measurable ({baseline.get('skipped_reason', 'unknown')}); "
                       f"release numbers above stand alone and the release APK was still "
                       f"installed over the previous one")
            print(f'::warning title=Startup comparison::{skipped}')
            message += '\n\n' + skipped
        check_lazy_fonts()
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as f:
                f.write(f'\n### Release startup smoke\n\n{message}\n')
    finally:
        (OUT / 'final-logcat.txt').write_text(adb('logcat', '-d', '-v', 'threadtime'))
        (OUT / 'device.txt').write_text(adb('shell', 'getprop'))


if __name__ == '__main__':
    main()
