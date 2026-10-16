import argparse
import asyncio
import importlib.util
import json
import os
import pathlib
import signal
import stat
import sys
import tempfile
import time
import uuid

CASE = 'TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys'
MARKER = b'TSK_NATIVE_KEYBOARD_HID_REQUEST_V1 '


def validate_command(command, udid):
    if command[:2] != ['xcodebuild', 'test-without-building']:
        raise ValueError('The pilot requires xcodebuild test-without-building')
    if [arg for arg in command if arg.startswith('-only-testing:')] != ['-only-testing:TskUITests/' + CASE]:
        raise ValueError('The pilot requires only the original independent native control')
    if any(arg.startswith('-skip-testing:') and arg != '-skip-testing:TskUITests/ShareCaptureUITests' for arg in command):
        raise ValueError('The pilot cannot skip its native assertions')
    for option, expected in [('-destination', 'platform=iOS Simulator,id=' + udid), ('-parallel-testing-enabled', 'NO')]:
        if command.count(option) != 1 or command[command.index(option) + 1] != expected:
            raise ValueError('Unexpected owned pilot option: ' + option)
    if command.count('-resultBundlePath') != 1:
        raise ValueError('The pilot requires one normal result bundle')


def passed_case(document):
    cases = []

    def visit(value):
        if isinstance(value, dict):
            if value.get('nodeType') == 'Test Case':
                cases.append(value)
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(document)
    return len(cases) == 1 and cases[0].get('nodeIdentifier') == CASE + '()' and cases[0].get('result') == 'Passed'


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

    async def wait_initialized(self, process):
        status = await asyncio.wait_for(process.wait(), timeout=30)
        if status:
            raise RuntimeError('UP-only transport initialization failed with status ' + str(status))

    async def wait_armed(self, path, relay, token, companion_pid):
        deadline = time.monotonic() + 10
        while True:
            receipt = read_receipt(path)
            if receipt.get('state') == 'waiting':
                if receipt.get('relayToken') != token or receipt.get('companionPID') != companion_pid or receipt.get('logStartOffset') != 0:
                    raise ValueError('Relay waiting receipt does not match this owner')
                return receipt
            if relay.returncode is not None:
                raise RuntimeError('Fixed relay exited before arming')
            if time.monotonic() >= deadline:
                raise TimeoutError('Relay arming exceeded 10 seconds')
            await asyncio.sleep(0.01)

    async def stream(self, process, live):
        async def pump():
            with live.open('ab', buffering=0) as file:
                while chunk := await process.stdout.read(4096):
                    file.write(chunk)
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()

        task = asyncio.create_task(pump())
        try:
            status = await asyncio.wait_for(process.wait(), timeout=600)
            try:
                await asyncio.wait_for(asyncio.shield(task), timeout=0.25)
            except TimeoutError:
                task.cancel()
            return status
        finally:
            if not task.done():
                task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    async def stop(self, process, group=False):
        hard_killed = False
        if group:
            def group_exists():
                try:
                    os.killpg(process.pid, 0)
                    return True
                except ProcessLookupError:
                    return False

            async def wait_for_group(seconds):
                deadline = time.monotonic() + seconds
                while group_exists():
                    if time.monotonic() >= deadline:
                        return False
                    await asyncio.sleep(0.05)
                return True

            group_gone = False
            try:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                group_gone = await wait_for_group(10)
                if not group_gone:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    hard_killed = True
                    group_gone = await wait_for_group(5)
            finally:
                await asyncio.wait_for(process.wait(), timeout=5)
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

    async def recover(self, socket):
        command = [str(self.tools / 'venv/bin/python'), str(self.scripts / 'with-native-keyboard-hid.py'), '--release-only', '--socket', str(socket)]
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
        try:
            raw, _ = await asyncio.wait_for(process.communicate(), timeout=25)
            (self.evidence / 'executed-tests.json').write_bytes(raw)
            if process.returncode:
                raise RuntimeError('Public test-result query failed')
            return json.loads(raw)
        finally:
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
        validate_command(self.command, self.udid)
        self.evidence.mkdir(parents=True, exist_ok=False)
        live = self.evidence / 'live-xcodebuild.log'
        live.touch(exist_ok=False)
        relay_receipt = self.evidence / 'relay-receipt.json'
        companion = initialization = relay = tests = None
        status = 70
        try:
            args = [str(self.tools / 'companion/idb_companion'), '--udid', self.udid, '--only', 'simulator', '--grpc-domain-sock', str(self.socket), '--terminate-offline', '1', '--log-hid-details', '1', '--log-level', 'debug']
            companion = await self.host.start(args, self.evidence / 'companion.log')
            self.receipt['companion'] = dict(pid=companion.pid, command=args)
            self.save()
            await self.host.wait_socket(self.socket, companion)
            args = [str(self.tools / 'venv/bin/python'), str(self.scripts / 'with-native-keyboard-hid.py'), '--initialize-transport', '--socket', str(self.socket)]
            initialization = await self.host.start(args, self.evidence / 'transport-initialization.log')
            self.receipt['transportInitialization'] = dict(pid=initialization.pid, command=args, timeoutSeconds=30, events=[[40, 'UP'], [227, 'UP']], state='started')
            self.save()
            await self.host.wait_initialized(initialization)
            self.receipt['transportInitialization']['state'] = 'up_only_rpc_completed_native_assertions_required'
            self.save()
            args = [str(self.tools / 'venv/bin/python'), str(self.scripts / 'relay-native-keyboard-hid.py'), '--log', str(live), '--socket', str(self.socket), '--udid', self.udid, '--companion-pid', str(companion.pid), '--relay-token', self.token, '--receipt', str(relay_receipt)]
            relay = await self.host.start(args, self.evidence / 'relay.log')
            self.receipt['relay'] = dict(pid=relay.pid, command=args)
            self.receipt['armed'] = await self.host.wait_armed(relay_receipt, relay, self.token, companion.pid)
            environment = dict(os.environ, TEST_RUNNER_TSK_TEST_HID_RELAY_TOKEN=self.token)
            self.receipt['runnerEnvironmentAdded'] = {'TEST_RUNNER_TSK_TEST_HID_RELAY_TOKEN': self.token}
            self.save()
            tests = await self.host.start(self.command, None, environment, pipe=True)
            self.receipt['testPID'] = tests.pid
            self.save()
            status = await self.host.stream(tests, live)
            self.receipt['xcodebuildStatus'] = status
            self.receipt['publicTests'] = await self.host.public_result(self.command)
            self.receipt['actualOriginalCasePassed'] = passed_case(self.receipt['publicTests'])
            if status == 0 and not self.receipt['actualOriginalCasePassed']:
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
            cleanup_task = asyncio.create_task(self._cleanup(tests, relay, initialization, companion, live, relay_receipt, status))
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

    async def _cleanup(self, tests, relay, initialization, companion, live, relay_receipt, status):
        for name, process in [('tests', tests), ('relay', relay), ('initialization', initialization)]:
            if process is not None:
                try:
                    self.receipt[name + 'Cleanup'] = await self.host.stop(process, group=name == 'tests')
                except Exception as error:
                    self.receipt[name + 'CleanupError'] = repr(error)
                    status = status or 70
        final = read_receipt(relay_receipt)
        self.receipt['relayResult'] = final
        complete = final.get('state') == 'hid_rpc_completed_native_assertions_required'
        marked = MARKER in live.read_bytes()[:8 * 1024 * 1024 + 1]
        self.receipt['markerObserved'] = marked
        cleanup_confirmed = any('UP cleanup RPC completed' in note for note in final.get('notes', []))
        if marked and not complete and not cleanup_confirmed:
            try:
                await self.host.recover(self.socket)
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


