import argparse
import collections
import datetime
import json
import os
from pathlib import Path
import platform
import re
import selectors
import signal
import subprocess
import threading
import time


MAXIMUM_SECONDS = 180 * 60
RESOURCE_INTERVAL = 30
EVENT_FIELDS = ('timestamp', 'processID', 'processImagePath', 'subsystem', 'category', 'messageType', 'eventMessage')
IDENTITY_FIELDS = ('ImageOS', 'ImageVersion', 'RUNNER_OS', 'RUNNER_ARCH', 'GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_JOB')


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


class Redactor:
    def __init__(self, environment):
        self.secrets = sorted({value for key, value in environment.items()
                               if re.search(r'token|secret|password|passwd|credential|authorization|private_key|api[_-]?key', key, re.I)
                               and value}, key=len, reverse=True)

    def __call__(self, text):
        for secret in self.secrets:
            text = text.replace(secret, '<REDACTED>')
        text = re.sub(r'(?i)(Bearer\s+)[^\s,;"\']+', r'\1<REDACTED>', text)
        text = re.sub(r'''(?i)((?:token|secret|password|passwd|authorization|credential|api[_-]?key|private[_-]?key)[\w-]*["']?\s*[=:]\s*)(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;}\]]+)''', r'\1<REDACTED>', text)
        return re.sub(r'(https?://)[^/\s:@]+:[^/\s@]+@', r'\1<REDACTED>@', text)

    def value(self, value):
        if isinstance(value, str):
            return self(value)
        if isinstance(value, dict):
            return {key: self.value(item) for key, item in value.items()}
        if isinstance(value, (list, tuple)):
            return [self.value(item) for item in value]
        return value


class BoundedRecords:
    def __init__(self, directory, maximum_bytes=2 * 1024 * 1024, maximum_files=4):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        if any(self.directory.iterdir()):
            raise FileExistsError('Preserve existing diagnostic records')
        self.maximum_bytes = maximum_bytes
        self.maximum_files = maximum_files
        self.paths = collections.deque()
        self.sequence = 0
        self.size = 0
        self.records = 0

    def write(self, value):
        data = (json.dumps(value, ensure_ascii=True) + '\n').encode()
        if len(data) > self.maximum_bytes:
            return
        if not self.paths or self.size + len(data) > self.maximum_bytes:
            self.sequence += 1
            self.paths.append(self.directory / f'{self.sequence:06}.jsonl')
            self.size = 0
            while len(self.paths) > self.maximum_files:
                self.paths.popleft().unlink(missing_ok=True)
        with self.paths[-1].open('ab') as output:
            output.write(data)
        self.size += len(data)
        self.records += 1


def stop_child(child):
    if child is None:
        return
    if child.poll() is None:
        child.terminate()
    try:
        child.wait(timeout=1)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait(timeout=1)


