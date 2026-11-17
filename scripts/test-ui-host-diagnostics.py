import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


SCRIPT = Path(__file__).with_name('capture-ui-host-diagnostics.py')
spec = importlib.util.spec_from_file_location('host_diagnostics', SCRIPT)
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)


class HostDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.output = Path(self.directory.name) / 'evidence'

    def capture(self, log, **kwargs):
        return diagnostics.HostCapture('00000000-0000-0000-0000-000000000001', self.output,
                                       log_command=[sys.executable, '-u', '-c', log], resource_commands={}, **kwargs)

    def test_multiline_environment_and_embedded_credentials_are_redacted_before_json_encoding(self):
        secret = 'fixture"secret\nline'
        redact = diagnostics.Redactor({'GITHUB_TOKEN': secret, 'API_KEY': 'abc'})
        value = redact.value({'eventMessage': secret + ' Bearer unseen-credential https://user:pass@example.com password=hidden abc', 'pid': 42})
        encoded = json.dumps(value)
        for text in [secret, 'unseen-credential', 'user:pass', 'hidden', 'abc']:
            self.assertNotIn(text, encoded)
        self.assertEqual(value['pid'], 42)
        self.assertGreaterEqual(encoded.count('<REDACTED>'), 5)
        assignments = redact('"TSK_UI_SYNC_SECRET" = "generated-fixture-value"; password="quoted-value"; \'credential\': \'two words\'')
        for text in ['generated-fixture-value', 'quoted-value', 'two words']:
            self.assertNotIn(text, assignments)

    def test_rotating_records_remain_bounded_and_keep_latest_events_in_order(self):
        writer = diagnostics.BoundedRecords(self.output, maximum_bytes=100, maximum_files=3)
        for number in range(50):
            writer.write({'number': number, 'message': 'x' * 20})
        self.assertLessEqual(sum(p.stat().st_size for p in self.output.iterdir()), 300)
        actual = [json.loads(line)['number'] for p in writer.paths for line in p.read_text().splitlines()]
        self.assertEqual(actual, sorted(actual))
        self.assertEqual(actual[-1], 49)
        self.assertGreater(actual[0], 0)

    def test_worker_failure_is_preserved_and_owned_logger_is_reaped(self):
        unrelated = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)'])
        self.addCleanup(lambda: diagnostics.stop_child(unrelated))
        capture = self.capture('import json,time;print(json.dumps({"eventMessage":"shutdown requested", "processID":42}));time.sleep(30)')
        status = diagnostics.run([sys.executable, '-c', 'import time;time.sleep(.3);raise SystemExit(7)'], capture)
        self.assertEqual(status, 7)
        metadata = json.loads((self.output / 'capture.json').read_text())
        self.assertTrue(metadata['collectorFinished'])
        self.assertEqual(metadata['workerStatus'], 7)
        self.assertGreater(metadata['eventRecords'], 0)
        with self.assertRaises(ProcessLookupError):
            os.kill(metadata['loggerPID'], 0)
        self.assertIsNone(unrelated.poll())

    def test_missing_log_executable_is_recorded_without_masking_worker_failure(self):
        capture = self.capture('raise SystemExit(0)')
        capture.log_command = ['/nonexistent/tsk-log-reader']
        self.assertEqual(diagnostics.run([sys.executable, '-c', 'raise SystemExit(7)'], capture), 7)
        metadata = json.loads((self.output / 'capture.json').read_text())
        self.assertIn('FileNotFoundError', metadata['errors'])
        self.assertEqual(metadata['workerStatus'], 7)

    def test_unavailable_log_service_does_not_change_worker_result(self):
        capture = self.capture('raise SystemExit(64)')
        capture.resource_commands = {'unavailable': ['/nonexistent/tsk-diagnostic-command']}
        self.assertEqual(diagnostics.run([sys.executable, '-c', 'import time;time.sleep(.2)'], capture), 0)
        metadata = json.loads((self.output / 'capture.json').read_text())
        self.assertEqual(metadata['loggerStatus'], 64)
        self.assertIn('host-log-ended-before-worker', metadata['errors'])
        self.assertEqual(metadata['finalResources']['commands']['unavailable']['error'], 'FileNotFoundError')

    def test_capture_duration_limit_does_not_interrupt_worker(self):
        capture = self.capture('import time;time.sleep(30)', maximum_seconds=0.05)
        started = time.monotonic()
        self.assertEqual(diagnostics.run([sys.executable, '-c', 'import time;time.sleep(.4)'], capture), 0)
        self.assertGreaterEqual(time.monotonic() - started, .4)
        metadata = json.loads((self.output / 'capture.json').read_text())
        self.assertTrue(metadata['durationCapped'])

    def test_only_allowlisted_redacted_log_fields_are_retained(self):
        log = 'import json,time;print(json.dumps({"eventMessage":"Bearer fixture-secret", "processID":1,"environment":{"PASSWORD":"never-retain"}}));time.sleep(30)'
        capture = self.capture(log, environment={'GITHUB_TOKEN': 'fixture-secret'})
        diagnostics.run([sys.executable, '-c', 'import time;time.sleep(.2)'], capture)
        stored = ''.join(p.read_text() for p in self.output.rglob('*') if p.is_file())
        for secret in ['fixture-secret', 'never-retain']:
            self.assertNotIn(secret, stored)
        events = [json.loads(line) for p in (self.output / 'host-events').glob('*') for line in p.read_text().splitlines()]
        self.assertEqual(events[0]['event'], {'eventMessage': 'Bearer <REDACTED>', 'processID': 1})

    def test_capture_start_or_close_error_cannot_mask_worker_exit(self):
        class Unavailable:
            def start(self):
                raise PermissionError()

            def close(self, _status):
                raise OSError()

        self.assertEqual(diagnostics.run([sys.executable, '-c', 'raise SystemExit(9)'], Unavailable()), 9)

    def test_existing_evidence_is_preserved_when_capture_cannot_start(self):
        self.output.mkdir()
        original = self.output / 'capture.json'
        original.write_text('original failed evidence')
        capture = self.capture('raise SystemExit(0)')
        self.assertEqual(diagnostics.run([sys.executable, '-c', 'raise SystemExit(7)'], capture), 7)
        self.assertEqual(original.read_text(), 'original failed evidence')

    def test_process_report_keeps_termination_actor_without_environment_or_raw_memory(self):
        capture = self.capture('raise SystemExit(0)')
        reports = Path(self.directory.name) / 'reports'
        reports.mkdir()
        report = {'procName': 'CoreSimulatorService', 'pid': 42, 'termination': {'byProc': 'launchd', 'byPid': 1},
                  'environment': {'PASSWORD': 'do-not-retain'}, 'threadState': {'memory': 'do-not-retain'}}
        recent = reports / 'CoreSimulatorService-fixture.ips'
        recent.write_text(json.dumps({'header': True}) + '\n' + json.dumps(report))
        old = reports / 'CoreSimulatorService-old.ips'
        old.write_text(json.dumps(report))
        unrelated = reports / 'Unrelated-app.ips'
        unrelated.write_text(json.dumps({'procName': 'Unrelated-app'}))
        for path, timestamp in ((recent, capture.started + 1), (old, capture.started - 1), (unrelated, capture.started + 1)):
            os.utime(path, (timestamp, timestamp))
        capture.reports([reports])
        self.assertEqual(len(capture.metadata['processReports']), 1)
        self.assertEqual(capture.metadata['processReports'][0]['file'], recent.name)
        retained = capture.metadata['processReports'][0]['details']
        self.assertEqual(retained['termination'], {'byProc': 'launchd', 'byPid': 1})
        self.assertNotIn('do-not-retain', json.dumps(retained))

    def test_signal_is_forwarded_to_worker_and_logger_is_cleaned(self):
        ready = Path(self.directory.name) / 'ready'
        code = ('import importlib.util,sys;'
                f's=importlib.util.spec_from_file_location("capture",{str(SCRIPT)!r});'
                'm=importlib.util.module_from_spec(s);s.loader.exec_module(m);'
                f'c=m.HostCapture("owned",{str(self.output)!r},log_command=[sys.executable,"-c","import time;time.sleep(30)"],resource_commands={{}});'
                f'w="import pathlib,signal,time;signal.signal(signal.SIGTERM,lambda *_:exit(143));pathlib.Path({str(ready)!r}).touch();time.sleep(30)";'
                'raise SystemExit(m.run([sys.executable,"-c",w],c))')
        child = subprocess.Popen([sys.executable, '-c', code])
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and child.poll() is None and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue(ready.exists())
            child.send_signal(signal.SIGTERM)
            self.assertEqual(child.wait(timeout=5), 143)
            metadata = json.loads((self.output / 'capture.json').read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(metadata['loggerPID'], 0)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=2)


if __name__ == '__main__':
    unittest.main()
