import asyncio
import contextlib
import io
import sys
import json
import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock

path = pathlib.Path(__file__).with_name('with-native-keyboard-hid.py')
spec = importlib.util.spec_from_file_location('hid_owner', path)
owner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(owner)

CASE = '-only-testing:TskUITests/TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys'
COMMAND = ['xcodebuild', 'test-without-building', '-destination', 'platform=iOS Simulator,id=343D52B5-399D-4E45-A357-BF8F8446452B', '-parallel-testing-enabled', 'NO', CASE, '-resultBundlePath', 'Result.xcresult']


class CommandTests(unittest.TestCase):
    def test_only_original_independent_case_and_owned_destination_are_accepted(self):
        owner.validate_command(COMMAND, '343D52B5-399D-4E45-A357-BF8F8446452B')
        for command in [COMMAND + ['-only-testing:TskUITests/AnotherTest'], COMMAND + ['-skip-testing:TskUITests/TaskAnnotationUITests'], ['echo', 'test'], [x.replace('343D52B5', '443D52B5') for x in COMMAND]]:
            with self.subTest(command=command), self.assertRaises(ValueError):
                owner.validate_command(command, '343D52B5-399D-4E45-A357-BF8F8446452B')


class FakeProcess:
    def __init__(self, kind, pid):
        self.kind, self.pid, self.returncode = kind, pid, None


class FakeHost:
    def __init__(self, evidence, *, fail=None, code=0, marked=True, complete=True, passed=True):
        self.evidence, self.fail, self.code = evidence, fail, code
        self.marked, self.complete, self.passed = marked, complete, passed
        self.events, self.environments = [], []

    async def start(self, command, log, environment=None, pipe=False):
        kind = 'companion' if command[0].endswith('idb_companion') else 'relay' if 'relay-native-keyboard-hid.py' in command[1] else 'tests'
        self.events.append('start:' + kind)
        self.environments.append(environment)
        return FakeProcess(kind, 100 + len(self.events))

    async def wait_socket(self, socket, process):
        self.events.append('socket')
        if self.fail == 'socket':
            raise RuntimeError('companion unavailable')

    async def wait_armed(self, path, relay, token, companion_pid):
        self.events.append('armed')
        if self.fail == 'armed':
            raise RuntimeError('relay unavailable')
        return dict(state='waiting', relayToken=token, companionPID=companion_pid, logStartOffset=0)

    async def stream(self, process, live):
        self.events.append('stream')
        if self.marked:
            live.write_bytes(owner.MARKER + b'owned request\n')
        final = dict(state='hid_rpc_completed_native_assertions_required' if self.complete else 'waiting')
        (self.evidence / 'relay-receipt.json').write_text(json.dumps(final))
        if self.fail == 'cancel':
            raise asyncio.CancelledError()
        if self.fail == 'timeout':
            raise TimeoutError('600 seconds elapsed')
        process.returncode = self.code
        return self.code

    async def public_result(self, command):
        self.events.append('public')
        if self.fail == 'public':
            raise RuntimeError('result unavailable')
        return dict(nodeType='Test Case', nodeIdentifier=owner.CASE + '()', result='Passed' if self.passed else 'Failed')

    async def stop(self, process, group=False):
        self.events.append('stop:' + process.kind)
        if self.fail == 'group-cleanup' and process.kind == 'tests':
            raise RuntimeError('Owned process group cleanup remains unconfirmed')
        process.returncode = process.returncode or 0
        return dict(pid=process.pid, status=process.returncode, reaped=True, hardKilled=process.kind == 'relay' and self.fail == 'hard-kill')

    async def recover(self, socket):
        self.events.append('UP-only')
        if self.fail == 'recovery':
            raise RuntimeError('UP unconfirmed')


class OwnershipTests(unittest.IsolatedAsyncioTestCase):
    async def run_case(self, **options):
        with tempfile.TemporaryDirectory() as root:
            evidence = pathlib.Path(root) / 'evidence'
            host = FakeHost(evidence, **options)
            comparison = owner.Comparison('343D52B5-399D-4E45-A357-BF8F8446452B', pathlib.Path(root), evidence, pathlib.Path(root) / 'owned.sock', COMMAND, host=host, token='A2A514F2-FE63-40E1-9A42-B097CB8E9F23')
            status = await comparison.run()
            return status, host, comparison.receipt

    async def test_waiting_precedes_test_start_nonce_forwarding_and_owned_cleanup(self):
        status, host, receipt = await self.run_case()
        self.assertEqual(status, 0)
        self.assertLess(host.events.index('armed'), host.events.index('start:tests'))
        self.assertEqual(host.environments[-1]['TEST_RUNNER_TSK_TEST_HID_RELAY_TOKEN'], 'A2A514F2-FE63-40E1-9A42-B097CB8E9F23')
        self.assertEqual(host.events[-3:], ['stop:tests', 'stop:relay', 'stop:companion'])
        self.assertTrue(receipt['actualOriginalCasePassed'])

    async def test_socket_and_arm_failure_never_launch_test_and_reap_only_started_children(self):
        for fail in ['socket', 'armed']:
            status, host, _ = await self.run_case(fail=fail, marked=False, complete=False)
            self.assertEqual(status, 70)
            self.assertNotIn('start:tests', host.events)
            self.assertEqual(host.events[-1], 'stop:companion')
            self.assertEqual('stop:relay' in host.events, fail == 'armed')
            self.assertNotIn('UP-only', host.events)

    async def test_test_failure_is_preserved_and_rpc_completion_is_not_public_pass(self):
        status, _, _ = await self.run_case(code=65, passed=False)
        self.assertEqual(status, 65)
        status, _, _ = await self.run_case(passed=False)
        self.assertEqual(status, 70)

    async def test_missing_public_result_cannot_turn_zero_exit_and_rpc_into_pass(self):
        status, host, _ = await self.run_case(fail='public')
        self.assertEqual(status, 70)
        self.assertEqual(host.events[-1], 'stop:companion')

    async def test_timeout_cancel_and_hard_kill_recover_up_before_companion_stops(self):
        for fail, expected in [('timeout', 124), ('cancel', 130), ('hard-kill', 70)]:
            status, host, _ = await self.run_case(fail=fail, complete=False)
            self.assertEqual(status, expected)
            self.assertLess(host.events.index('stop:relay'), host.events.index('UP-only'))
            self.assertLess(host.events.index('UP-only'), host.events.index('stop:companion'))

    async def test_unconfirmed_test_group_fails_owner_and_still_stops_other_owned_processes(self):
        status, host, receipt = await self.run_case(fail='group-cleanup')
        self.assertEqual(status, 70)
        self.assertIn('testsCleanupError', receipt)
        self.assertEqual(host.events[-2:], ['stop:relay', 'stop:companion'])

    async def test_unconfirmed_up_recovery_never_reports_success(self):
        status, host, receipt = await self.run_case(fail='recovery', complete=False)
        self.assertEqual(status, 70)
        self.assertIn('upOnlyRecoveryError', receipt)
        self.assertEqual(host.events[-1], 'stop:companion')


