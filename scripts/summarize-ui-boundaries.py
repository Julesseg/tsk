import collections
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import uuid


PREFIX = b'TSK_BOUNDARY_SUMMARY_V1 '
UUID = r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}'
PATTERNS = {
    'participant': re.compile(rf'participant-fixture-(?:missed-notifications-)?({UUID})-([1-9][0-9]{{0,9}})\.json'),
    'readback': re.compile(rf'reminders-fixture-authorization-({UUID})-([1-9][0-9]{{0,9}})\.json'),
}
LIMITS = {'files': 128, 'file': 1048576, 'input': 8388608, 'output': 131072, 'line': 2048, 'family': 32768, 'reserve': 4096}
STAGES = set('''reminders.access reminders.access.begin reminders.access.callback reminders.access.returned reminders.access.error reminders.access.rejected reminders.access.publication-sample reminders.lists.begin reminders.lists.returned reminders.fixture.prepare.begin reminders.fixture.prepare.error reminders.fixture.removal.begin reminders.fixture.removal.returned reminders.recurring-fixture.prepare.begin reminders.move.removal.begin calendar.authorization calendar.access.begin calendar.access.callback calendar.access.returned calendar.access.error calendar.refresh.begin calendar.refresh.snapshot calendar.refresh.discarded calendar.refresh.published calendar.scene'''.split())


def number(value):
    return integer(value) or type(value) is float and math.isfinite(value)


def authorization(value):
    return integer(value) or type(value) is str and value in ('notDetermined', 'restricted', 'denied', 'writeOnly', 'fullAccess', 'authorized', 'unavailable')


def integer(value):
    return type(value) is int and abs(value) <= 2**53


def identifier(value):
    return type(value) is str and re.fullmatch(UUID, value) is not None


def boolean(value):
    return type(value) is bool


def fields(source, validators, counts, native_strings=False):
    if type(source) is not dict:
        counts['invalid'] += 1
        return {}
    result = {}
    for key, value in source.items():
        validate = validators.get(key)
        if validate is None:
            counts['omittedFields'] += 1
            continue
        if native_strings and type(value) is str:
            if validate is boolean and value in ('true', 'false'):
                value = value == 'true'
            elif validate in (integer, authorization) and re.fullmatch(r'-?(?:0|[1-9][0-9]{0,15})', value):
                value = int(value)
        if validate(value): result[key] = value
        else: counts['invalid'] += 1
    return result


DETAILS = dict.fromkeys(['store', 'request', 'generation'], identifier)
DETAILS.update(dict.fromkeys(['checkedAuthorization', 'count', 'errorCode'], integer))
DETAILS['authorization'] = authorization
DETAILS.update(dict.fromkeys(['granted', 'mainThread', 'requestingAccess', 'hasReadError'], boolean))
DETAILS['mappedAuthorization'] = lambda value: value in ('notDetermined', 'restricted', 'denied', 'writeOnly', 'fullAccess', 'authorized', 'unavailable') if type(value) is str else False
DETAILS['phase'] = lambda value: value in ('active', 'inactive', 'background') if type(value) is str else False
DETAILS['errorDomain'] = lambda value: value in ('EKErrorDomain', 'NSCocoaErrorDomain', 'NSPOSIXErrorDomain', 'NSURLErrorDomain', 'tsk.EventKitFixture') if type(value) is str else False


def eventkit(payload, pid, counts):
    if type(payload) is not dict or type(payload.get('events')) is not list:
        counts['invalid'] += 1
        return []
    result = []
    for event in payload['events']:
        if type(event) is not dict or type(event.get('stage')) is not str or event.get('stage') not in STAGES:
            counts['filteredRecords'] += 1
            continue
        if type(event.get('processID')) is not int or event['processID'] != pid:
            counts['invalid'] += 1
            continue
        row = fields(event, {'stage': lambda v: type(v) is str and v in STAGES, 'phase': lambda v: v in ('begin', 'event', 'end'), 'id': identifier, 'time': number, 'processID': integer}, counts)
        row['kind'] = 'eventkit'
        if 'details' in event: row['details'] = fields(event['details'], DETAILS, counts, native_strings=True)
        result.append(row)
    result.sort(key=lambda row: (0 if row.get('stage', '').endswith('.callback') else 1 if row.get('stage', '').endswith('.returned') else 2 if row.get('stage', '').endswith('.publication-sample') else 3, row.get('time', 0)))
    return result


def readback(payload, pid, counts):
    if type(payload) is not dict or type(payload.get('processID')) is not int or payload['processID'] != pid:
        counts['invalid'] += 1
        return []
    validators = dict.fromkeys(['processID', 'authorization', 'authorizationAfterRead', 'ownedCalendarCount', 'ownedReminderCount'], integer)
    validators.update(dict.fromkeys(['time', 'finishedTime'], number))
    validators.update(dict.fromkeys(['fetchStarted', 'fetchReturnedNonNil', 'timedOut', 'cancelRequested'], boolean))
    validators['stage'] = lambda v: v == 'fresh-process-before-cleanup'
    return [dict(kind='eventkit-readback', **fields(payload, validators, counts))]


