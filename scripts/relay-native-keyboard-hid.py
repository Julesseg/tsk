import argparse
import asyncio
import importlib.metadata
import json
import logging
import math
import os
import pathlib
import re
import signal
import stat
import sys
import time
import uuid

PREFIX = b'TSK_KEYBOARD_COMMAND_REQUEST_V1 '
ABORT = b'TSK_KEYBOARD_COMMAND_ABORT_V1 '
CASE = 'TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys'
ANNOTATIONS = 'TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations'
WORKSPACE = 'iPadWorkspaceUITests/testInjectedKeyboardCaptureSelectionEditCompletionAndReopen'
RUNNER = 'com.julesseguin.tsk.uitests.xctrunner'
CHORD = ((227, 'DOWN'), (40, 'DOWN'), (40, 'UP'), (227, 'UP'))
RELEASES = ((40, 'UP'), (227, 'UP'))


def chord(key, shift=False):
    modifiers = (227, 225) if shift else (227,)
    return tuple((code, 'DOWN') for code in modifiers) + ((key, 'DOWN'), (key, 'UP')) + tuple((code, 'UP') for code in reversed(modifiers))


CHORDS = {
    CASE: {'commandReturn': CHORD},
    ANNOTATIONS: {'secondNoteCommandN': chord(17), 'secondNoteSave': CHORD, 'editSelectAll': chord(4), 'editedNoteSave': CHORD},
    WORKSPACE: {'capture': chord(17), 'saveNew': CHORD, 'select': chord(81), 'edit': chord(8), 'saveEdit': CHORD, 'complete': chord(40, shift=True), 'completedView': chord(33)},
}
BOUNDARY = re.compile(rb"^Test Case '-\[(?:TskUITests\.)?(\w+) (\w+)\]' (started\.|(passed|failed|skipped) \([\d.,]+ seconds\)\.)$")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate protocol field')
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError('Nonfinite protocol value: ' + value)


def decode(raw):
    return json.loads(raw, object_pairs_hook=unique_object, parse_constant=reject_constant)


def identifier(raw):
    if not isinstance(raw, str) or str(uuid.UUID(raw)) != raw:
        raise ValueError('Expected canonical lowercase UUID')
    return raw


def validate_request(request, expected_token):
    expected = {'version', 'owner', 'attempt', 'request', 'caseName', 'phase', 'sequence', 'runnerPID', 'runnerBundleID', 'replica', 'expiresAt'}
    if not isinstance(request, dict):
        raise ValueError('Expected request object')
    native = request.get('caseName') == CASE
    if set(request) != expected | ({'nativeState'} if native else set()):
        raise ValueError('Unexpected request fields')
    for key in ['owner', 'attempt', 'request', 'replica']:
        identifier(request[key])
    if request['owner'] != identifier(expected_token):
        raise ValueError('Request owner does not match this run')
    if type(request['version']) is not int or request['version'] != 1 or request['runnerBundleID'] != RUNNER:
        raise ValueError('Unexpected protocol or runner')
    if type(request['runnerPID']) is not int or not 0 < request['runnerPID'] <= 2_147_483_647:
        raise ValueError('Invalid runner PID')
    if type(request['sequence']) is not int or not 0 <= request['sequence'] < 7:
        raise ValueError('Invalid request sequence')
    if type(request['expiresAt']) not in (int, float) or not math.isfinite(request['expiresAt']):
        raise ValueError('Invalid request expiry')
    if request['caseName'] not in CHORDS or request['phase'] not in CHORDS[request['caseName']]:
        raise ValueError('Unexpected case or phase')
    if native:
        state = request['nativeState']
        values = {'firstResponder': True, 'textLength': 1, 'textIsPlainN': True, 'commandNCount': 1, 'commandReturnCount': 0}
        if not isinstance(state, dict) or set(state) != {'processID', *values}:
            raise ValueError('Unexpected native state fields')
        if type(state['processID']) is not int or not 0 < state['processID'] <= 2_147_483_647 or any(type(state[key]) is not type(value) or state[key] != value for key, value in values.items()):
            raise ValueError('Native focus or input baseline is not ready')
    return request


