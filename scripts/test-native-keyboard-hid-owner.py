import asyncio
import contextlib
import io
import sys
import json
import importlib.util
import pathlib
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock

path = pathlib.Path(__file__).with_name('with-native-keyboard-hid.py')
spec = importlib.util.spec_from_file_location('hid_owner', path)
owner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(owner)

CASE = '-only-testing:TskUITests/TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys'
COMMAND = ['xcodebuild', 'test-without-building', '-destination', 'platform=iOS Simulator,id=343D52B5-399D-4E45-A357-BF8F8446452B', '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never', CASE, '-resultBundlePath', 'Result.xcresult']


class CommandTests(unittest.TestCase):
    def test_only_original_independent_case_and_owned_destination_are_accepted(self):
        owner.validate_command(COMMAND, '343D52B5-399D-4E45-A357-BF8F8446452B')
        for command in [COMMAND + ['-skip-testing:TskUITests/TaskAnnotationUITests'], COMMAND + ['-destination', 'platform=iOS Simulator,id=foreign'], ['echo', 'test'], [x.replace('343D52B5', '443D52B5') for x in COMMAND]]:
            with self.subTest(command=command), self.assertRaises(ValueError):
                owner.validate_command(command, '343D52B5-399D-4E45-A357-BF8F8446452B')


class CanonicalResultTests(unittest.TestCase):
    def test_full_suite_and_existing_filters_select_all_original_cases_without_overriding_arguments(self):
        full=[item for item in COMMAND if item!=CASE]
        self.assertEqual(owner.selected_cases(full),set(owner.CASES))
        annotations=full+['-only-testing:TskUITests/TaskAnnotationUITests']
        self.assertEqual(owner.selected_cases(annotations),{owner.CASE,'TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations'})
        self.assertEqual(owner.selected_cases(COMMAND),{owner.CASE})
        owner.validate_command(full,'343D52B5-399D-4E45-A357-BF8F8446452B')
        self.assertEqual(full,[item for item in COMMAND if item!=CASE])

    def test_public_missing_zero_duplicate_failed_or_incomplete_sequences_never_pass(self):
        name=owner.CASE
        case=dict(nodeType='Test Case',nodeIdentifier=name+'()',result='Passed')
        receipt=dict(cases={name:dict(completed=['commandReturn'],result='passed')})
        self.assertTrue(owner.passed_case(case,{name},receipt))
        for document in [{},dict(children=[case,case]),dict(case,result='Failed')]:
            self.assertFalse(owner.passed_case(document,{name},receipt))
        self.assertFalse(owner.passed_case(case,set(),receipt))
        self.assertFalse(owner.passed_case(case,{name},dict(cases={name:dict(completed=[],result='passed')})))
        self.assertFalse(owner.passed_case(case,{name,'TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations'},receipt))

    def test_original_phone_only_ipad_skip_is_allowed_without_hid_input(self):
        name='iPadWorkspaceUITests/testInjectedKeyboardCaptureSelectionEditCompletionAndReopen'
        case=dict(nodeType='Test Case',nodeIdentifier=name+'()',result='Skipped')
        receipt=dict(cases={name:dict(completed=[],result='skipped')})
        self.assertTrue(owner.passed_case(case,{name},receipt))
        self.assertFalse(owner.passed_case(dict(case,nodeIdentifier=owner.CASE+'()'),{owner.CASE},dict(cases={owner.CASE:dict(completed=[],result='skipped')})))


class FakeProcess:
    def __init__(self, kind, pid):
        self.kind, self.pid, self.returncode = kind, pid, None