class HostCapture:
    def __init__(self, device, output, environment=None, log_command=None, resource_commands=None, maximum_seconds=MAXIMUM_SECONDS):
        self.device = device
        self.output = Path(output)
        self.environment = dict(os.environ if environment is None else environment)
        self.redact = Redactor(self.environment)
        predicate = ('process == "CoreSimulatorService" OR process == "com.apple.CoreSimulator.CoreSimulatorService" OR process == "simdiskimaged" '
                     'OR subsystem BEGINSWITH "com.apple.CoreSimulator" '
                     f'OR (process == "launchd" AND (eventMessage CONTAINS "{device}" OR eventMessage CONTAINS "CoreSimulator")) '
                     'OR (process == "kernel" AND (eventMessage CONTAINS[c] "memorystatus" OR eventMessage CONTAINS[c] "jetsam"))')
        self.log_command = log_command or ['/usr/bin/log', 'stream', '--style', 'ndjson', '--level', 'info', '--timeout', '180m', '--predicate', predicate]
        self.resource_commands = resource_commands if resource_commands is not None else {
            'memory': ['/usr/bin/vm_stat'],
            'pressure': ['/usr/bin/memory_pressure', '-Q'],
            'swap': ['/usr/sbin/sysctl', 'vm.swapusage'],
            'disk': ['/bin/df', '-k', str(self.output.resolve())],
            'processes': ['/bin/ps', '-axo', 'pid,ppid,pcpu,rss,comm'],
        }
        self.maximum_seconds = maximum_seconds
        self.started = time.time()
        self.stop = threading.Event()
        self.thread = None
        self.capture_started = False
        self.logger = None
        self.metadata = dict(schema=1, device=device, startedUTC=utc(), hostOS=platform.mac_ver()[0],
                             hostArchitecture=platform.machine(), runner={key: self.environment[key] for key in IDENTITY_FIELDS if key in self.environment},
                             maximumSeconds=maximum_seconds, resourceIntervalSeconds=RESOURCE_INTERVAL,
                             eventLimitBytes=8 * 1024 * 1024, resourceLimitBytes=1024 * 1024,
                             logExecutable=self.log_command[0], logPredicate=predicate, errors=[], oversizedLines=0)

    def save(self):
        target = self.output / 'capture.json'
        temporary = target.with_suffix('.tmp')
        temporary.write_text(json.dumps(self.redact.value(self.metadata), indent=2) + '\n')
        temporary.replace(target)

    def start(self):
        self.output.mkdir(parents=True, exist_ok=True)
        if any(self.output.iterdir()):
            raise FileExistsError('Preserve existing host diagnostics')
        self.save()
        self.capture_started = True
        try:
            self.logger = subprocess.Popen(self.log_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.metadata['loggerPID'] = self.logger.pid
        except OSError as error:
            self.metadata['errors'].append(type(error).__name__)
            self.save()
            print('::warning::UI host log reader unavailable; see capture.json for the diagnostic gap', file=os.sys.stderr)
            return
        self.thread = threading.Thread(target=self.collect, name='tsk-host-diagnostics', daemon=True)
        self.thread.start()

    def resources(self, records, final=False):
        sample = dict(utc=utc(), monotonic=time.monotonic(), load=os.getloadavg(), commands={})
        for name, command in self.resource_commands.items():
            if self.stop.is_set() and not final:
                break
            try:
                result = subprocess.run(command, capture_output=True, text=True, timeout=1)
                text = result.stdout
                if name == 'processes':
                    text = '\n'.join(line for line in text.splitlines() if re.search(r'CoreSimulator|simdiskimaged|SimLaunchHost|launchd_sim|testmanagerd|xcodebuild|Tsk', line))
                sample['commands'][name] = dict(status=result.returncode, stdout=self.redact(text[:32768]), stderr=self.redact(result.stderr[:2048]))
            except (OSError, subprocess.TimeoutExpired) as error:
                sample['commands'][name] = dict(error=type(error).__name__)
        if records:
            records.write(sample)
        if 'initialResources' not in self.metadata:
            self.metadata['initialResources'] = sample
        return sample

    def reports(self, directories=None):
        prefixes = ('CoreSimulatorService', 'simdiskimaged', 'SimLaunchHost', 'launchd_sim', 'Simulator', 'testmanagerd', 'Tsk')
        fields = ('procName', 'pid', 'parentProc', 'parentPid', 'responsibleProc', 'responsiblePid',
                  'exception', 'termination', 'captureTime', 'osVersion')
        reports = []
        directories = directories if directories is not None else (Path.home() / 'Library/Logs/DiagnosticReports', Path('/Library/Logs/DiagnosticReports'))
        deadline = time.monotonic() + 2
        scanned = 0
        for directory in directories:
            for path in directory.glob('*.ips'):
                scanned += 1
                if len(reports) >= 8 or scanned > 512 or time.monotonic() >= deadline:
                    self.metadata['reportScanCapped'] = True
                    break
                try:
                    if not path.name.startswith(prefixes) or path.is_symlink() or path.stat().st_mtime < self.started:
                        continue
                    if path.stat().st_size > 2 * 1024 * 1024:
                        continue
                    with path.open() as source:
                        text = source.read(2 * 1024 * 1024 + 1)
                    if len(text) > 2 * 1024 * 1024:
                        continue
                    try:
                        body = json.loads(text)
                    except ValueError:
                        body = json.loads(text.split('\n', 1)[1])
                    if not isinstance(body, dict):
                        continue
                    report = {field: body[field] for field in fields if field in body}
                    index = body.get('faultingThread')
                    if isinstance(index, int) and 0 <= index < len(body.get('threads', [])):
                        report['faultingFrames'] = body['threads'][index].get('frames', [])[:50]
                    retained = self.redact.value(dict(file=path.name, details=report))
                    if len(json.dumps(retained).encode()) <= 65536:
                        reports.append(retained)
                except (OSError, ValueError, IndexError, TypeError):
                    continue
        self.metadata['processReports'] = reports

    def collect(self):
        events = None
        resources = None
        selector = selectors.DefaultSelector()
        buffers = {}
        deadline = time.monotonic() + self.maximum_seconds
        next_resources = 0

        def read_ready(timeout):
            for key, _ in selector.select(timeout=timeout):
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                data = buffers[key.fileobj] + chunk
                lines = data.split(b'\n')
                buffers[key.fileobj] = lines.pop()
                if len(buffers[key.fileobj]) > 65536:
                    buffers[key.fileobj] = b''
                    self.metadata['oversizedLines'] += 1
                for line in lines:
                    if len(line) > 65536:
                        self.metadata['oversizedLines'] += 1
                        continue
                    if key.fileobj == self.logger.stderr:
                        events.write(dict(kind='logger-stderr', utc=utc(), message=self.redact(line.decode(errors='replace'))))
                        continue
                    try:
                        event = json.loads(line)
                        if not isinstance(event, dict):
                            raise ValueError('Expected log event')
                        value = {field: event[field] for field in EVENT_FIELDS if field in event}
                        events.write(dict(kind='host-event', event=self.redact.value(value)))
                    except (ValueError, TypeError):
                        self.metadata['invalidLines'] = self.metadata.get('invalidLines', 0) + 1

        try:
            events = BoundedRecords(self.output / 'host-events')
            resources = BoundedRecords(self.output / 'resources', maximum_bytes=512 * 1024, maximum_files=2)
            for stream in (self.logger.stdout, self.logger.stderr):
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ)
                buffers[stream] = b''
            while not self.stop.is_set() and time.monotonic() < deadline:
                if time.monotonic() >= next_resources:
                    self.resources(resources)
                    next_resources = time.monotonic() + RESOURCE_INTERVAL
                read_ready(0.2)
                if not selector.get_map():
                    break
        except Exception as error:
            self.metadata['errors'].append(type(error).__name__)
        finally:
            try:
                stop_child(self.logger)
                drain_deadline = time.monotonic() + 1
                while selector.get_map() and time.monotonic() < drain_deadline:
                    read_ready(0.05)
            except (OSError, subprocess.TimeoutExpired) as error:
                self.metadata['errors'].append(type(error).__name__)
            selector.close()
            if self.logger:
                for stream in (self.logger.stdout, self.logger.stderr):
                    stream.close()
                self.metadata['loggerStatus'] = self.logger.returncode
            self.metadata['stoppedBy'] = 'worker-finished' if self.stop.is_set() else 'duration' if time.monotonic() >= deadline else 'logger-exit'
            if self.metadata['stoppedBy'] == 'logger-exit':
                self.metadata['errors'].append('host-log-ended-before-worker')
                print('::warning::UI host log reader ended before the worker; see capture.json for the diagnostic gap', file=os.sys.stderr)
            self.metadata.update(captureFinishedUTC=utc(), durationCapped=time.monotonic() >= deadline,
                                 eventRecords=events.records if events else 0, eventFiles=[p.name for p in events.paths] if events else [],
                                 resourceFiles=[p.name for p in resources.paths] if resources else [],
                                 eventFilesDropped=events.sequence - len(events.paths) if events else 0,
                                 resourceFilesDropped=resources.sequence - len(resources.paths) if resources else 0)
            self.save()

    def close(self, status):
        if not self.capture_started:
            return
        self.stop.set()
        if self.thread:
            self.thread.join(timeout=5)
            if self.thread.is_alive():
                stop_child(self.logger)
                self.thread.join(timeout=2)
        self.metadata.update(workerStatus=status, collectorFinished=self.thread is None or not self.thread.is_alive())
        try:
            self.metadata['finalResources'] = self.resources(None, final=True)
            self.reports()
        except Exception as error:
            self.metadata['errors'].append(type(error).__name__)
        self.metadata['finishedUTC'] = utc()
        self.save()


