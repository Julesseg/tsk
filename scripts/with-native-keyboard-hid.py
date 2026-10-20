import argparse
import asyncio
import importlib.util
import json
import math
import os
import pathlib
import signal
import stat
import sys
import tempfile
import time
import uuid

CASE = 'TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys'
CASES = {CASE: ['commandReturn'], 'TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations': ['secondNoteCommandN', 'secondNoteSave', 'editSelectAll', 'editedNoteSave'], 'iPadWorkspaceUITests/testInjectedKeyboardCaptureSelectionEditCompletionAndReopen': ['capture', 'saveNew', 'select', 'edit', 'saveEdit', 'complete', 'completedView']}
MARKER = b'TSK_KEYBOARD_COMMAND_REQUEST_V1 '


def validate_command(command, udid):
    if command[:2] != ['xcodebuild', 'test-without-building']:
        raise ValueError('Canonical HID requires xcodebuild test-without-building')
    for option, expected in [('-destination', 'platform=iOS Simulator,id=' + udid), ('-parallel-testing-enabled', 'NO'), ('-collect-test-diagnostics', 'never')]:
        if command.count(option) != 1 or command[command.index(option) + 1] != expected:
            raise ValueError('Unexpected owned command option: ' + option)
    if command.count('-resultBundlePath') != 1:
        raise ValueError('Canonical HID requires one normal result bundle')
    if not selected_cases(command):
        raise ValueError('Canonical HID requires selected original keyboard cases')


def selected_cases(command):
    only = [item.removeprefix('-only-testing:') for item in command if item.startswith('-only-testing:')]
    skip = [item.removeprefix('-skip-testing:') for item in command if item.startswith('-skip-testing:')]

    def matches(selector, case):
        return ('TskUITests/' + case).startswith(selector.rstrip('/') + '/') or 'TskUITests/' + case == selector

    return {case for case in CASES if (not only or any(matches(selector, case) for selector in only)) and not any(matches(selector, case) for selector in skip)}


def passed_case(document, expected=None, relay=None):
    expected = expected if expected is not None else {CASE}
    relay = relay or {}
    cases = {}
    if not expected:
        return False

    def visit(value):
        if isinstance(value, dict):
            if value.get('nodeType') == 'Test Case':
                name = value.get('nodeIdentifier', '').removesuffix('()')
                if name in expected:
                    cases.setdefault(name, []).append(value.get('result'))
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(document)
    for name in expected:
        outcomes = cases.get(name, [])
        record = relay.get('cases', {}).get(name, {})
        if outcomes == ['Passed'] and record.get('completed') == CASES[name] and record.get('result') == 'passed':
            continue
        if name.startswith('iPadWorkspaceUITests/') and outcomes == ['Skipped'] and record.get('completed') == [] and record.get('result') == 'skipped':
            continue
        return False
    return True


