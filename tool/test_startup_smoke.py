"""Unit tests for the launch retry/baseline tolerance in startup_smoke.py.

The CI smoke runs against a real emulator, but the failure it must survive is
pure logic: `am start -W` answering "Status: timeout" for the 171 MiB JIT debug
baseline on a loaded runner. These tests replay that transcript against stubs.
"""
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import startup_smoke as smoke

# Transcribed from the failing job: the framework gave up after ~12s while the
# debug baseline was still doing its first JIT launch.
TIMEOUT_LAUNCH = """Starting: Intent { cmp=de.loicezt.stickers/.MainActivity }
Status: timeout
LaunchState: UNKNOWN (-1)
Activity: de.loicezt.stickers/.MainActivity
WaitTime: 12265
Complete
"""

OK_LAUNCH = """Starting: Intent { cmp=de.loicezt.stickers/.MainActivity }
Status: ok
Activity: de.loicezt.stickers/.MainActivity
WaitTime: 2320
TotalTime: 2310
LaunchState: RESUMED
Complete
"""

NO_TOTAL_LAUNCH = """Starting: Intent { cmp=de.loicezt.stickers/.MainActivity }
Status: ok
WaitTime: 2320
Complete
"""

CRASH_LOGS = 'E AndroidRuntime: FATAL EXCEPTION: main\n'
CLEAN_LOGS = 'I StickersStartup: home_ready_ms=1800\n'
RELEASE_LOGS = ('Startup data ready: 610ms\n'
                'Startup first frame: 640ms\n'
                'I StickersStartup: home_ready_ms=1900\n')
WINDOW_XML = ('<?xml version="1.0"?>\n<hierarchy rotation="0">\n'
              '  <node text="Settings" content-desc="" bounds="[0,0][100,50]" />\n'
              '  <node text="Fonts manager" content-desc="" bounds="[0,60][200,110]" />\n'
              '  <node text="Lobster" content-desc="" bounds="[0,120][200,170]" />\n'
              '</hierarchy>\n')


class FullAdb:
    """Routes every adb subcommand main() uses, for end-to-end replays."""

    def __init__(self, starts, logs=CLEAN_LOGS, window=WINDOW_XML):
        self.starts = list(starts)
        self.logs = logs
        self.window = window
        self.installed = []
        self.taps = []

    def __call__(self, *args, timeout=None):
        if args[0] == 'install':
            self.installed.append(args[2])
            return 'Success\n'
        if args[0] == 'logcat':
            return '' if '-c' in args else self.logs
        if args[:4] == ('shell', 'dumpsys', 'activity', 'activities'):
            return f'ResumedActivity: ActivityRecord{{ {smoke.PACKAGE}/.MainActivity }}\n'
        if args[:3] == ('shell', 'am', 'start'):
            if not self.starts:
                raise AssertionError('more launches than scripted')
            return self.starts.pop(0)
        if args[:3] == ('shell', 'uiautomator', 'dump'):
            return ''
        if args[:2] == ('shell', 'cat'):
            return self.window
        if args[:3] == ('shell', 'input', 'tap'):
            self.taps.append(args[3:5])
            return ''
        return ''


class FakeAdb:
    """Replays scripted `am start -W` answers; records every adb invocation."""

    def __init__(self, launches, logs=CLEAN_LOGS):
        self.launches = list(launches)
        self.logs = logs
        self.calls = []

    def __call__(self, *args, timeout=None):
        self.calls.append(args)
        # Real code calls `adb logcat -c` (clear) then `adb logcat -d ...` (dump).
        if args[0] == 'logcat' and '-c' not in args:
            return self.logs
        if args[:4] == ('shell', 'dumpsys', 'activity', 'activities'):
            # settle() polls this; report the activity as on screen so the
            # post-timeout wait returns instead of spinning to its deadline.
            return f'ResumedActivity: ActivityRecord{{ {smoke.PACKAGE}/.MainActivity }}\n'
        if args[:3] == ('shell', 'am', 'start'):
            if not self.launches:
                raise AssertionError('more launches than scripted')
            answer = self.launches.pop(0)
            if isinstance(answer, Exception):
                raise answer
            return answer
        return ''

    @property
    def starts(self):
        return [call for call in self.calls if call[:3] == ('shell', 'am', 'start')]


class StartupSmokeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.out = Path(self.tmp.name)
        self.addCleanup(setattr, smoke, 'OUT', smoke.OUT)
        smoke.OUT = self.out
        self.addCleanup(setattr, smoke.time, 'sleep', smoke.time.sleep)
        smoke.time.sleep = lambda seconds: None

    def use(self, launches, logs=CLEAN_LOGS):
        fake = FakeAdb(launches, logs)
        self.addCleanup(setattr, smoke, 'adb', smoke.adb)
        smoke.adb = fake
        return fake

    def test_parses_the_real_ci_transcript(self):
        self.assertEqual(smoke.parse_launch(TIMEOUT_LAUNCH)['state'], 'timeout')
        self.assertEqual(smoke.parse_launch(TIMEOUT_LAUNCH)['wait_ms'], 12265)
        ok = smoke.parse_launch(OK_LAUNCH)
        self.assertEqual((ok['state'], ok['total_ms'], ok['wait_ms']), ('ok', 2310, 2320))
        self.assertEqual(smoke.parse_launch(NO_TOTAL_LAUNCH)['state'], 'incomplete')
        self.assertEqual(smoke.parse_launch('Error: Activity not started')['state'], 'error')

    def test_launch_retries_a_timeout_and_reports_attempts(self):
        fake = self.use([TIMEOUT_LAUNCH, OK_LAUNCH])
        result, attempts = smoke.launch('launch-0')
        self.assertEqual((result['total_ms'], attempts), (2310, 2))
        self.assertEqual(len(fake.starts), 2)
        self.assertEqual((self.out / 'launch-0-1.txt').read_text(), TIMEOUT_LAUNCH)
        self.assertEqual((self.out / 'launch-0-2.txt').read_text(), OK_LAUNCH)
        self.assertIn('attempt 1: timeout', (self.out / 'launch-0-failures.txt').read_text())

    def test_launch_never_retries_a_crash(self):
        fake = self.use([OK_LAUNCH, OK_LAUNCH], logs=CRASH_LOGS)
        with self.assertRaises(AssertionError) as caught:
            smoke.launch('launch-0')
        self.assertIn('FATAL EXCEPTION', str(caught.exception))
        self.assertEqual(len(fake.starts), 1)

    def test_launch_exhausts_attempts(self):
        fake = self.use([TIMEOUT_LAUNCH] * smoke.LAUNCH_ATTEMPTS)
        result, attempts = smoke.launch('launch-0')
        self.assertIsNone(result)
        self.assertEqual((attempts, len(fake.starts)), (smoke.LAUNCH_ATTEMPTS, smoke.LAUNCH_ATTEMPTS))

    def test_run_start_records_attempts_and_metrics(self):
        fake = self.use([TIMEOUT_LAUNCH, OK_LAUNCH],
                        logs='Startup data ready: 600ms\nStartup first frame: 640ms\n'
                             'I StickersStartup: home_ready_ms=1900\n')
        fake_screencap = lambda *args, **kwargs: None
        self.addCleanup(setattr, smoke.subprocess, 'run', smoke.subprocess.run)
        smoke.subprocess.run = fake_screencap
        result = smoke.run_start(0)
        self.assertEqual(result['launch_attempts'], 2)
        self.assertEqual(result['am_total_ms'], 2310)
        self.assertEqual(result['home_ready_ms'], 1900)
        self.assertEqual(result['dart_data_ready_ms'], 600)
        self.assertEqual(result['dart_first_frame_ms'], 640)

    def test_baseline_warmup_recovers_from_the_ci_timeout(self):
        # Warm-up times out once, then succeeds, and every measured launch
        # succeeds: the comparison survives the run that used to abort the job.
        ok = [OK_LAUNCH] * (smoke.BASELINE_SAMPLES + 1)  # +1 for the warm-up retry
        self.use([TIMEOUT_LAUNCH] + ok)
        baseline = smoke.measure_baseline()
        self.assertEqual(baseline['warmup_launch_attempts'], 2)
        self.assertEqual(baseline['samples'], smoke.BASELINE_SAMPLES)
        self.assertEqual(baseline['timed_out_launches'], 0)
        self.assertEqual(baseline['launch_attempts'], [1] * smoke.BASELINE_SAMPLES)
        self.assertEqual(baseline['first_install_am_total_ms'], 2310)
        self.assertEqual(baseline['restart_median_am_total_ms'], 2310)
        self.assertEqual(len(baseline['restart_am_total_ms']), smoke.BASELINE_SAMPLES - 1)
        self.assertTrue(baseline['installed'])

    def test_baseline_is_skipped_when_no_launch_settles(self):
        self.use([TIMEOUT_LAUNCH] * (smoke.BASELINE_WARMUP_ATTEMPTS + smoke.BASELINE_SAMPLES))
        self.assertIsNone(smoke.measure_baseline())

    def test_baseline_reports_partially_measurable_runs(self):
        # Warm-up ok; first measured launch times out on every retry (skipped),
        # the remaining five succeed -> five samples, one unmeasurable.
        launches = [OK_LAUNCH]  # warm-up
        launches += [TIMEOUT_LAUNCH] * smoke.LAUNCH_ATTEMPTS  # measured launch 0
        launches += [OK_LAUNCH] * (smoke.BASELINE_SAMPLES - 1)  # measured 1..5
        self.use(launches)
        baseline = smoke.measure_baseline()
        self.assertEqual(baseline['samples'], smoke.BASELINE_SAMPLES - 1)
        self.assertEqual(baseline['timed_out_launches'], 1)
        self.assertEqual(baseline['launch_attempts'][0], smoke.LAUNCH_ATTEMPTS)
        self.assertTrue(baseline['installed'])

    def test_baseline_skipped_when_too_few_launches_measurable(self):
        # Warm-up ok, but only one measured launch succeeds -> not comparable.
        launches = [OK_LAUNCH]  # warm-up
        launches += [OK_LAUNCH]  # measured launch 0 succeeds
        launches += [TIMEOUT_LAUNCH] * smoke.LAUNCH_ATTEMPTS * (smoke.BASELINE_SAMPLES - 1)
        self.use(launches)
        baseline = smoke.measure_baseline()
        self.assertIn('skipped_reason', baseline)
        self.assertNotIn('restart_median_am_total_ms', baseline)
        self.assertIn('only 1 of', baseline['skipped_reason'])

    def test_baseline_starts_downgrades_an_unmeasurable_baseline_to_a_warning(self):
        self.use([TIMEOUT_LAUNCH] * (smoke.BASELINE_WARMUP_ATTEMPTS + smoke.BASELINE_SAMPLES))
        apk = self.out / 'stickers-1.5.9-27-debug.apk'
        apk.write_bytes(b'apk')
        with redirect_stdout(io.StringIO()) as printed:
            baseline = smoke.baseline_starts(str(apk))
        self.assertEqual(baseline['skipped_reason'], 'launch timeout on every attempt')
        self.assertNotIn('restart_median_am_total_ms', baseline)
        self.assertIn('::warning title=Debug baseline::', printed.getvalue())

    def test_baseline_starts_survives_a_crashing_baseline(self):
        self.use([OK_LAUNCH], logs=CRASH_LOGS)
        apk = self.out / 'stickers-1.5.9-27-debug.apk'
        apk.write_bytes(b'apk')
        with redirect_stdout(io.StringIO()) as printed:
            baseline = smoke.baseline_starts(str(apk))
        self.assertIn('runtime crash', baseline['skipped_reason'])
        self.assertIn('::warning title=Debug baseline::', printed.getvalue())

    def test_install_rejects_a_glob_that_matched_nothing(self):
        self.use([])
        with self.assertRaises(SystemExit):
            smoke.install_apk('apks/*-x86_64-release.apk')

    def test_baseline_glob_miss_warns_instead_of_aborting(self):
        # The release APK must hard-fail on a glob miss, but the *optional*
        # baseline must not: it degrades to a warning so publishing continues.
        self.use([])
        with redirect_stdout(io.StringIO()) as printed:
            baseline = smoke.baseline_starts('baseline/*-debug.apk')
        self.assertFalse(baseline['installed'])
        self.assertIn('not found', baseline['skipped_reason'])
        self.assertIn('::warning title=Debug baseline::', printed.getvalue())

    def test_comparison_message_discloses_baseline_retries(self):
        baseline = {'restart_median_am_total_ms': 7108, 'launch_attempts': [2, 1, 1, 1, 1, 1],
                    'timed_out_launches': 1, 'warmup_launch_attempts': 2, 'installed': True}
        message = smoke.comparison_message(baseline, {'restart_median_am_total_ms': 3074})
        self.assertIn('7108ms -> release 3074ms', message)
        self.assertIn('warm-up took 2 attempts', message)
        self.assertIn('1 measured launch(es) retried', message)
        self.assertIn('1 unmeasurable', message)
        self.assertIn('in-place upgrade succeeded', message)

    def test_comparison_message_stays_clean_without_retries(self):
        baseline = {'restart_median_am_total_ms': 7108, 'launch_attempts': [1] * 6,
                    'timed_out_launches': 0, 'warmup_launch_attempts': 1, 'installed': True}
        message = smoke.comparison_message(baseline, {'restart_median_am_total_ms': 3074})
        self.assertNotIn('retried', message)
        self.assertNotIn('warm-up', message)
        self.assertIn('in-place upgrade succeeded', message)

    def run_main(self, fake):
        """Wire stubs + real APK files, run main(), return (stdout, paths)."""
        def fake_run(cmd, check=False, stdout=None, timeout=None):
            if stdout is not None:
                stdout.write(b'png')

            class Result:
                returncode = 0
            return Result()

        self.addCleanup(setattr, smoke, 'adb', smoke.adb)
        smoke.adb = fake
        self.addCleanup(setattr, smoke.subprocess, 'run', smoke.subprocess.run)
        smoke.subprocess.run = fake_run

        baseline_apk = self.out / 'stickers-1.5.9-27-debug.apk'
        baseline_apk.write_bytes(b'apk')
        release_apk = self.out / 'stickers-1.6.0-28-x86_64-release.apk'
        release_apk.write_bytes(b'apk')
        summary_file = self.out / 'step_summary.md'
        os.environ['GITHUB_STEP_SUMMARY'] = str(summary_file)
        self.addCleanup(os.environ.pop, 'GITHUB_STEP_SUMMARY', None)
        self.addCleanup(setattr, sys, 'argv', sys.argv)
        sys.argv = ['startup_smoke.py', str(release_apk), '--baseline', str(baseline_apk)]

        with redirect_stdout(io.StringIO()) as printed:
            smoke.main()
        return printed.getvalue(), baseline_apk, release_apk, summary_file

    def test_main_recovers_from_the_exact_ci_baseline_timeout(self):
        # End-to-end replay of the failing job: the debug baseline's first
        # launch (warm-up) times out exactly as CI showed, then recovers. The
        # release must still be installed over it, measured, and published to
        # startup.json with the comparison and an honest warm-up disclosure.
        ok_count = 1 + smoke.BASELINE_SAMPLES + 6  # warm-up retry + baseline + release
        fake = FullAdb([TIMEOUT_LAUNCH] + [OK_LAUNCH] * ok_count, logs=RELEASE_LOGS)
        out, baseline_apk, release_apk, summary_file = self.run_main(fake)

        # Both APKs installed, baseline first then release over it (in-place).
        self.assertEqual(fake.installed, [str(baseline_apk), str(release_apk)])
        self.assertEqual(fake.starts, [])  # every scripted launch consumed
        # The baseline recovered -> no blocking warning, and the run completed.
        self.assertNotIn('::warning', out)
        self.assertNotIn('Traceback', out)
        self.assertIn('::notice title=Startup smoke::', out)
        self.assertIn('::notice title=Startup comparison::', out)
        self.assertIn('warm-up took 2 attempts', out)  # honest flake disclosure
        self.assertIn('::notice title=Lazy fonts smoke::', out)
        # Fonts navigation actually tapped Settings then Fonts manager.
        self.assertEqual(fake.taps, [('50', '25'), ('100', '85')])

        summary = json.loads((self.out / 'startup.json').read_text())
        baseline = summary['baseline']
        self.assertEqual(baseline['samples'], smoke.BASELINE_SAMPLES)
        self.assertEqual(baseline['warmup_launch_attempts'], 2)
        self.assertEqual(baseline['timed_out_launches'], 0)
        self.assertTrue(baseline['installed'])
        self.assertEqual(summary['first_launch']['home_ready_ms'], 1900)
        self.assertEqual(summary['first_launch']['launch_attempts'], 1)
        self.assertIn('Release startup smoke', summary_file.read_text())

    def test_main_completes_when_the_baseline_never_launches(self):
        # The property that unblocks `publish`: an unmeasurable baseline warns
        # but must NOT abort. The release is still installed over it, measured,
        # navigated to fonts, and written to startup.json.
        fake = FullAdb([TIMEOUT_LAUNCH] * smoke.BASELINE_WARMUP_ATTEMPTS + [OK_LAUNCH] * 6,
                       logs=RELEASE_LOGS)
        out, baseline_apk, release_apk, summary_file = self.run_main(fake)

        self.assertEqual(fake.installed, [str(baseline_apk), str(release_apk)])
        self.assertEqual(fake.starts, [])
        self.assertNotIn('Traceback', out)
        self.assertIn('::warning title=Debug baseline::', out)
        self.assertIn('::warning title=Startup comparison::', out)
        self.assertIn('Debug baseline not measurable', out)
        # The release smoke itself still ran to completion.
        self.assertIn('::notice title=Startup smoke::', out)
        self.assertIn('::notice title=Lazy fonts smoke::', out)

        summary = json.loads((self.out / 'startup.json').read_text())
        baseline = summary['baseline']
        self.assertIn('skipped_reason', baseline)
        self.assertNotIn('restart_median_am_total_ms', baseline)
        self.assertTrue(baseline['installed'])  # still proved the in-place upgrade
        self.assertEqual(summary['first_launch']['home_ready_ms'], 1900)
        self.assertIn('Release startup smoke', summary_file.read_text())


if __name__ == '__main__':
    unittest.main()
