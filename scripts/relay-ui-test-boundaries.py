#!/usr/bin/env python3
import argparse
import array
import datetime
import fcntl
import json
import os
import pathlib
import re
import selectors
import signal
import subprocess
import sys
import termios
import time


SPOTLIGHT_METHODS = {
    'testReceivedEncryptedPeerCompletionReconcilesActualIndex',
    'testStaleRealSystemResultReportsUnavailableAndNeverOpensAnotherTask',
    'testSystemSpotlightOpensExactTaskAndLocalCompletionRemovesIndexEntry',
}
WIDGET_METHOD = 'testInstalledWidgetRendersTodayCompletesAndUsesSavedViewWithTruthfulDeletionError'
CASE = re.compile(r"^Test Case '-\[TskUITests\.(SpotlightUITests|WidgetUITests) (\w+)\]' (started\.|(?:passed|failed) \([\d.,]+ seconds\)\.)$")
POST_PARENT_EXIT_DRAIN_SECONDS = 0.25
POST_GROUP_SIGNAL_DRAIN_SECONDS = 0.25
SEARCH_SURFACE = re.compile(r"^\s*t =\s*[\d.,]+s Added attachment named 'Actual system Search surface before first-run handling'$")
PROVIDER = re.compile(r"^\s*t =\s*[\d.,]+s Added attachment named 'Actual tsk provider cell in native widget gallery'$")


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


class BoundaryCapture:
    def __init__(self, device, evidence, scripts):
        self.device = device
        self.evidence = pathlib.Path(evidence)
        self.scripts = pathlib.Path(scripts)
        self.children = []
        self.events = []
        self.started = set()
        self.active = {}
        self.widget_active = False
        self.widget_contexts = set()
        self.remote_pids = set()
        self.remote_pids_truncated = False
        self.spotlight_current = None
        self.spotlight_pids = {}
        self.spotlight_pids_truncated = set()
        self.search_contexts = set()
        try:
            self.evidence.mkdir(parents=True, exist_ok=True)
        except OSError as error:
            self.record('evidence-directory-error', error=str(error))

    def record(self, event, **fields):
        self.events.append(dict(event=event, receivedUTC=utc(), **fields))

    def spawn(self, arguments, kind, key, stop=None):
        entry = dict(kind=kind, key=key, startedUTC=utc(), arguments=arguments, stop=stop)
        try:
            output = (self.evidence / ('boundary-' + key + '-helper.txt')).open('wb')
            try:
                process = subprocess.Popen(arguments, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            finally:
                output.close()
            entry.update(process=process, pid=process.pid)
            self.children.append(entry)
            return entry
        except OSError as error:
            self.record('helper-start-error', kind=kind, key=key, error=str(error))
            return None

    def stop(self, method, reason):
        entry = self.active.pop(method, None)
        if entry:
            try:
                pathlib.Path(entry['stop']).touch()
            except OSError as error:
                self.record('stop-file-error', method=method, error=str(error))
            self.record('spotlight-window-stop', method=method, reason=reason)

    def widget_context(self, name):
        if name in self.widget_contexts:
            return
        self.widget_contexts.add(name)
        arguments = [sys.executable, str(self.scripts / 'capture-simulator-search-context.py'), self.device,
                     str(self.evidence / (name + '-context.json'))]
        for pid in sorted(self.remote_pids):
            arguments += ['--observed-pid', pid]
        self.record('widget-context-request', name=name, observedPIDs=sorted(self.remote_pids))
        self.spawn(arguments, 'context', name)

    def search_context(self, method, boundary):
        key = method + '-' + boundary
        if key in self.search_contexts:
            return
        self.search_contexts.add(key)
        pids = sorted(self.spotlight_pids.get(method, set()))
        name = 'spotlight-' + key
        arguments = [sys.executable, str(self.scripts / 'capture-simulator-search-context.py'), self.device,
                     str(self.evidence / (name + '-context.json'))]
        for pid in pids:
            arguments += ['--observed-pid', pid]
        self.record('spotlight-context-request', method=method, boundary=boundary, observedPIDs=pids)
        self.spawn(arguments, 'context', name)

    def line(self, raw):
        line = raw.decode('utf-8', errors='replace').rstrip('\r')
        match = CASE.fullmatch(line)
        if match:
            suite, method, outcome = match.groups()
            if suite == 'SpotlightUITests' and method in SPOTLIGHT_METHODS:
                if outcome == 'started.':
                    if method in self.started:
                        self.record('duplicate-start', method=method)
                    else:
                        self.started.add(method)
                        self.spotlight_current = method
                        self.spotlight_pids[method] = set()
                        self.search_context(method, 'method-start')
                        stop = self.evidence / ('spotlight-' + method + '.stop')
                        try:
                            stop.unlink(missing_ok=True)
                        except OSError as error:
                            self.record('stop-file-error', method=method, error=str(error))
                            return
                        self.record('spotlight-window-start', method=method)
                        entry = self.spawn([sys.executable, str(self.scripts / 'capture-simulator-spotlight-log.py'), self.device,
                                            str(self.evidence / ('spotlight-' + method + '.log')), str(stop), '--maximum-seconds', '600', '--sample-index-wait'], 'spotlight', method, str(stop))
                        if entry:
                            self.active[method] = entry
                else:
                    self.record('test-end', method=method, outcome=outcome)
                    if method in self.started:
                        self.search_context(method, 'method-end')
                    self.stop(method, 'test-end')
                    if self.spotlight_current == method:
                        self.spotlight_current = None
            elif suite == 'WidgetUITests' and method == WIDGET_METHOD:
                self.widget_active = outcome == 'started.'
                self.record('widget-test-boundary', outcome=outcome)
        if self.spotlight_current is not None:
            method = self.spotlight_current
            pids = self.spotlight_pids[method]
            for pid in re.findall(r'remote element in process (\d+)', line):
                if len(pids) < 32:
                    pids.add(pid)
                elif pid not in pids and method not in self.spotlight_pids_truncated:
                    self.spotlight_pids_truncated.add(method)
                    self.record('spotlight-observed-pids-truncated', method=method, maximum=32)
            if SEARCH_SURFACE.fullmatch(line):
                self.search_context(method, 'search-before')
            if ' : failed - Actual system Spotlight search field must be available' in line:
                self.search_context(method, 'search-missing-field')
        if self.widget_active:
            for pid in re.findall(r'remote element in process (\d+)', line):
                if len(self.remote_pids) < 32:
                    self.remote_pids.add(pid)
                elif pid not in self.remote_pids and not self.remote_pids_truncated:
                    self.remote_pids_truncated = True
                    self.record('widget-observed-pids-truncated', maximum=32)
            if PROVIDER.fullmatch(line):
                self.widget_context('widget-before-provider')
            if ' : failed - Missing native system control: Add Widget' in line:
                self.widget_context('widget-missing-add')
        self.reap()

    def reap(self):
        for entry in self.children:
            if 'returnCode' not in entry and entry['process'].poll() is not None:
                entry.update(returnCode=entry['process'].returncode, finishedUTC=utc())

    def finish(self, reason):
        for method in list(self.active):
            self.stop(method, reason)
        deadline = time.monotonic() + 20
        while any(entry['process'].poll() is None for entry in self.children) and time.monotonic() < deadline:
            self.reap()
            time.sleep(0.05)
        for entry in self.children:
            process = entry['process']
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)
                entry['forcedCleanup'] = True
        self.reap()
        return [dict((key, value) for key, value in entry.items() if key != 'process') for entry in self.children]