async def release_only(socket, timeout=5):
    if not socket.is_absolute() or not stat.S_ISSOCK(socket.stat().st_mode):
        raise ValueError('UP-only recovery requires the explicit owned Unix socket')
    spec = importlib.util.spec_from_file_location('fixed_native_hid_relay', pathlib.Path(__file__).with_name('relay-native-keyboard-hid.py'))
    relay = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(relay)
    await asyncio.wait_for(relay.make_sender(str(socket))(relay.RELEASES), timeout=timeout)
    print('Owned UP-only RPC completed (40UP,227UP); native key state remains unverified', flush=True)


async def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--release-only', action='store_true')
    mode.add_argument('--initialize-transport', action='store_true')
    parser.add_argument('--socket', type=pathlib.Path)
    parser.add_argument('--udid')
    parser.add_argument('--tool-root', type=pathlib.Path)
    parser.add_argument('--evidence', type=pathlib.Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.release_only or args.initialize_transport:
        if not args.socket or args.command:
            parser.error('UP-only mode requires only the explicit socket')
        await release_only(args.socket, timeout=30 if args.initialize_transport else 5)
        return 0
    if not args.udid or not args.tool_root or not args.evidence:
        parser.error('Pass owned UDID, pinned tool root and evidence directory')
    uuid.UUID(args.udid)
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if '-collect-test-diagnostics' not in command:
        command += ['-collect-test-diagnostics', 'never']
    elif command[command.index('-collect-test-diagnostics') + 1] != 'never':
        parser.error('This focused pilot uses normal attachments without verbose diagnostics')
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