def parse_marker(line, expected_token, prefix=PREFIX):
    if prefix not in line:
        return None
    if line.count(prefix) != 1 or not line.endswith(b'\n'):
        raise ValueError('Ambiguous or truncated protocol marker')
    before, payload = line.split(prefix, 1)
    if len(before) > 256 or len(payload.rstrip(b'\r\n')) > 2048:
        raise ValueError('Protocol marker exceeds its byte budget')
    return validate_request(decode(payload), expected_token)


class MarkerReader:
    def __init__(self, expected_token):
        self.expected_token = expected_token
        self.buffer = b''
        self.discarding = False

    def feed(self, chunk):
        lines = []
        for part in chunk.splitlines(keepends=True):
            self.buffer += part
            if len(self.buffer) > 65536:
                if PREFIX in self.buffer or ABORT in self.buffer:
                    raise ValueError('Oversized protocol marker')
                self.buffer = b''
                self.discarding = True
            if part.endswith(b'\n'):
                if not self.discarding:
                    lines.append(self.buffer.rstrip(b'\r\n'))
                self.buffer = b''
                self.discarding = False
        return lines

    def finish(self):
        if self.buffer and (PREFIX in self.buffer or ABORT in self.buffer or PREFIX.startswith(self.buffer) or ABORT.startswith(self.buffer)):
            raise ValueError('Truncated protocol marker')


class ArmedLog:
    def __init__(self, path, token):
        self.path = pathlib.Path(path)
        self.file = self.path.open('rb', buffering=0)
        info = os.fstat(self.file.fileno())
        if not stat.S_ISREG(info.st_mode):
            self.file.close()
            raise ValueError('Live log must be a regular file')
        self.identity = (info.st_dev, info.st_ino)
        self.file.seek(0, os.SEEK_END)
        self.start_offset = self.file.tell()
        self.reader = MarkerReader(token)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.file.close()

    def poll(self):
        info = self.path.stat()
        if (info.st_dev, info.st_ino) != self.identity or info.st_size < self.file.tell():
            raise ValueError('Armed log was replaced or truncated')
        return self.reader.feed(self.file.read(4096))


class Protocol:
    def __init__(self, token):
        self.token = identifier(token)
        self.active = None
        self.pending = None
        self.cases = {}
        self.requests = set()

    def line(self, raw):
        boundary = BOUNDARY.fullmatch(raw)
        if boundary:
            suite, method, outcome, result = boundary.groups()
            name = suite.decode() + '/' + method.decode()
            if outcome == b'started.':
                if self.active is not None or self.pending is not None or name in self.cases:
                    raise ValueError('Overlapping or repeated XCTest case')
                self.active = name
                if name in CHORDS:
                    self.cases[name] = dict(completed=[], attempt=None, result=None)
            else:
                if self.active != name or self.pending is not None:
                    raise ValueError('Unexpected XCTest case completion')
                if name in CHORDS:
                    record = self.cases[name]
                    record['result'] = result.decode()
                    if result == b'passed' and record['completed'] != list(CHORDS[name]):
                        raise ValueError('Passed keyboard case lacks its complete command sequence')
                self.active = None
            return None
        if ABORT in raw:
            request = parse_marker(raw + b'\n', self.token, ABORT)
            raise ValueError('Runner aborted HID request: ' + request['request'])
        request = parse_marker(raw + b'\n', self.token)
        if request is None:
            return None
        name = request['caseName']
        if self.active != name or self.pending is not None or request['request'] in self.requests:
            raise ValueError('Inactive, overlapping or replayed HID request')
        record = self.cases[name]
        index = len(record['completed'])
        if request['sequence'] != index or index >= len(CHORDS[name]) or request['phase'] != list(CHORDS[name])[index]:
            raise ValueError('Out-of-order HID request')
        binding = {key: request[key] for key in ['attempt', 'runnerPID', 'runnerBundleID', 'replica']}
        if record['attempt'] is not None and record['attempt'] != binding:
            raise ValueError('Case attempt identity changed')
        record['attempt'] = binding
        self.pending = request
        self.requests.add(request['request'])
        return request

    def acknowledged(self, request):
        if request != self.pending:
            raise ValueError('Acknowledgement is not for the active request')
        self.cases[request['caseName']]['completed'].append(request['phase'])
        self.pending = None

    def finish(self):
        if self.pending is not None or self.active is not None:
            raise ValueError('Incomplete XCTest case or HID exchange')