def run(command, device, evidence, scripts=pathlib.Path(__file__).parent, cleanup_grace=5):
    if cleanup_grace not in (5, 120):
        raise ValueError('Owned cleanup grace must be the default or fixed native HID allowance')
    capture = BoundaryCapture(device, evidence, scripts)
    process = None
    interrupted = None
    broken_output = False
    pending = b''
    discarding = False
    pipe_held_open = False
    old_handlers = {}

    def interrupt(number, _frame):
        nonlocal interrupted
        interrupted = number

    def signal_owned(number, include_exited=False):
        if process is not None and (include_exited or process.poll() is None):
            try:
                os.killpg(process.pid, number)
            except ProcessLookupError:
                pass

    def consume(chunk):
        nonlocal broken_output, interrupted, pending, discarding
        if not broken_output:
            try:
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
            except BrokenPipeError:
                broken_output = True
                interrupted = signal.SIGTERM
                with open(os.devnull, 'wb') as sink:
                    os.dup2(sink.fileno(), sys.stdout.fileno())
        pending += chunk
        while b'\n' in pending:
            line, pending = pending.split(b'\n', 1)
            if not discarding:
                try:
                    capture.line(line)
                except Exception as error:
                    capture.record('boundary-error', error=str(error))
            discarding = False
        if len(pending) > 65536:
            capture.record('oversized-line-ignored')
            pending = b''
            discarding = True

    for number in (signal.SIGINT, signal.SIGTERM):
        old_handlers[number] = signal.signal(number, interrupt)
    status = 1
    reason = 'relay-error'
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        capture.record('owned-native-hid-owner-start' if cleanup_grace == 120 else 'xcodebuild-start', pid=process.pid, command=command, **(dict(cleanupGraceSeconds=120) if cleanup_grace == 120 else {}))
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            signalled = False
            stop_deadline = None
            parent_exit_at = None
            group_signalled_at = None
            group_killed_at = None
            while selector.get_map():
                now = time.monotonic()
                if process.poll() is not None and parent_exit_at is None:
                    parent_exit_at = now
                    capture.record('parent-exit-observed', returnCode=process.returncode)
                if parent_exit_at is not None and now - parent_exit_at >= POST_PARENT_EXIT_DRAIN_SECONDS:
                    if group_signalled_at is None:
                        pipe_held_open = True
                        group_signalled_at = now
                        capture.record('inherited-pipe-held-open', returnCode=process.returncode, drainSeconds=POST_PARENT_EXIT_DRAIN_SECONDS)
                        signal_owned(signal.SIGTERM, include_exited=True)
                    elif group_killed_at is None and now - group_signalled_at >= POST_GROUP_SIGNAL_DRAIN_SECONDS:
                        group_killed_at = now
                        signal_owned(signal.SIGKILL, include_exited=True)
                    elif group_killed_at is not None and now - group_killed_at >= POST_GROUP_SIGNAL_DRAIN_SECONDS:
                        for key in list(selector.get_map().values()):
                            os.set_blocking(key.fileobj.fileno(), False)
                            buffered = array.array('i', [0])
                            fcntl.ioctl(key.fileobj.fileno(), termios.FIONREAD, buffered, True)
                            remaining = max(0, buffered[0])
                            while remaining:
                                chunk = os.read(key.fileobj.fileno(), min(65536, remaining))
                                if not chunk:
                                    break
                                consume(chunk)
                                remaining -= len(chunk)
                            selector.unregister(key.fileobj)
                            key.fileobj.close()
                            capture.record('inherited-pipe-drain-closed', bufferedBytes=buffered[0], unreadSnapshotBytes=remaining)
                        break
                if interrupted is not None and not signalled:
                    signal_owned(interrupted)
                    signalled = True
                    stop_deadline = time.monotonic() + cleanup_grace
                if stop_deadline is not None and time.monotonic() > stop_deadline:
                    signal_owned(signal.SIGKILL)
                for key, _ in selector.select(timeout=0.1):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        break
                    consume(chunk)
                capture.reap()
            if pending and not discarding:
                try:
                    capture.line(pending)
                except Exception as error:
                    capture.record('boundary-error', error=str(error))
        stop_deadline = None
        while process.poll() is None:
            if interrupted is not None:
                if stop_deadline is None:
                    signal_owned(interrupted)
                    stop_deadline = time.monotonic() + cleanup_grace
                elif time.monotonic() > stop_deadline:
                    signal_owned(signal.SIGKILL)
            time.sleep(0.05)
        code = process.returncode
        status = code if code >= 0 else 128 - code
        if interrupted is not None:
            status = 141 if broken_output else 128 + interrupted
        reason = 'output-pipe' if broken_output else 'signal' if interrupted else 'eof'
        capture.record('owned-native-hid-owner-end' if cleanup_grace == 120 else 'xcodebuild-end', returnCode=code, status=status)
    except OSError as error:
        capture.record('relay-error', error=str(error))
        if process is not None and process.poll() is not None:
            status = process.returncode if process.returncode >= 0 else 128 - process.returncode
    finally:
        signal_owned(signal.SIGKILL if pipe_held_open else signal.SIGTERM, include_exited=pipe_held_open)
        if process is not None and process.poll() is None:
            try:
                process.wait(timeout=cleanup_grace)
            except subprocess.TimeoutExpired:
                signal_owned(signal.SIGKILL)
                process.wait(timeout=5)
        children = capture.finish(reason)
        for number, handler in old_handlers.items():
            signal.signal(number, handler)
        if interrupted is not None:
            status = 141 if broken_output else 128 + interrupted
        try:
            (pathlib.Path(evidence) / 'test-aligned-boundaries.json').write_text(json.dumps(dict(
                device=device, finishedUTC=utc(), status=status, interrupted=interrupted, events=capture.events, children=children), indent=2) + '\n')
        except OSError as error:
            print('Boundary metadata could not be written: ' + str(error), file=sys.stderr)
    return status


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--evidence', required=True)
    parser.add_argument('--owned-simulator', action='store_true')
    parser.add_argument('--owned-cleanup-grace-seconds', type=int, choices=[5, 120], default=5)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    if os.environ.get('CI') != 'true' or os.environ.get('TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR') != '1' or not arguments.owned_simulator:
        parser.error('Boundary capture requires the wrapper-owned isolated CI simulator')
    command = arguments.command[1:] if arguments.command[:1] == ['--'] else arguments.command
    if not command:
        parser.error('Pass the original xcodebuild command after --')
    if arguments.owned_cleanup_grace_seconds == 120 and (len(command) < 2 or pathlib.Path(command[1]).resolve() != pathlib.Path(__file__).with_name('with-native-keyboard-hid.py').resolve() or os.environ.get('TSK_NATIVE_KEYBOARD_HID') != '1'):
        parser.error('Extended owned cleanup is only for the explicit native HID owner')
    raise SystemExit(run(command, arguments.device, arguments.evidence, cleanup_grace=arguments.owned_cleanup_grace_seconds))