class FakeHost:
    def __init__(self, evidence, *, fail=None, code=0, marked=True, complete=True, passed=True):
        self.evidence, self.fail, self.code = evidence, fail, code
        self.marked, self.complete, self.passed = marked, complete, passed
        self.events, self.environments = [], []

    async def start(self, command, log, environment=None, pipe=False):
        kind = 'companion' if command[0].endswith('idb_companion') else 'relay' if 'relay-native-keyboard-hid.py' in command[1] else 'initialization' if '--initialize-transport' in command else 'tests'
        self.events.append('start:' + kind)
        self.environments.append(environment)
        return FakeProcess(kind, 100 + len(self.events))

    async def wait_socket(self, socket, process):
        self.events.append('socket')
        if self.fail == 'socket':
            raise RuntimeError('companion unavailable')

    async def wait_initialized(self, process):
        self.events.append('initialized')
        if self.fail == 'initialization':
            raise RuntimeError('transport initialization failed')
        if self.fail == 'initialization-cancel':
            raise asyncio.CancelledError()
        process.returncode = 0

    async def wait_armed(self, path, relay, token, companion_pid):
        self.events.append('armed')
        if self.fail == 'armed':
            raise RuntimeError('relay unavailable')
        return dict(state='waiting', relayToken=token, companionPID=companion_pid, logStartOffset=0)

    async def stream(self, process, live, relay=None):
        self.events.append('stream')
        if self.marked:
            live.write_bytes(owner.MARKER + b'owned request\n')
        final = dict(state='completed_native_assertions_required' if self.complete else 'waiting', cases={owner.CASE: dict(completed=['commandReturn'] if self.complete else [], result='passed' if self.passed else 'failed')}, inFlight=None if self.complete else dict(caseName=owner.CASE, phase='commandReturn'), transportComplete=self.complete)
        (self.evidence / 'relay-receipt.json').write_text(json.dumps(final))
        if self.fail == 'cancel':
            raise asyncio.CancelledError()
        if self.fail == 'timeout':
            raise TimeoutError('Owned infrastructure deadline elapsed')
        process.returncode = self.code
        return self.code

    async def finish_relay(self, process, stop_file):
        self.events.append('finish-relay')

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

    async def recover(self, socket, request):
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
        self.assertLess(host.events.index('socket'), host.events.index('start:initialization'))
        self.assertLess(host.events.index('initialized'), host.events.index('start:relay'))
        self.assertLess(host.events.index('armed'), host.events.index('start:tests'))
        self.assertEqual(receipt['transportInitialization']['events'], [[40, 'UP'], [227, 'UP']])
        self.assertEqual(receipt['transportInitialization']['timeoutSeconds'], 30)
        self.assertEqual(receipt['transportInitialization']['state'], 'up_only_rpc_completed_native_assertions_required')
        self.assertEqual(host.environments[-1]['TEST_RUNNER_TSK_TEST_HID_RELAY_TOKEN'], 'A2A514F2-FE63-40E1-9A42-B097CB8E9F23')
        self.assertEqual(host.environments[-1]['TEST_RUNNER_TSK_TEST_HID_DRIVER'], '1')
        self.assertEqual(host.events[-4:], ['stop:tests', 'stop:relay', 'stop:initialization', 'stop:companion'])
        self.assertTrue(receipt['selectedOriginalCasesPassed'])

    async def test_socket_and_arm_failure_never_launch_test_and_reap_only_started_children(self):
        for fail in ['socket', 'initialization', 'initialization-cancel', 'armed']:
            status, host, _ = await self.run_case(fail=fail, marked=False, complete=False)
            self.assertEqual(status, 130 if fail == 'initialization-cancel' else 70)
            self.assertEqual('stop:initialization' in host.events, fail != 'socket')
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
        self.assertEqual(host.events[-3:], ['stop:relay', 'stop:initialization', 'stop:companion'])

    async def test_unconfirmed_up_recovery_never_reports_success(self):
        status, host, receipt = await self.run_case(fail='recovery', complete=False)
        self.assertEqual(status, 70)
        self.assertIn('upOnlyRecoveryError', receipt)
        self.assertEqual(host.events[-1], 'stop:companion')


class InitializationTests(unittest.IsolatedAsyncioTestCase):
    async def test_initialization_wait_is_bounded_and_nonzero_exit_cannot_arm(self):
        with tempfile.TemporaryDirectory() as root:
            host = owner.Host(path.parent, pathlib.Path(root), pathlib.Path(root))
            wait_for = asyncio.wait_for
            for status in [0, 1]:
                process = SimpleNamespace(wait=mock.AsyncMock(return_value=status))
                with mock.patch.object(owner.asyncio, 'wait_for', wraps=wait_for) as bounded:
                    if status:
                        with self.assertRaisesRegex(RuntimeError, 'initialization failed'):
                            await host.wait_initialized(process)
                    else:
                        await host.wait_initialized(process)
                self.assertEqual(bounded.call_args.kwargs['timeout'], 30)

    async def test_initialization_deadline_stops_owned_process_before_companion(self):
        with tempfile.TemporaryDirectory() as root:
            evidence = pathlib.Path(root) / 'evidence'

            class TimedOutHost(FakeHost):
                async def wait_initialized(self, process):
                    raise TimeoutError('Transport initialization exceeded 30 seconds')

            host = TimedOutHost(evidence)
            comparison = owner.Comparison('343D52B5-399D-4E45-A357-BF8F8446452B', pathlib.Path(root), evidence, pathlib.Path(root) / 'owned.sock', COMMAND, host=host)
            self.assertEqual(await comparison.run(), 124)
            self.assertNotIn('start:relay', host.events)
            self.assertNotIn('start:tests', host.events)
            self.assertEqual(host.events[-2:], ['stop:initialization', 'stop:companion'])
            self.assertTrue(comparison.receipt['initializationCleanup']['reaped'])

    async def test_up_only_rpc_keeps_recovery_budget_and_separate_initialization_budget(self):
        releases = ((40, 'UP'), (227, 'UP'))
        send = mock.AsyncMock()
        make_sender = mock.Mock(return_value=send)
        relay = SimpleNamespace(make_sender=make_sender, RELEASES=releases)
        spec = SimpleNamespace(loader=SimpleNamespace(exec_module=lambda module: None))
        socket = mock.Mock()
        socket.is_absolute.return_value = True
        socket.stat.return_value = SimpleNamespace(st_mode=owner.stat.S_IFSOCK)
        wait_for = asyncio.wait_for
        with mock.patch.object(owner.importlib.util, 'spec_from_file_location', return_value=spec), mock.patch.object(owner.importlib.util, 'module_from_spec', return_value=relay), contextlib.redirect_stdout(io.StringIO()):
            for timeout in [5, 30]:
                with mock.patch.object(owner.asyncio, 'wait_for', wraps=wait_for) as bounded:
                    await owner.release_only(socket, timeout=timeout)
                send.assert_awaited_with(((40, 'UP'), (227, 'UP')))
                self.assertEqual(bounded.call_args.kwargs['timeout'], timeout)
        self.assertEqual(send.await_count, 2)
        make_sender.assert_called_with(str(socket))

    async def test_cli_initialization_uses_thirty_seconds_and_recovery_still_uses_five(self):
        for mode, timeout in [('--initialize-transport', 30), ('--release-only', 5)]:
            with mock.patch.object(owner.sys, 'argv', [str(path), mode, '--socket', '/tmp/owned.sock']), mock.patch.object(owner, 'release_only', new_callable=mock.AsyncMock) as release:
                self.assertEqual(await owner.main(), 0)
                release.assert_awaited_once_with(pathlib.Path('/tmp/owned.sock'), timeout=timeout)