def releases(events):
    return tuple((code, direction) for code, direction in events if direction == 'UP')


async def dispatch_chord(send, events=CHORD):
    try:
        await asyncio.wait_for(send(events), timeout=5)
    except BaseException as error:
        cleanup = asyncio.create_task(asyncio.wait_for(send(releases(events)), timeout=5))
        try:
            await asyncio.shield(cleanup)
            error.add_note('HID UP cleanup RPC completed; native key state remains unverified')
        except BaseException as cleanup_error:
            error.add_note('HID UP cleanup unconfirmed: ' + repr(cleanup_error))
        raise


def make_sender(socket):
    if importlib.metadata.version('fb-idb') != '1.7.3':
        raise ValueError('Pinned fb-idb 1.7.3 is required')
    from idb.common.types import DomainSocketAddress, HIDDirection, HIDKey, HIDPress
    from idb.grpc.client import Client

    async def send(events):
        presses = [HIDPress(action=HIDKey(keycode=code), direction=getattr(HIDDirection, direction)) for code, direction in events]
        async with Client.build(address=DomainSocketAddress(path=socket), logger=logging.getLogger('owned-native-hid'), exchange_metadata=False) as client:
            await client.send_events(presses)

    return send


def save_receipt(path, receipt):
    temporary = path.with_name(path.name + '.' + str(os.getpid()) + '.tmp')
    with temporary.open('w') as file:
        json.dump(receipt, file, indent=2)
        file.write('\n')
        file.flush()
        os.fsync(file.fileno())
    temporary.replace(path)


class Exchange:
    def __init__(self, container, request):
        self.request = request
        self.directory = os.open(container, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            for component in ['Documents', 'TSKHID', request['owner'], request['attempt']]:
                child = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=self.directory)
                os.close(self.directory)
                self.directory = child
        except BaseException:
            self.close()
            raise
        self.name = request['request']

    def close(self):
        os.close(self.directory)

    def exists(self, suffix):
        try:
            os.stat(self.name + suffix, dir_fd=self.directory, follow_symlinks=False)
            return True
        except FileNotFoundError:
            return False

    def verify(self, now):
        remaining = self.request['expiresAt'] - now
        if not 0 < remaining <= 12 or self.exists('.abort.json') or self.exists('.ack.json'):
            raise ValueError('Expired, aborted or already acknowledged request')
        descriptor = os.open(self.name + '.request.json', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.directory)
        with os.fdopen(descriptor, 'rb') as file:
            info = os.fstat(file.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > 2048:
                raise ValueError('Request must be a bounded regular file')
            raw = file.read(2049)
        if len(raw) > 2048 or validate_request(decode(raw), self.request['owner']) != self.request:
            raise ValueError('Runner request file does not match its marker')

    def acknowledge(self, now):
        self.verify(now)
        temporary = self.name + '.' + str(uuid.uuid4()) + '.tmp'
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=self.directory)
        try:
            with os.fdopen(descriptor, 'wb') as file:
                file.write(json.dumps(dict(request=self.request, state='transportComplete'), allow_nan=False).encode())
                file.flush()
                os.fsync(file.fileno())
            os.rename(temporary, self.name + '.ack.json', src_dir_fd=self.directory, dst_dir_fd=self.directory)
        finally:
            try:
                os.unlink(temporary, dir_fd=self.directory)
            except FileNotFoundError:
                pass