def read_receipt(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


class Host:
    def __init__(self, scripts, tools, evidence):
        self.scripts, self.tools, self.evidence = scripts, tools, evidence

    async def start(self, command, log, environment=None, pipe=False):
        if pipe:
            return await asyncio.create_subprocess_exec(*command, env=environment, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT, start_new_session=True)
        with log.open('wb', buffering=0) as file:
            return await asyncio.create_subprocess_exec(*command, env=environment, stdout=file, stderr=asyncio.subprocess.STDOUT, start_new_session=True)

    async def wait_socket(self, socket, process):
        deadline = time.monotonic() + 30
        while True:
            if process.returncode is not None:
                raise RuntimeError('Owned companion exited before socket readiness')
            if socket.exists() and stat.S_ISSOCK(socket.stat().st_mode):
                return
            if time.monotonic() >= deadline:
                raise TimeoutError('Owned companion socket exceeded 30 seconds')
            await asyncio.sleep(0.02)

    async def wait_relay(self, path, relay, binding, deadline, phase):
        while True:
            if relay.returncode is not None:
                raise RuntimeError('Owned relay exited before ' + phase)
            if time.monotonic() >= deadline:
                raise TimeoutError('Relay ' + phase + ' exceeded its original deadline')
            receipt = read_receipt(path)
            if time.monotonic() >= deadline:
                raise TimeoutError('Relay ' + phase + ' exceeded its original deadline')
            if receipt:
                if any(receipt.get(key) != value for key, value in binding.items()):
                    raise ValueError('Relay startup receipt does not match this owner')
                if receipt.get('state') == 'failed':
                    raise RuntimeError('Owned relay failed before ' + phase)
                if receipt.get('state') not in ('preparing', 'waiting'):
                    raise ValueError('Relay startup receipt has an unexpected state')
                initialization = receipt.get('initialization', {})
                if initialization:
                    completed = initialization.get('completedMonotonic')
                    if initialization.get('state') != 'up_only_rpc_completed_native_assertions_required' or initialization.get('events') != [[40, 'UP'], [227, 'UP']] or type(completed) not in (int, float) or not math.isfinite(completed) or not 0 < completed <= time.monotonic():
                        raise ValueError('Relay initialization proof is invalid')
                    if phase == 'initialization':
                        if time.monotonic() >= deadline:
                            raise TimeoutError('Relay initialization exceeded its original deadline')
                        return receipt
                    if receipt.get('state') == 'waiting':
                        if receipt.get('logStartOffset') != 0:
                            raise ValueError('Relay waiting receipt has an unexpected log offset')
                        if time.monotonic() >= deadline:
                            raise TimeoutError('Relay arming exceeded its original deadline')
                        return receipt
                elif receipt.get('state') == 'waiting':
                    raise ValueError('Relay armed without UP-only initialization proof')
            await asyncio.sleep(0.01)

    async def stream(self, process, live, relay=None):
        async def pump():
            with live.open('ab', buffering=0) as file:
                while chunk := await process.stdout.read(4096):
                    file.write(chunk)
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()

        pump_task = asyncio.create_task(pump())
        test_wait = asyncio.create_task(process.wait())
        relay_wait = asyncio.create_task(relay.wait()) if relay else None
        try:
            if relay_wait:
                done, _ = await asyncio.wait([test_wait, relay_wait], return_when=asyncio.FIRST_COMPLETED)
                if relay_wait in done and test_wait not in done:
                    raise RuntimeError('HID relay exited while the owned UI command was active')
            status = await test_wait
            try:
                await asyncio.wait_for(asyncio.shield(pump_task), timeout=0.25)
            except TimeoutError:
                pump_task.cancel()
            return status
        finally:
            tasks = [pump_task, test_wait] + ([relay_wait] if relay_wait else [])
            for task in tasks:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    async def finish_relay(self, process, stop_file):
        stop_file.touch(exist_ok=False)
        status = await asyncio.wait_for(process.wait(), timeout=10)
        if status:
            raise RuntimeError('HID relay failed with status ' + str(status))

    async def stop(self, process, group=False):
        hard_killed = False
        if group:
            pgid = process.pid
            if type(pgid) is not int or pgid <= 1 or pgid == os.getpgrp():
                raise RuntimeError('Refusing invalid or current process group: ' + str(pgid))
            detail = dict(pid=process.pid, pgid=pgid, phases=[])
            path = self.evidence / ('process-cleanup-' + str(process.pid) + '.json')

            def record(phase, error=None):
                row = dict(phase=phase, timeMonotonic=time.monotonic())
                if error is not None:
                    row.update(error=repr(error), errno=getattr(error, 'errno', None))
                detail['phases'].append(row)
                try:
                    path.write_text(json.dumps(detail, indent=2) + '\n')
                except OSError as error:
                    detail['receiptError'] = repr(error)

            def signal_group(number, phase):
                record(phase)
                try:
                    os.killpg(pgid, number)
                    return True
                except ProcessLookupError:
                    return False
                except OSError as error:
                    record(phase, error)
                    raise RuntimeError('Owned process group cleanup failed phase=' + phase + ' pid=' + str(process.pid) + ' pgid=' + str(pgid) + ' errno=' + str(error.errno)) from error

            async def wait_for_group(seconds):
                deadline = time.monotonic() + seconds
                while signal_group(0, 'group-existence'):
                    if time.monotonic() >= deadline:
                        return False
                    await asyncio.sleep(0.05)
                return True

            group_gone = False
            try:
                if process.returncode is None:
                    record('parent-interrupt')
                    try:
                        process.send_signal(signal.SIGINT)
                    except ProcessLookupError:
                        pass
                    try:
                        await asyncio.wait_for(process.wait(), timeout=5)
                    except TimeoutError:
                        record('parent-interrupt-timeout')
                signal_group(signal.SIGTERM, 'group-term')
                group_gone = await wait_for_group(10)
                if not group_gone:
                    signal_group(signal.SIGKILL, 'group-kill')
                    hard_killed = True
                    group_gone = await wait_for_group(5)
            finally:
                if process.returncode is None:
                    record('parent-term')
                    try:
                        process.terminate()
                    except ProcessLookupError:
                        pass
                try:
                    await asyncio.wait_for(process.wait(), timeout=5)
                except TimeoutError:
                    record('parent-kill')
                    try:
                        process.kill()
                    except ProcessLookupError:
                        pass
                    await asyncio.wait_for(process.wait(), timeout=5)
                detail.update(status=process.returncode, reaped=True, groupGone=group_gone)
                record('parent-reaped')
            if detail.get('receiptError'):
                raise RuntimeError('Owned process cleanup receipt could not be persisted: ' + detail['receiptError'])
            if not group_gone:
                raise RuntimeError('Owned process group cleanup remains unconfirmed: ' + str(process.pid))
            return dict(pid=process.pid, status=process.returncode, reaped=True, hardKilled=hard_killed, groupGone=True)
        if process.returncode is None:
            try:
                process.terminate()
            except ProcessLookupError:
                pass
            try:
                await asyncio.wait_for(process.wait(), timeout=10)
            except TimeoutError:
                try:
                    process.kill()
                except ProcessLookupError:
                    pass
                await asyncio.wait_for(process.wait(), timeout=5)
                hard_killed = True
        else:
            await process.wait()
        return dict(pid=process.pid, status=process.returncode, reaped=True, hardKilled=hard_killed)

    async def recover(self, socket, request):
        command = [str(self.tools / 'venv/bin/python'), str(self.scripts / 'with-native-keyboard-hid.py'), '--release-only', '--socket', str(socket), '--case-name', request['caseName'], '--phase', request['phase']]
        process = await self.start(command, self.evidence / 'up-only-recovery.log')
        try:
            status = await asyncio.wait_for(process.wait(), timeout=10)
            if status:
                raise RuntimeError('UP-only recovery failed with status ' + str(status))
        finally:
            await self.stop(process)

    async def public_result(self, command):
        bundle = command[command.index('-resultBundlePath') + 1]
        args = ['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', bundle]
        process = await self.start(args, None, pipe=True)
        self.query_process = process
        query = dict(command=args, pid=process.pid, startedMonotonic=time.monotonic(), timeoutSeconds=60)
        try:
            raw, _ = await asyncio.wait_for(process.communicate(), timeout=60)
            query.update(status=process.returncode, durationSeconds=time.monotonic() - query['startedMonotonic'])
            (self.evidence / 'public-result-query.json').write_text(json.dumps(query, indent=2) + '\n')
            (self.evidence / 'executed-tests.json').write_bytes(raw)
            if process.returncode:
                raise RuntimeError('Public test-result query failed')
            return json.loads(raw)
        finally:
            query.update(status=process.returncode, finishedMonotonic=time.monotonic())
            (self.evidence / 'public-result-query.json').write_text(json.dumps(query, indent=2) + '\n')
            await self.stop(process)


class Comparison:
    def __init__(self, udid, tools, evidence, socket, command, host=None, token=None):
        self.udid, self.tools, self.evidence, self.socket, self.command = udid, tools, evidence, socket, command
        self.scripts = pathlib.Path(__file__).resolve().parent
        self.host = host or Host(self.scripts, tools, evidence)
        self.token = token or str(uuid.uuid4())
        self.receipt = dict(udid=udid, socket=str(socket), relayToken=self.token, command=command, nativeAcceptance='Only original public XCTest result and native assertions establish acceptance')
        self.cancel_status = 130

    def save(self):
        (self.evidence / 'owner-receipt.json').write_text(json.dumps(self.receipt, indent=2) + '\n')

    async def run(self):
        command = self.command
        validate_command(command, self.udid)
        self.evidence.mkdir(parents=True, exist_ok=False)
        live = self.evidence / 'live-xcodebuild.log'
        live.touch(exist_ok=False)
        relay_receipt = self.evidence / 'relay-receipt.json'
        stop_file = self.evidence / 'relay.stop'
        companion = relay = tests = None
        status = 70
        try:
            args = [str(self.tools / 'companion/idb_companion'), '--udid', self.udid, '--only', 'simulator', '--grpc-domain-sock', str(self.socket), '--terminate-offline', '1', '--log-hid-details', '1', '--log-level', 'debug']
            companion = await self.host.start(args, self.evidence / 'companion.log')
            self.receipt['companion'] = dict(pid=companion.pid, command=args)
            self.save()
            await self.host.wait_socket(self.socket, companion)
            args = [str(self.tools / 'venv/bin/python'), str(self.scripts / 'relay-native-keyboard-hid.py'), '--log', str(live), '--socket', str(self.socket), '--udid', self.udid, '--companion-pid', str(companion.pid), '--relay-token', self.token, '--receipt', str(relay_receipt), '--stop-file', str(stop_file)]
            initialization_deadline = time.monotonic() + 30
            relay = await self.host.start(args, self.evidence / 'relay.log')
            self.receipt['relay'] = dict(pid=relay.pid, command=args)
            self.receipt['transportInitialization'] = dict(pid=relay.pid, timeoutSeconds=30, deadlineMonotonic=initialization_deadline, events=[[40, 'UP'], [227, 'UP']], state='started')
            self.save()
            binding = dict(udid=self.udid, socket=str(self.socket), companionPID=companion.pid, relayPID=relay.pid, relayToken=self.token)
            initialized = await self.host.wait_relay(relay_receipt, relay, binding, initialization_deadline, 'initialization')
            self.receipt['transportInitialization']['state'] = 'up_only_rpc_completed_native_assertions_required'
            self.receipt['transportInitialization']['completedMonotonic'] = initialized['initialization']['completedMonotonic']
            self.save()
            arming_deadline = initialized['initialization']['completedMonotonic'] + 10
            binding['initialization'] = initialized['initialization']
            self.receipt['armed'] = await self.host.wait_relay(relay_receipt, relay, binding, arming_deadline, 'arming')
            if companion.returncode is not None or relay.returncode is not None:
                raise RuntimeError('Owned transport process exited before XCTest launch')
            environment = dict(os.environ, TEST_RUNNER_TSK_TEST_HID_RELAY_TOKEN=self.token, TEST_RUNNER_TSK_TEST_HID_DRIVER='1')
            self.receipt['runnerEnvironmentAdded'] = {'TEST_RUNNER_TSK_TEST_HID_RELAY_TOKEN': self.token, 'TEST_RUNNER_TSK_TEST_HID_DRIVER': '1'}
            self.save()
            tests = await self.host.start(self.command, None, environment, pipe=True)
            self.receipt['testPID'] = tests.pid
            self.save()
            status = await self.host.stream(tests, live, relay)
            self.receipt['xcodebuildStatus'] = status
            await self.host.finish_relay(relay, stop_file)
            self.receipt['publicTests'] = await self.host.public_result(command)
            self.receipt['selectedKeyboardCases'] = sorted(selected_cases(command))
            self.receipt['selectedOriginalCasesPassed'] = passed_case(self.receipt['publicTests'], selected_cases(command), read_receipt(relay_receipt))
            if status == 0 and not self.receipt['selectedOriginalCasesPassed']:
                status = 70
        except asyncio.CancelledError:
            status = self.cancel_status
            self.receipt['error'] = 'Owner cancelled'
        except TimeoutError as error:
            status = 124
            self.receipt['error'] = repr(error)
        except Exception as error:
            status = status or 70
            self.receipt['error'] = repr(error)
        finally:
            cleanup_task = asyncio.create_task(self._cleanup(tests, relay, companion, live, relay_receipt, status))
            try:
                status = await asyncio.shield(cleanup_task)
            except asyncio.CancelledError:
                self.receipt['error'] = 'Owner cancelled'
                self.receipt['cancelledDuringCleanup'] = True
                await cleanup_task
                status = self.cancel_status
                self.receipt['status'] = status
                self.save()
        return status

    async def _cleanup(self, tests, relay, companion, live, relay_receipt, status):
        for name, process in [('tests', tests), ('relay', relay), ('publicQuery', getattr(self.host, 'query_process', None))]:
            if process is not None:
                try:
                    self.receipt[name + 'Cleanup'] = await self.host.stop(process, group=name == 'tests')
                except Exception as error:
                    self.receipt[name + 'CleanupError'] = repr(error)
                    status = status or 70
        final = read_receipt(relay_receipt)
        self.receipt['relayResult'] = final
        complete = final.get('state') == 'completed_native_assertions_required'
        marked = final.get('inFlight') is not None
        self.receipt['markerObserved'] = marked
        cleanup_confirmed = any('UP cleanup RPC completed' in note for note in final.get('notes', []))
        if marked and not final.get('transportComplete') and not cleanup_confirmed:
            try:
                await self.host.recover(self.socket, final['inFlight'])
                self.receipt['upOnlyRecovery'] = 'RPC completed; native key state still requires evidence'
            except Exception as error:
                self.receipt['upOnlyRecoveryError'] = repr(error)
                status = status or 70
        if companion is not None:
            try:
                self.receipt['companionCleanup'] = await self.host.stop(companion)
            except Exception as error:
                self.receipt['companionCleanupError'] = repr(error)
                status = status or 70
        if not complete:
            status = status or 70
        self.receipt['status'] = status
        self.save()
        return status


async def release_only(socket, timeout=5, case_name=None, phase=None):
    if not socket.is_absolute() or not stat.S_ISSOCK(socket.stat().st_mode):
        raise ValueError('UP-only recovery requires the explicit owned Unix socket')
    spec = importlib.util.spec_from_file_location('fixed_native_hid_relay', pathlib.Path(__file__).with_name('relay-native-keyboard-hid.py'))
    relay = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(relay)
    events = relay.RELEASES if case_name is None and phase is None else relay.releases(relay.CHORDS[case_name][phase])
    async def release():
        async with relay.make_sender(str(socket)) as send:
            await send(events)
    await asyncio.wait_for(release(), timeout=timeout)
    print('Owned UP-only RPC completed ' + repr(events) + '; native key state remains unverified', flush=True)


async def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--release-only', action='store_true')
    mode.add_argument('--initialize-transport', action='store_true')
    parser.add_argument('--socket', type=pathlib.Path)
    parser.add_argument('--case-name')
    parser.add_argument('--phase')
    parser.add_argument('--udid')
    parser.add_argument('--tool-root', type=pathlib.Path)
    parser.add_argument('--evidence', type=pathlib.Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.release_only or args.initialize_transport:
        if not args.socket or args.command:
            parser.error('UP-only mode requires only the explicit socket')
        if args.initialize_transport and (args.case_name or args.phase):
            parser.error('Initialization sends only its fixed UP sequence')
        await release_only(args.socket, timeout=30 if args.initialize_transport else 5, **(dict(case_name=args.case_name, phase=args.phase) if args.case_name or args.phase else {}))
        return 0
    if not args.udid or not args.tool_root or not args.evidence:
        parser.error('Pass owned UDID, pinned tool root and evidence directory')
    uuid.UUID(args.udid)
    if os.environ.get('CI') != 'true' or os.environ.get('TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR') != '1':
        parser.error('Canonical HID requires the CI-owned isolated simulator')
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    with tempfile.TemporaryDirectory(prefix='tsk-native-hid-', dir='/tmp') as directory:
        comparison = Comparison(args.udid, args.tool_root.resolve(), args.evidence.resolve(), pathlib.Path(directory) / 'owned.sock', command)
        task = asyncio.current_task()
        loop = asyncio.get_running_loop()
        for number in (signal.SIGTERM, signal.SIGINT):
            def cancel(number=number):
                if not task.cancelling():
                    comparison.cancel_status = 128 + number
                    task.cancel()
            loop.add_signal_handler(number, cancel)
        try:
            return await comparison.run()
        finally:
            for number in (signal.SIGTERM, signal.SIGINT):
                loop.remove_signal_handler(number)


if __name__ == '__main__':
    raise SystemExit(asyncio.run(main()))