class CleanupCancellationTests(unittest.IsolatedAsyncioTestCase):
    async def test_first_cancel_during_normal_group_cleanup_waits_for_all_owned_cleanup(self):
        for interrupt_status in [130, 143]:
            with self.subTest(status=interrupt_status), tempfile.TemporaryDirectory() as root:
                entered = asyncio.Event()
                release = asyncio.Event()
                evidence = pathlib.Path(root) / 'evidence'

                class SuspendedCleanupHost(FakeHost):
                    async def stop(self, process, group=False):
                        if process.kind == 'tests':
                            entered.set()
                            await release.wait()
                        return await super().stop(process, group)

                host = SuspendedCleanupHost(evidence, complete=False)
                comparison = owner.Comparison('343D52B5-399D-4E45-A357-BF8F8446452B', pathlib.Path(root), evidence, pathlib.Path(root) / 'owned.sock', COMMAND, host=host)
                comparison.cancel_status = interrupt_status
                task = asyncio.create_task(comparison.run())
                await asyncio.wait_for(entered.wait(), timeout=1)
                self.assertEqual(task.cancelling(), 0)
                task.cancel()
                await asyncio.sleep(0)
                waiting_for_cleanup = not task.done()
                release.set()
                try:
                    result = await asyncio.wait_for(task, timeout=1)
                except asyncio.CancelledError:
                    result = None
                self.assertTrue(waiting_for_cleanup, 'Owner must await cleanup settlement after its first cancellation')
                self.assertEqual(result, interrupt_status)
                self.assertEqual(host.events[-5:], ['stop:tests', 'stop:relay', 'stop:initialization', 'UP-only', 'stop:companion'])
                receipt = json.loads((evidence / 'owner-receipt.json').read_text())
                self.assertEqual(receipt['status'], interrupt_status)
                self.assertTrue(receipt['testsCleanup']['reaped'])
                self.assertTrue(receipt['relayCleanup']['reaped'])
                self.assertTrue(receipt['initializationCleanup']['reaped'])
                self.assertTrue(receipt['companionCleanup']['reaped'])
                self.assertIn('upOnlyRecovery', receipt)


class PublicQueryCancellationTests(unittest.IsolatedAsyncioTestCase):
    async def test_cancel_during_actual_query_finally_reaps_registered_query_and_all_components(self):
        with tempfile.TemporaryDirectory() as root:
            entered=asyncio.Event(); evidence=pathlib.Path(root)/'evidence'
            class QueryHost(FakeHost):
                public_result=owner.Host.public_result
                first_cleanup=True

                async def start(self,command,log,environment=None,pipe=False):
                    if command[0]=='xcrun':
                        process=FakeProcess('public-query',456)
                        process.returncode=0
                        result=dict(nodeType='Test Case',nodeIdentifier=owner.CASE+'()',result='Passed')
                        process.communicate=mock.AsyncMock(return_value=(json.dumps(result).encode(),None))
                        return process
                    return await super().start(command,log,environment,pipe)

                async def stop(self,process,group=False):
                    if process.kind=='public-query' and self.first_cleanup:
                        self.first_cleanup=False
                        entered.set()
                        await asyncio.Event().wait()
                    return await super().stop(process,group)

            host=QueryHost(evidence)
            comparison=owner.Comparison('343D52B5-399D-4E45-A357-BF8F8446452B',pathlib.Path(root),evidence,pathlib.Path(root)/'owned.sock',COMMAND,host=host)
            task=asyncio.create_task(comparison.run());await asyncio.wait_for(entered.wait(),1);task.cancel()
            self.assertEqual(await asyncio.wait_for(task,1),130)
            self.assertTrue(comparison.receipt['publicQueryCleanup']['reaped'])
            self.assertEqual(host.events[-2:],['stop:public-query','stop:companion'])
            self.assertEqual(json.loads((evidence/'public-result-query.json').read_text())['timeoutSeconds'],60)


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