async def container_for(udid, request, receipt):
    command = ['xcrun', 'simctl', 'get_app_container', udid, RUNNER, 'data']
    process = await asyncio.create_subprocess_exec(*command, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    entry = dict(command=command, pid=process.pid)
    receipt.setdefault('containerLookups', []).append(entry)
    try:
        raw, error = await asyncio.wait_for(process.communicate(), timeout=2)
        entry['status'] = process.returncode
        if process.returncode or len(raw) > 4096:
            raise ValueError('Owned runner container lookup failed')
        path = pathlib.Path(raw.decode().strip())
        if not path.is_absolute():
            raise ValueError('Owned runner container is not absolute')
        entry['path'] = str(path)
        return path
    finally:
        if process.returncode is None:
            process.kill()
        await asyncio.wait_for(process.wait(), timeout=5)


async def run(args):
    receipt_path = pathlib.Path(args.receipt)
    with receipt_path.open('x'):
        pass
    protocol = Protocol(args.relay_token)
    receipt = dict(state='preparing', udid=args.udid, socket=args.socket, companionPID=args.companion_pid, relayToken=args.relay_token, cases=protocol.cases, exchanges=[])
    save_receipt(receipt_path, receipt)
    task = asyncio.current_task()
    loop = asyncio.get_running_loop()
    loop.add_signal_handler(signal.SIGTERM, task.cancel)
    try:
        if not stat.S_ISSOCK(pathlib.Path(args.socket).stat().st_mode):
            raise ValueError('Explicit companion address must be a Unix socket')
        send = make_sender(args.socket)
        with ArmedLog(args.log, args.relay_token) as log:
            receipt.update(state='waiting', logStartOffset=log.start_offset)
            save_receipt(receipt_path, receipt)
            containers = {}
            while True:
                lines = log.poll()
                while lines:
                    raw = lines.pop(0)
                    request = protocol.line(raw)
                    if request is None:
                        continue
                    for following in lines:
                        protocol.line(following)
                    lines.clear()
                    binding = (request['caseName'], request['attempt'])
                    if binding not in containers:
                        containers[binding] = await container_for(args.udid, request, receipt)
                    exchange = Exchange(containers[binding], request)
                    try:
                        end = log.path.stat().st_size
                        while log.file.tell() < end:
                            for following in log.poll():
                                protocol.line(following)
                        exchange.verify(time.time())
                        events = CHORDS[request['caseName']][request['phase']]
                        exchange_record = dict(request=request, events=events, startedMonotonic=time.monotonic())
                        receipt['exchanges'].append(exchange_record)
                        receipt.update(state='sending', inFlight=request, transportComplete=False)
                        save_receipt(receipt_path, receipt)
                        await dispatch_chord(send, events)
                        exchange_record.update(transportComplete=True, rpcDurationSeconds=time.monotonic() - exchange_record['startedMonotonic'])
                        receipt['transportComplete'] = True
                        save_receipt(receipt_path, receipt)
                        end = log.path.stat().st_size
                        while log.file.tell() < end:
                            for following in log.poll():
                                protocol.line(following)
                        exchange.acknowledge(time.time())
                        protocol.acknowledged(request)
                        exchange_record['acknowledgedAtEpoch'] = time.time()
                        receipt.update(state='waiting', inFlight=None)
                        save_receipt(receipt_path, receipt)
                    finally:
                        exchange.close()
                if pathlib.Path(args.stop_file).exists():
                    if log.file.tell() < log.path.stat().st_size:
                        continue
                    log.reader.finish()
                    protocol.finish()
                    receipt.update(state='completed_native_assertions_required')
                    save_receipt(receipt_path, receipt)
                    return
                await asyncio.sleep(0.01)
    except BaseException as error:
        receipt.update(state='failed', error=repr(error), notes=getattr(error, '__notes__', []))
        save_receipt(receipt_path, receipt)
        raise
    finally:
        loop.remove_signal_handler(signal.SIGTERM)


def parse_args():
    parser = argparse.ArgumentParser()
    for name in ['log', 'socket', 'udid', 'relay-token', 'receipt', 'stop-file']:
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--companion-pid', required=True, type=int)
    args = parser.parse_args()
    identifier(args.relay_token)
    uuid.UUID(args.udid)
    if args.companion_pid <= 0:
        parser.error('Owned companion PID must be positive')
    if not all(pathlib.Path(value).is_absolute() for value in [args.log, args.socket, args.receipt, args.stop_file]):
        parser.error('Owned paths must be explicit and absolute')
    return args


if __name__ == '__main__':
    try:
        asyncio.run(run(parse_args()))
    except BaseException as error:
        if isinstance(error, SystemExit):
            raise
        print('Native HID relay failed: ' + repr(error), file=sys.stderr, flush=True)
        raise SystemExit(1)
