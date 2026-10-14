import argparse
import json
import os
import pathlib
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--server', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--verify-peer')
parser.add_argument('command', nargs=argparse.REMAINDER)
options = parser.parse_args()
command = options.command[1:] if options.command[:1] == ['--'] else options.command
if not command:
    parser.error('Pass the test command after --')
binary = pathlib.Path(options.server).resolve()
version = subprocess.check_output([str(binary), '--version'], text=True).strip()
if version != 'taskchampion-sync-server 0.7.1':
    raise SystemExit('The isolated fixture requires taskchampion-sync-server 0.7.1')
output = pathlib.Path(options.output).resolve()
output.mkdir(parents=True, exist_ok=True)
fixture = pathlib.Path(tempfile.mkdtemp(prefix='run-', dir=output))
with socket.socket() as reservation:
    reservation.bind(('127.0.0.1', 0))
    port = reservation.getsockname()[1]
client = str(uuid.uuid4())
secret = 'tsk-isolated-ui-' + str(uuid.uuid4())
url = 'http://127.0.0.1:' + str(port)
settings = {'TSK_UI_SYNC_SERVER_URL': url, 'TSK_UI_SYNC_CLIENT_ID': client, 'TSK_UI_SYNC_SECRET': secret,
            'TSK_UI_SYNC_FIXTURE_TOKEN': str(uuid.uuid4())}
environment = dict(os.environ)
for key, value in settings.items():
    environment[key] = value
    environment['TEST_RUNNER_' + key] = value
for suffix, source in [('URL', 'SERVER_URL'), ('CLIENT_ID', 'CLIENT_ID'), ('SECRET', 'SECRET')]:
    environment['TSK_SYNC_TEST_' + suffix] = settings['TSK_UI_SYNC_' + source]
server_environment = dict(os.environ)
for name in ['LISTEN', 'DATA_DIR', 'CLIENT_ID', 'CREATE_CLIENTS', 'SNAPSHOT_VERSIONS', 'SNAPSHOT_DAYS']:
    server_environment.pop(name, None)
server_environment['RUST_LOG'] = 'info'
server = None
tests = None

def interrupted(number, frame):
    raise KeyboardInterrupt()

signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)

try:
    with (fixture / 'server.log').open('w') as log:
        server = subprocess.Popen([str(binary), '--listen', '127.0.0.1:' + str(port), '--data-dir', str(fixture / 'data'), '--allow-client-id', client], stdout=log, stderr=log, env=server_environment)
        deadline = time.monotonic() + 20
        while True:
            if server.poll() is not None:
                raise RuntimeError('The real fixture server exited; inspect ' + str(fixture / 'server.log'))
            try:
                with urllib.request.urlopen(url, timeout=1) as response:
                    if response.read().decode() != 'TaskChampion sync server v0.7.1':
                        raise RuntimeError('Unexpected real server readiness response')
                break
            except urllib.error.URLError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('The real fixture server did not become ready')
                time.sleep(0.05)
        (fixture / 'fixture.json').write_text(json.dumps({'serverURL': url, 'clientID': client, 'token': settings['TSK_UI_SYNC_FIXTURE_TOKEN'], 'version': version, 'serverPID': server.pid}, indent=2))
        print('Real isolated sync fixture ready at ' + url + '; evidence ' + str(fixture), flush=True)
        tests = subprocess.Popen(command, env=environment, start_new_session=True)
        status = tests.wait()
        if status == 0 and options.verify_peer:
            environment['TSK_UI_SYNC_PEER_DIRECTORY'] = str(fixture / 'peer')
            environment['TSK_UI_SYNC_PEER_PROOF'] = str(fixture / 'peer-proof.json')
            tests = subprocess.Popen([str(pathlib.Path(options.verify_peer).resolve()), 'verify-ui-sync'], env=environment, start_new_session=True)
            status = tests.wait()
        raise SystemExit(status)
finally:
    for process in [tests, server]:
        if process is not None and process.poll() is None:
            if process is tests:
                os.killpg(process.pid, signal.SIGTERM)
            else:
                process.terminate()
            try:
                process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                if process is tests:
                    os.killpg(process.pid, signal.SIGKILL)
                else:
                    process.kill()
                process.wait()
    (fixture / 'stopped').touch()