def summarize(directory, limits=None):
    limits = dict(LIMITS, **(limits or {}))
    counts = collections.Counter(dict(discovered=0, read=0, invalid=0, symlink=0, oversize=0, capped=0, omittedFields=0, omittedRecords=0, filteredRecords=0))
    buckets = {kind: [] for kind in PATTERNS}
    families = {kind: collections.Counter(discovered=0, read=0, omittedFiles=0, omittedRows=0) for kind in PATTERNS}
    try:
        with os.scandir(directory) as entries:
            for index, entry in enumerate(entries):
                if index >= 4096:
                    counts['capped'] += 1
                    break
                for kind, pattern in PATTERNS.items():
                    match = pattern.fullmatch(entry.name)
                    if match:
                        if int(match[2]) > 2**31 - 1:
                            counts['invalid'] += 1
                            break
                        counts['discovered'] += 1
                        families[kind]['discovered'] += 1
                        buckets[kind].append((entry.name, match[1], int(match[2])))
                        break
    except OSError:
        counts['invalid'] += 1
    queues = [collections.deque(sorted(values)) for values in buckets.values()]
    selected = []
    while any(queues):
        for kind, queue in zip(buckets, queues):
            if queue:
                name, token, pid = queue.popleft()
                if len(selected) < limits['files']: selected.append((kind, name, token, pid))
                else:
                    counts['capped'] += 1
                    families[kind]['omittedFiles'] += 1
    files = []
    used_input = 0
    for kind, name, token, pid in selected:
        path = Path(directory) / name
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        except OSError:
            if path.is_symlink(): counts['symlink'] += 1
            else: counts['invalid'] += 1
            continue
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode):
                counts['invalid'] += 1
                continue
            if info.st_size > limits['file'] or used_input + info.st_size > limits['input']:
                counts['oversize'] += 1
                continue
            with os.fdopen(descriptor, 'rb', closefd=False) as source:
                raw = source.read(min(limits['file'], limits['input'] - used_input) + 1)
            used_input += len(raw)
            if len(raw) > limits['file'] or used_input > limits['input']:
                counts['oversize'] += 1
                continue
            payload = json.loads(raw)
            rows = readback(payload, pid, counts) if kind == 'readback' else eventkit(payload, pid, counts)
            counts['read'] += 1
            families[kind]['read'] += 1
            source = {'replica': str(uuid.UUID(token)).upper(), 'processID': pid, 'sha256': hashlib.sha256(raw).hexdigest()}
            observed = payload if type(payload) is list else payload.get('events', []) if type(payload) is dict else []
            if type(observed) is not list: observed = []
            if kind == 'readback': observed = [payload]
            times = [v['time'] for v in observed if type(v) is dict and number(v.get('time'))]
            source['observedRows'] = len(observed)
            if times: source.update(firstTime=min(times), lastTime=max(times))
            files.append((kind, collections.deque([dict(row, source=source) for row in rows])))
        except (OSError, ValueError, RecursionError):
            counts['invalid'] += 1
        finally:
            os.close(descriptor)
    def line(row):
        return PREFIX + json.dumps(row, separators=(',', ':'), allow_nan=False).encode() + b'\n'
    provenance = {}
    for key, variable, pattern in [('commit', 'GITHUB_SHA', r'[0-9a-fA-F]{40}'), ('run', 'GITHUB_RUN_ID', r'[0-9]{1,20}'), ('job', 'GITHUB_JOB', r'[A-Za-z0-9_-]{1,80}')]:
        value = os.environ.get(variable, '')
        if re.fullmatch(pattern, value): provenance[key] = value
    lines = [line(dict(kind='header', schema=1, scope='owned-eventkit-authorization', **provenance))]
    total = len(lines[0])
    family_bytes = collections.Counter()
    while any(queue for _, queue in files):
        for kind, queue in files:
            if not queue: continue
            row = queue.popleft()
            encoded = line(row)
            family = 'eventkit'
            if len(encoded) > limits['line'] or family_bytes[family] + len(encoded) > limits['family'] or total + len(encoded) > limits['output'] - min(limits['reserve'], limits['output'] // 4):
                counts['capped'] += 1
                families[kind]['omittedRows'] += 1
                continue
            lines.append(encoded)
            total += len(encoded)
            family_bytes[family] += len(encoded)
    for kind, values in families.items():
        values['omittedFiles'] = values['discovered'] - values['read']
    inventory = line({'kind': 'inventory', 'complete': not any(counts[k] for k in ['invalid', 'symlink', 'oversize', 'capped']), 'counts': dict(counts), 'families': {kind: dict(values) for kind, values in families.items()}, 'inputBytes': used_input, 'emittedRows': len(lines) - 1})
    lines.append(inventory)
    return lines


def supervise(directory, timeout=5):
    child = None
    interrupted = None
    old = {}
    def stop(number, _frame):
        nonlocal interrupted
        interrupted = number
        if child is not None and child.poll() is None:
            try: child.kill()
            except ProcessLookupError: pass
    for number in (signal.SIGINT, signal.SIGTERM): old[number] = signal.signal(number, stop)
    try:
        child = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--emit', str(directory)], start_new_session=True)
        if interrupted is not None: child.kill()
        try:
            status = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
            return {'status': 124, 'childPID': child.pid, 'timedOut': True}
        return {'status': 128 + interrupted if interrupted else 128 - status if status < 0 else status, 'childPID': child.pid, 'timedOut': False}
    finally:
        if child is not None and child.poll() is None:
            child.kill()
            child.wait()
        for number, handler in old.items(): signal.signal(number, handler)


if __name__ == '__main__':
    if os.environ.get('CI') != 'true' or os.environ.get('TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR') != '1': raise SystemExit(0)
    if len(sys.argv) == 3 and sys.argv[1] == '--emit':
        try:
            for output in summarize(sys.argv[2]):
                while output:
                    written = os.write(1, output)
                    output = output[written:]
        except BrokenPipeError: raise SystemExit(141)
        except (OSError, ValueError, TypeError, RecursionError): raise SystemExit(1)
    elif len(sys.argv) == 2:
        try: status = supervise(sys.argv[1])['status']
        except OSError: status = 1
        raise SystemExit(status)
    else: raise SystemExit(2)
