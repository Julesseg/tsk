import importlib.util
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


plan = load('plan-ui-tests')
products = load('ui-build-products')
dispatch = load('dispatch-ui-tests')
boundaries = load('relay-ui-test-boundaries')
summary = load('summarize-ui-execution')


class ExecutionTests(unittest.TestCase):
    def test_plans_keep_four_full_workers_and_skip_unused_smoke_fixtures(self):
        full = plan.plan('full')
        self.assertEqual(len(full['matrix']['include']), 4)
        for worker in full['matrix']['include']:
            self.assertEqual(worker['native_keyboard'], worker['partition'] == 'workspace')
            self.assertEqual(worker['server'], worker['partition'] == 'workspace')
            self.assertEqual(worker['peer'], worker['partition'] == 'workspace')
        smoke = plan.plan('smoke')
        self.assertEqual(len(smoke['matrix']['include']), 2)
        self.assertFalse(any(worker['native_keyboard'] for worker in smoke['matrix']['include']))
        self.assertEqual([worker['server'] for worker in smoke['matrix']['include']], [True, False])
        self.assertEqual(plan.plan('diagnostic')['families'], ['iPhone'])
        self.assertFalse(plan.plan('text')['server'])
        plan.validate_source('frozen', 'frozen')
        plan.validate_source(None, 'current')
        with self.assertRaisesRegex(ValueError, 'Branch moved'):
            plan.validate_source('frozen', 'different')

    def test_products_reject_source_toolchain_and_runtime_mismatches(self):
        identity = dict(source='sha', tree='tree', sdk='27.0', runtimes=['27.0-build'])
        products.verify_identity(identity, dict(identity))
        for key in identity:
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, key):
                products.verify_identity(identity, dict(identity, **{key: 'different'}))

    def test_product_transfer_preserves_executables_links_and_detects_corruption(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / '.build/ui/Build/Products/Debug-iphonesimulator/Tsk.app'
            app.mkdir(parents=True)
            (app / 'Tsk').write_bytes(b'executable')
            (app / 'Tsk').chmod(0o755)
            (app / 'Current').symlink_to('Tsk')
            (root / '.build/ui-tools').mkdir()
            archive = root / 'transfer/ui-products.tar.gz'
            def run(command):
                with patch.object(sys, 'argv', ['products', command, '--root', str(root), '--archive', str(archive)]), patch.object(products, 'identity', return_value=dict(source='fixed')), patch.object(products.subprocess, 'run'):
                    products.main()
            run('pack')
            shutil.rmtree(root / '.build/ui')
            shutil.rmtree(root / '.build/ui-tools')
            run('unpack')
            self.assertEqual((app / 'Current').read_bytes(), b'executable')
            self.assertTrue((app / 'Tsk').stat().st_mode & 0o111)
            with archive.open('ab') as output:
                output.write(b'corrupt')
            with self.assertRaisesRegex(ValueError, 'checksum'):
                run('unpack')

    def test_dispatch_deduplicates_only_matching_source_branch_and_coverage(self):
        run = dict(id=1, head_sha='fixed', head_branch='branch', event='workflow_dispatch', display_title='CI · full · verification', status='in_progress', conclusion=None, html_url='https://example.test/run')
        self.assertEqual(dispatch.matching_run([run], 'fixed', 'branch', 'full'), run)
        for sha, branch, suite in [('other', 'branch', 'full'), ('fixed', 'other', 'full'), ('fixed', 'branch', 'smoke')]:
            self.assertIsNone(dispatch.matching_run([run], sha, branch, suite))
        complete = dict(run, status='completed', conclusion='success')
        self.assertIsNone(dispatch.matching_run([complete], 'fixed', 'branch', 'full'))
        self.assertIsNone(dispatch.matching_run([complete], 'fixed', 'branch', 'full', dict(runtime='target'), lambda run: dict(runtime='other')))
        self.assertEqual(dispatch.matching_run([complete], 'fixed', 'branch', 'full', dict(runtime='target'), lambda run: dict(runtime='target')), complete)
        self.assertIsNone(dispatch.matching_run([dict(complete, conclusion='failure')], 'fixed', 'branch', 'full', {}, lambda run: {}))
        with self.assertRaisesRegex(ValueError, 'awaiting'):
            dispatch.matching_run([run], 'fixed', 'branch', 'full', dict(runtime='target'), lambda run: None)
        with self.assertRaisesRegex(ValueError, 'different'):
            dispatch.matching_run([run], 'fixed', 'branch', 'full', dict(runtime='target'), lambda run: dict(runtime='other'))

    def test_device_monitor_stops_only_for_positive_owned_device_shutdown(self):
        for state, expected in [('Booted', False), ('Shutdown', True), ('missing', False)]:
            with self.subTest(state=state):
                now = [0]
                events = []
                data = dict(devices=dict(runtime=[] if state == 'missing' else [dict(udid='owned', state=state)]))
                command = [sys.executable, '-c', 'import sys;sys.stdout.write(' + repr(json.dumps(data)) + ')']
                monitor = boundaries.DeviceMonitor('owned', lambda *args, **kwargs: events.append((args, kwargs)), command, clock=lambda: now[0])
                try:
                    now[0] = 15
                    self.assertFalse(monitor.poll())
                    monitor.process.wait(timeout=3)
                    self.assertEqual(monitor.poll(), expected)
                    self.assertEqual(bool(events), expected)
                finally:
                    monitor.close()

    def test_stalled_monitor_is_killed_and_does_not_assert_device_loss(self):
        now = [0]
        monitor = boundaries.DeviceMonitor('owned', lambda *args, **kwargs: None, [sys.executable, '-c', 'import time;time.sleep(10)'], clock=lambda: now[0])
        try:
            now[0] = 15
            self.assertFalse(monitor.poll())
            child = monitor.process
            now[0] = 18
            self.assertFalse(monitor.poll())
            self.assertIsNotNone(child.returncode)
        finally:
            monitor.close()

    def test_method_boundaries_retain_initial_failure_and_later_independent_results(self):
        with tempfile.TemporaryDirectory() as directory:
            capture = boundaries.BoundaryCapture('owned', directory, ROOT / 'scripts')
            with contextlib.redirect_stdout(io.StringIO()):
                capture.line(b"Test Case '-[TskUITests.TaskRowEditingUITests testEdit]' failed (5.000 seconds).")
                capture.line(b"Test Case '-[TskUITests.TaskRowEditingUITests testOther]' passed (2.000 seconds).")
            self.assertEqual([event['outcome'] for event in capture.events if event['event'] == 'method-end'], ['failed', 'passed'])
            self.assertEqual(sum(event['event'] == 'first-test-failure' for event in capture.events), 1)

    def test_device_archive_builds_only_the_device_rust_architecture(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            shutil.copy(ROOT / 'scripts/build-native.sh', root / 'scripts')
            target = root / 'target/aarch64-apple-ios/release'
            target.mkdir(parents=True)
            (target / 'libtsk_taskchampion.a').write_bytes(b'device')
            tool = root / 'tool'
            tool.write_text('#!/bin/sh\nprintf "%s %s\\n" "$0" "$*" >> "$BUILD_COMMANDS"\n')
            tool.chmod(0o755)
            for name in ('rustup', 'cargo', 'lipo'):
                (root / name).symlink_to(tool)
            log = root / 'calls'
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'], CARGO_TARGET_DIR=str(root / 'target'), BUILD_COMMANDS=str(log))
            subprocess.run(['/bin/bash', str(root / 'scripts/build-native.sh'), 'device'], env=environment, check=True)
            calls = log.read_text()
            self.assertIn('--target aarch64-apple-ios', calls)
            self.assertNotIn('aarch64-apple-ios-sim', calls)
            self.assertNotIn('x86_64', calls)
            self.assertNotIn('/lipo', calls)
            self.assertEqual((root / 'Native/Artifacts/iphoneos/libtsk_taskchampion.a').read_bytes(), b'device')

    def test_result_summary_uses_completed_method_durations(self):
        methods = summary.test_methods([dict(name='suite', children=[dict(nodeType='Test Case', name='edit', nodeIdentifier='Row/edit', durationInSeconds=42, result='Failed')])])
        self.assertEqual(methods, [dict(name='Row/edit', seconds=42, result='Failed')])

    def test_failure_timing_spans_share_and_main_without_hiding_the_first_failure(self):
        share = dict(finishedUTC='2026-10-31T00:02:00+00:00', events=[dict(event='xcodebuild-start', receivedUTC='2026-10-31T00:00:00+00:00'), dict(event='first-test-failure', receivedUTC='2026-10-31T00:01:00+00:00', method='Share/edit')])
        main = dict(finishedUTC='2026-10-31T00:10:00+00:00', events=[dict(event='xcodebuild-start', receivedUTC='2026-10-31T00:03:00+00:00'), dict(event='first-test-failure', receivedUTC='2026-10-31T00:05:00+00:00', method='Row/edit')])
        timing = summary.failure_timing([main, share])
        self.assertEqual(timing['method'], 'Share/edit')
        self.assertEqual(timing['seconds_to_failure'], 60)
        self.assertEqual(timing['seconds_after_failure'], 540)
        self.assertIsNone(summary.failure_timing([]))


if __name__ == '__main__':
    unittest.main()
