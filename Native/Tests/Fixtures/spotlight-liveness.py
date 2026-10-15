import json
import fcntl
import os
import pathlib
import subprocess
import sys
import tempfile
import time


probe, library = sys.argv[1:3]
proof = []
processes = []
environment = dict(os.environ, TSK_TASKCHAMPION_LIBRARY=library)


def wait_until(predicate, message, process=None):
    deadline = time.monotonic() + 5
    while not predicate():
        assert time.monotonic() < deadline, message
        if process is not None:
            assert process.poll() is None, (message, process.returncode)
        time.sleep(0.01)


def read(path):
    return json.loads(path.read_text())


def start(root, replica, mode, released=False):
    control = root / mode
    control.mkdir()
    if released:
        (control / 'release').touch()
    output = control / 'ack.json'
    process = subprocess.Popen([probe, 'spotlight-worker', str(replica), str(control), str(output), mode], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    processes.append(process)
    wait_until(output.exists, ('No public task acknowledgement', mode), process)
    assert 'error' not in read(output), read(output)
    return process, control, read(output)


def settled(replica):
    state = read(replica / 'spotlight-status.json')
    revision = read(replica / 'participant-changes.json')['tasks']
    return state.get('attempt') is None and state.get('error') is None and state.get('confirmedRevision') == revision and state.get('requestedRepair') == state.get('confirmedRepair')


try:
    with tempfile.TemporaryDirectory(prefix='tsk-spotlight-process-') as temporary:
        root = pathlib.Path(temporary)
        for death in [False, True]:
            case = root / ('death' if death else 'late-callback')
            case.mkdir()
            replica = case / 'replica'
            owner, first, a = start(case, replica, 'create')
            wait_until((first / 'entered').exists, 'First index operation never entered', owner)
            if death:
                participant, second, b = start(case, replica, 'participant')
                assert not (second / 'entered').exists(), 'Ordinary extension must not confirm the containing app index'
                owner.kill()
                owner.wait(timeout=5)
                assert read(replica / 'spotlight-status.json').get('attempt'), 'Unconfirmed attempt must survive worker death'
                recovering, recovery, ack = start(case, replica, 'recover', released=True)
                wait_until(lambda: settled(replica), 'New process did not reconcile unconfirmed work', recovering)
                projected = read(recovery / 'projection.json')
                assert {item['id'] for item in projected} == {a['saved'], b['saved']}, projected
                proof.append(dict(case='owner-death', first=a, participant=b, recovery=ack, projection=projected, status=read(replica / 'spotlight-status.json')))
            else:
                writer, second, b = start(case, replica, 'mutate')
                assert not (second / 'entered').exists(), 'A second process submitted while the first callback still owned admission'
                assert read(first / 'calls.json') == 1
                with (replica / '.tsk-spotlight-index').open('r+') as lock:
                    try:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        pass
                    else:
                        raise AssertionError('Callback owner released the actual cross-process lock early')
                (first / 'release').touch()
                wait_until(lambda: settled(replica), 'Latest cross-process task state never settled')
                projected = read(first / 'projection.json')
                assert len(projected) == 1 and projected[0]['id'] == b['saved'], projected
                assert projected[0]['title'] == 'Latest cross-process projection', projected
                proof.append(dict(case='late-callback', first=a, writer=b, projection=projected, status=read(replica / 'spotlight-status.json')))
            for child in processes:
                if child.poll() is None:
                    child.terminate()
                    child.wait(timeout=5)
            processes.clear()
        case = root / 'failure-publication'
        case.mkdir()
        replica = case / 'replica'
        failing, first, a = start(case, replica, 'create')
        wait_until((first / 'entered').exists, 'Failing index operation never entered', failing)
        with (replica / '.tsk-spotlight-state').open('r+') as state_gate:
            fcntl.flock(state_gate, fcntl.LOCK_EX)
            (first / 'fail').touch()
            (first / 'release').touch()
            wait_until((first / 'failed').exists, 'Controlled failure never returned', failing)
            time.sleep(0.1)
            with (replica / '.tsk-spotlight-index').open('r+') as operation_gate:
                try:
                    fcntl.flock(operation_gate, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    pass
                else:
                    raise AssertionError('Failed worker released ownership before publishing its delayed error')
            fcntl.flock(state_gate, fcntl.LOCK_UN)
        wait_until(lambda: read(replica / 'spotlight-status.json').get('error') is not None, 'Genuine index failure was not published', failing)
        recovering, recovery, ack = start(case, replica, 'recover', released=True)
        wait_until(lambda: settled(replica), 'New worker did not replace the failed attempt with a clean receipt', recovering)
        confirmation = read(replica / 'spotlight-status.json')
        time.sleep(0.1)
        assert read(replica / 'spotlight-status.json') == confirmation, 'Older failed worker overwrote a newer confirmation'
        proof.append(dict(case='failure-publication', first=a, recovery=ack, status=confirmation))
        print(json.dumps(proof, indent=2))
finally:
    for child in processes:
        if child.poll() is None:
            child.kill()
            child.wait(timeout=5)