class OwnedGroupTests(unittest.IsolatedAsyncioTestCase):
    async def stop_group(self, initially_exited, survives_kill=False):
        class Process:
            pid = 24101

            def __init__(self):
                self.returncode = 0 if initially_exited else None
                self.waits = 0

            async def wait(self):
                self.waits += 1
                self.returncode = 0
                return 0

        process = Process()
        group_alive = True
        signals = []
        clock = 0.0

        def killpg(pgid, number):
            nonlocal group_alive
            self.assertEqual(pgid, 24101)
            if not group_alive:
                raise ProcessLookupError()
            if number:
                signals.append((pgid, number))
            if number == owner.signal.SIGTERM:
                process.returncode = 0
            if number == owner.signal.SIGKILL and not survives_kill:
                group_alive = False

        async def sleep(seconds):
            nonlocal clock
            clock += seconds

        with tempfile.TemporaryDirectory() as root:
            host = owner.Host(path.parent, pathlib.Path(root), pathlib.Path(root))
            with mock.patch.object(owner.os, 'killpg', side_effect=killpg), mock.patch.object(owner.time, 'monotonic', side_effect=lambda: clock), mock.patch.object(owner.asyncio, 'sleep', side_effect=sleep):
                if survives_kill:
                    with self.assertRaisesRegex(RuntimeError, 'process group'):
                        await host.stop(process, group=True)
                    receipt = None
                else:
                    receipt = await host.stop(process, group=True)
        self.assertGreater(process.waits, 0)
        self.assertEqual(signals, [(24101, owner.signal.SIGTERM), (24101, owner.signal.SIGKILL)])
        return receipt

    async def test_exited_leader_does_not_hide_surviving_owned_child(self):
        receipt = await self.stop_group(initially_exited=True)
        self.assertTrue(receipt['groupGone'])
        self.assertTrue(receipt['hardKilled'])
        self.assertTrue(receipt['reaped'])

    async def test_leader_exit_after_term_does_not_hide_surviving_owned_child(self):
        receipt = await self.stop_group(initially_exited=False)
        self.assertTrue(receipt['groupGone'])
        self.assertTrue(receipt['hardKilled'])

    async def test_unconfirmed_group_cleanup_fails_after_reaping_leader(self):
        await self.stop_group(initially_exited=True, survives_kill=True)


class StreamTests(unittest.IsolatedAsyncioTestCase):
    async def test_child_exit_race_during_cleanup_still_reaps_the_owned_process(self):
        class ExitedProcess:
            pid = 123
            returncode = None

            def terminate(self):
                raise ProcessLookupError()

            async def wait(self):
                self.returncode = 0
                return 0

        with tempfile.TemporaryDirectory() as root:
            host = owner.Host(path.parent, pathlib.Path(root), pathlib.Path(root))
            receipt = await host.stop(ExitedProcess())
            self.assertTrue(receipt['reaped'])
            self.assertEqual(receipt['status'], 0)

    async def test_actual_child_bytes_reach_log_before_exit_and_keep_both_streams_and_status(self):
        with tempfile.TemporaryDirectory() as root:
            evidence = pathlib.Path(root)
            live = evidence / 'live.log'
            live.touch()
            host = owner.Host(path.parent, evidence, evidence)
            command = [sys.executable, '-c', "import os,time;os.write(1,b'first');time.sleep(.4);os.write(2,b'second');raise SystemExit(23)"]
            process = await host.start(command, None, pipe=True)
            captured = io.BytesIO()
            wrapper = io.TextIOWrapper(captured)
            task = None
            try:
                with contextlib.redirect_stdout(wrapper):
                    task = asyncio.create_task(host.stream(process, live))
                    for _ in range(100):
                        if live.read_bytes() == b'first':
                            break
                        await asyncio.sleep(.002)
                    self.assertEqual(live.read_bytes(), b'first')
                    self.assertIsNone(process.returncode)
                    self.assertEqual(await task, 23)
                self.assertEqual(live.read_bytes(), b'firstsecond')
                self.assertEqual(captured.getvalue(), b'firstsecond')
            finally:
                if task and not task.done():
                    task.cancel()
                    await asyncio.gather(task, return_exceptions=True)
                await host.stop(process, group=True)


if __name__ == '__main__':
    unittest.main()
