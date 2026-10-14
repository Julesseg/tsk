import ctypes
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import uuid


def connect(library):
    native = ctypes.CDLL(library)
    native.tsk_tc_request.argtypes = [ctypes.c_char_p]
    native.tsk_tc_request.restype = ctypes.c_void_p
    native.tsk_tc_free.argtypes = [ctypes.c_void_p]
    return native


def request(native, value):
    output = native.tsk_tc_request(json.dumps(value, ensure_ascii=False).encode())
    try:
        return json.loads(ctypes.string_at(output))
    finally:
        native.tsk_tc_free(output)


if sys.argv[1] == 'worker':
    result = request(connect(sys.argv[2]), json.load(open(sys.argv[3])))
    pathlib.Path(sys.argv[4]).write_text(json.dumps(result))
    sys.exit(0)

library, backend, client, secret = sys.argv[1:]
native = connect(library)
root = pathlib.Path(tempfile.mkdtemp(prefix='tsk-process-admission-'))
print('Fixture:', root, flush=True)
attrs_pairs = os.environ.get('TSK_NATIVE_ATTRIBUTE_PAIRS') == '1'


def attributes(value):
    return [{'key': key, 'value': value} for key, value in value.items()] if attrs_pairs else value


def raw(record):
    value = record['attributes']
    return {entry['key']: entry['value'] for entry in value} if isinstance(value, list) else value


def invoke(path, command, **value):
    result = request(native, dict(path=str(path), command=command, **value))
    assert 'error' not in result, result
    return result['value']


def wait_file(path, process=None, timeout=15):
    deadline = time.monotonic() + timeout
    while not path.exists():
        assert time.monotonic() < deadline, ('Timed out', path)
        if process is not None:
            assert process.poll() is None, ('Process ended', process.returncode)
        time.sleep(0.01)


def worker(control, value):
    control.mkdir(parents=True, exist_ok=True)
    source = control / 'request.json'
    source.write_text(json.dumps(value))
    output = control / 'result.json'
    process = subprocess.Popen([sys.executable, __file__, 'worker', library, str(source), str(output)])
    return process, output


for method, kill in [('GET', False), ('POST', False), ('POST', True)]:
    case = root / (method + ('-death' if kill else '-interrupt'))
    control = case / 'proxy'
    control.mkdir(parents=True)
    proxy = subprocess.Popen([sys.executable, str(pathlib.Path(__file__).with_name('delayed-sync-proxy.py')), backend, str(control), method])
    owner = None
    try:
        wait_file(control / 'url', proxy)
        path = case / 'replica'
        identifier = str(uuid.uuid4())
        invoke(path, 'create', id=identifier, attributes=attributes({'description': 'Cross-process fixture', 'status': 'pending', 'opaque.fixture': 'untouched'}))
        config = dict(serverURL=(control / 'url').read_text(), clientID=client, encryptionSecret=secret)
        owner, output = worker(case / 'owner', dict(path=str(path), command='synchronize', configuration=config))
        wait_file(control / 'blocked.json', proxy)
        assert json.loads((control / 'blocked.json').read_text())['status'] == 200
        if kill:
            owner.kill()
            owner.wait(timeout=5)
        release_at = time.monotonic() + 5
        safety = subprocess.Popen([sys.executable, '-c', 'import pathlib,time,sys;time.sleep(5);pathlib.Path(sys.argv[1]).touch()', str(control / 'released')])
        try:
            started = time.monotonic()
            invoke(path, 'update', id=identifier, changes=attributes({'description': 'Durable second-process edit'}))
            elapsed = time.monotonic() - started
            assert elapsed < 2, ('Local write waited for network', method, kill, elapsed)
            assert not (control / 'released').exists(), 'Local acknowledgement required releasing HTTP response'
            if not kill:
                owner.wait(timeout=3)
                assert json.loads(output.read_text()) == {'error': 'TSK_SYNC_INTERRUPTED'}
            (control / 'released').touch()
            invoke(path, 'synchronize', configuration=dict(config, serverURL=backend))
            peer = case / 'peer'
            invoke(peer, 'synchronize', configuration=dict(config, serverURL=backend))
            records = [record for record in invoke(peer, 'tasks') if record['id'] == identifier]
            assert len(records) == 1, records
            assert raw(records[0])['description'] == 'Durable second-process edit'
            assert raw(records[0])['opaque.fixture'] == 'untouched'
            print(method, 'owner death' if kill else 'interruption', 'acknowledged in', round(elapsed, 3), 'seconds; UUID/opaque convergence passed', flush=True)
        finally:
            safety.terminate()
            safety.wait()
    finally:
        (control / 'released').touch()
        if owner is not None and owner.poll() is None:
            owner.kill()
            owner.wait()
        proxy.terminate()
        proxy.wait()

print('All isolated multiprocess admission scenarios passed', flush=True)