def run(command, capture):
    child = None
    interrupted = None
    old_handlers = {}

    def interrupt(number, _frame):
        nonlocal interrupted
        interrupted = number
        if child is not None and child.poll() is None:
            try:
                os.killpg(child.pid, number)
            except ProcessLookupError:
                pass

    for number in (signal.SIGINT, signal.SIGTERM):
        old_handlers[number] = signal.signal(number, interrupt)
    status = 1
    try:
        try:
            capture.start()
        except Exception as error:
            print(f'::warning::UI host diagnostics unavailable ({type(error).__name__})', file=os.sys.stderr)
        child = subprocess.Popen(command, start_new_session=True)
        if interrupted is not None:
            interrupt(interrupted, None)
        result = child.wait()
        status = result if result >= 0 else 128 - result
        return status
    finally:
        try:
            capture.close(status)
        except Exception as error:
            print(f'::warning::UI host diagnostics incomplete ({type(error).__name__})', file=os.sys.stderr)
        for number, handler in old_handlers.items():
            signal.signal(number, handler)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    command = arguments.command[1:] if arguments.command[:1] == ['--'] else arguments.command
    if not command:
        parser.error('Pass the unchanged UI worker command after --')
    raise SystemExit(run(command, HostCapture(arguments.device, arguments.output)))
