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
import tempfile
import termios
import threading
import time

from native_ui_readback import NativeReadback, REQUEST


METHOD = re.compile(r"^Test Case '-\[TskUITests\.(\w+) (\w+)\]' (started\.|(passed|failed|skipped) \(([\d.]+) seconds\)\.)$")
POST_PARENT_EXIT_DRAIN_SECONDS = 0.25
POST_GROUP_SIGNAL_DRAIN_SECONDS = 0.25


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


class DeviceMonitor:
    def __init__(self, device, record, command=None, clock=time.monotonic):
        self.device = device
        self.record = record
        self.command = command or ['xcrun', 'simctl', 'list', 'devices', '--json']
        self.clock = clock
        self.next_check = clock() + 15
        self.process = None
        self.output = None

    def poll(self):
        now = self.clock()
        if self.process is None and now >= self.next_check:
            self.output = tempfile.TemporaryFile()
            try:
                self.process = subprocess.Popen(self.command, stdout=self.output, stderr=subprocess.DEVNULL)
            except OSError:
                self.close()
                self.next_check = now + 15
                self.record('device-monitor-inconclusive', reason='query-start-failed')
                return False
            self.deadline = now + 3
        if self.process is None:
            return False
        if self.process.poll() is None:
            if now >= self.deadline:
                self.close()
                self.next_check = now + 15
                self.record('device-monitor-inconclusive', reason='query-timeout')
            return False
        unavailable = False
        try:
            if self.process.returncode == 0:
                self.output.seek(0)
                data = json.load(self.output)
                states = [item.get('state') for items in data['devices'].values() for item in items if item.get('udid') == self.device]
                unavailable = states == ['Shutdown']
                if unavailable:
                    self.record('owned-device-unavailable', state='Shutdown')
        except (ValueError, KeyError, TypeError):
            self.record('device-monitor-inconclusive', reason='invalid-response')
        finally:
            self.close()
            self.next_check = now + 15
        return unavailable

    def close(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.kill()
            try:
                self.process.wait(timeout=0)
            except subprocess.TimeoutExpired:
                threading.Thread(target=self.process.wait, name='tsk-device-monitor-reaper', daemon=True).start()
            self.process = None
        if self.output is not None:
            self.output.close()
            self.output = None


class BoundaryCapture:
    def __init__(self, device, evidence, readback=None):
        self.device = device
        self.evidence = pathlib.Path(evidence)
        self.events = []
        self.first_failure = None
        self.readback = readback
        try:
            self.evidence.mkdir(parents=True, exist_ok=True)
        except OSError as error:
            self.record('evidence-directory-error', error=str(error))

    def record(self, event, **fields):
        self.events.append(dict(event=event, receivedUTC=utc(), **fields))

    def line(self, raw):
        line = raw.decode('utf-8', errors='replace').rstrip('\r')
        request = REQUEST.fullmatch(line)
        if request and self.readback is not None:
            self.readback.respond(request[1])
        method = METHOD.fullmatch(line)
        if method:
            suite, name, state, outcome, seconds = method.groups()
            self.record('method-start' if state == 'started.' else 'method-end', method=suite + '/' + name, outcome=outcome, seconds=float(seconds) if seconds else None)
            if outcome == 'failed' and self.first_failure is None:
                self.first_failure = utc()
                self.record('first-test-failure', method=suite + '/' + name)
                print('::error title=First UI failure::' + suite + '/' + name + ' failed; remaining independent cases may continue.', flush=True)


def run(command, device, evidence, cleanup_grace=5, monitor_device=False, readback=None):
    if cleanup_grace != 5:
        raise ValueError('Owned cleanup grace must remain five seconds')
    capture = BoundaryCapture(device, evidence, readback)
    process = None
    interrupted = None
    broken_output = False
    pending = b''
    discarding = False
    pipe_held_open = False
    old_handlers = {}
    monitor = DeviceMonitor(device, capture.record) if monitor_device else None
    device_lost = False

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
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        capture.record('xcodebuild-start', pid=process.pid, command=command)
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            signalled = False
            stop_deadline = None
            parent_exit_at = None
            group_signalled_at = None
            group_killed_at = None
            while selector.get_map():
                now = time.monotonic()
                if monitor is not None and not device_lost and monitor.poll():
                    device_lost = True
                    interrupted = signal.SIGTERM
                    print('::error title=Owned simulator unavailable::Stopping UI execution after the owned simulator shut down.', flush=True)
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
                        key.fileobj.close()
                        break
                    consume(chunk)
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
        capture.record('xcodebuild-end', returnCode=code, status=status)
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        capture.record('relay-error', error=str(error))
        if process is not None and process.poll() is not None:
            status = process.returncode if process.returncode >= 0 else 128 - process.returncode
    finally:
        if monitor is not None:
            monitor.close()
        signal_owned(signal.SIGKILL if pipe_held_open else signal.SIGTERM, include_exited=pipe_held_open)
        if process is not None and process.poll() is None:
            try:
                process.wait(timeout=cleanup_grace)
            except subprocess.TimeoutExpired:
                signal_owned(signal.SIGKILL)
                process.wait(timeout=5)
        for number, handler in old_handlers.items():
            signal.signal(number, handler)
        if interrupted is not None:
            status = 141 if broken_output else 128 + interrupted
        if device_lost:
            status = 74
        if readback is not None:
            status = readback.finish(status)
        try:
            (pathlib.Path(evidence) / 'test-aligned-boundaries.json').write_text(json.dumps(dict(
                device=device, finishedUTC=utc(), status=status, interrupted=interrupted, events=capture.events), indent=2) + '\n')
        except OSError as error:
            print('Boundary metadata could not be written: ' + str(error), file=sys.stderr)
    return status


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--evidence', required=True)
    parser.add_argument('--owned-simulator', action='store_true')
    parser.add_argument('--monitor-device', action='store_true')
    parser.add_argument('--native-probe')
    parser.add_argument('--native-library')
    parser.add_argument('--native-readback-plan')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    if os.environ.get('CI') != 'true' or os.environ.get('TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR') != '1' or not arguments.owned_simulator:
        parser.error('Boundary capture requires the wrapper-owned isolated CI simulator')
    command = arguments.command[1:] if arguments.command[:1] == ['--'] else arguments.command
    if not command:
        parser.error('Pass the original xcodebuild command after --')
    readback = None
    if arguments.native_readback_plan:
        plan = json.loads(pathlib.Path(arguments.native_readback_plan).read_text())
        readback = NativeReadback(arguments.device, arguments.native_probe, arguments.native_library, plan, pathlib.Path(arguments.evidence) / 'native-readback', os.environ['TSK_UI_NATIVE_READBACK_TOKEN'])
    raise SystemExit(run(command, arguments.device, arguments.evidence, monitor_device=arguments.monitor_device, readback=readback))
