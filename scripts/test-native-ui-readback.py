import json
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import threading
import tempfile
import unittest
import uuid
from unittest.mock import patch

from native_ui_readback import NativeReadback

spec = importlib.util.spec_from_file_location('boundaries', Path(__file__).with_name('relay-ui-test-boundaries.py'))
boundaries = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boundaries)


class NativeReadbackTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.runner = self.root / 'runner'
        self.runner.mkdir()
        self.requests = self.runner / 'Documents/TskNativeReadback'
        self.requests.mkdir(parents=True)
        self.group = self.root / 'group'
        self.replica = str(uuid.uuid4()).upper()
        self.storage = self.group / 'UITests' / self.replica / 'TaskChampion'
        self.storage.mkdir(parents=True)
        self.record = dict(id=str(uuid.uuid4()), attributes=[dict(key='scheduled', value='1792231200')])
        (self.storage / 'records.json').write_text(json.dumps([self.record]))
        self.probe = self.root / 'probe'
        self.probe.write_text('#!/usr/bin/env python3\nimport pathlib,sys\nassert sys.argv[1]=="read-tasks"\nprint((pathlib.Path(sys.argv[2])/"records.json").read_text())\n')
        self.probe.chmod(0o755)
        self.method = 'BulkTests/testSave'
        self.reader = NativeReadback('owned', str(self.probe), 'native-library', {self.method: ['saved']}, self.root / 'evidence', 'owned-session')
        self.reader.container = lambda bundle, kind: self.runner if kind == 'data' else self.group

    def request(self, **changes):
        nonce = str(uuid.uuid4()).upper()
        value = dict(schema=1, session='owned-session', nonce=nonce, replica=self.replica, method=self.method, checkpoint='saved')
        value.update(changes)
        (self.requests / (nonce+'.request.json')).write_text(json.dumps(value))
        self.reader.respond(nonce)
        self.reader.worker.join()
        return json.loads((self.requests / (nonce+'.response.json')).read_text())

    def test_native_response_is_actual_query_output_with_bound_identity(self):
        response = self.request()
        self.assertEqual(response['records'], [self.record])
        self.assertEqual(response['replica'], self.replica)
        self.assertEqual(self.reader.finish(0), 0)
        records = list((self.root / 'evidence').glob('*.json'))
        self.assertFalse(any('owned-session' in p.read_text() for p in records))

    def test_wrong_session_unknown_and_duplicate_checkpoints_fail(self):
        for change in [dict(session='other'), dict(method='Other/test'), dict(replica='../escape')]:
            with self.subTest(change=change):
                response = self.request(**change)
                self.assertIn('error', response)
        self.assertNotEqual(self.reader.finish(0), 0)
        self.assertEqual(self.reader.finish(65), 65)

    def test_duplicate_checkpoint_cannot_satisfy_missing_coverage(self):
        self.assertIn('records', self.request())
        self.assertIn('error', self.request())
        self.assertNotEqual(self.reader.finish(0), 0)

    def test_missing_native_store_does_not_create_a_store_or_return_empty_success(self):
        (self.storage / 'records.json').unlink()
        self.storage.rmdir()
        self.assertIn('error', self.request())
        self.assertFalse(self.storage.exists())
        self.assertNotEqual(self.reader.finish(0), 0)

    def test_platform_container_identity_is_resolved_once_per_run(self):
        self.reader.container = NativeReadback.container.__get__(self.reader)
        with patch.object(self.reader, 'command', return_value=str(self.group)) as lookup:
            self.assertEqual(self.reader.container('owned-app', 'group'), self.group)
            self.assertEqual(self.reader.container('owned-app', 'group'), self.group)
            self.assertEqual(lookup.call_count, 1)

    def test_no_request_is_incomplete_even_when_ui_process_exits_green(self):
        self.assertNotEqual(self.reader.finish(0), 0)

    def test_slow_container_lookup_does_not_block_test_boundary_delivery(self):
        nonce = str(uuid.uuid4()).upper()
        request = dict(schema=1, session='owned-session', nonce=nonce, replica=self.replica,
                       method=self.method, checkpoint='saved')
        (self.requests / (nonce+'.request.json')).write_text(json.dumps(request))
        delivered = threading.Event()

        def container(bundle, kind):
            delivered.wait()
            return self.runner if kind == 'data' else self.group

        self.reader.container = container
        original = boundaries.BoundaryCapture.record

        def record(capture, event, **fields):
            original(capture, event, **fields)
            if event == 'method-start':
                delivered.set()

        command = f'import pathlib,time; print("TSK_NATIVE_READBACK_REQUEST {nonce}", flush=True); print("Test Case \'-[TskUITests.SignalTests testBoundary]\' started.", flush=True); response=pathlib.Path({str(self.requests / (nonce+".response.json"))!r}); exec("while not response.exists(): time.sleep(0.001)")'
        with patch.object(boundaries.BoundaryCapture, 'record', record):
            status = boundaries.run([sys.executable, '-c', command], 'owned', self.root / 'boundaries', readback=self.reader)
        self.assertEqual(status, 0, self.reader.errors)
        response = json.loads((self.requests / (nonce+'.response.json')).read_text())
        self.assertEqual(response['records'], [self.record])
        self.assertTrue(delivered.is_set())

    def test_ui_exit_reaps_an_unfinished_native_reader_and_preserves_failure(self):
        self.probe.write_text('#!/usr/bin/env python3\nimport signal\nsignal.pause()\n')
        nonce = str(uuid.uuid4()).upper()
        request = dict(schema=1, session='owned-session', nonce=nonce, replica=self.replica,
                       method=self.method, checkpoint='saved')
        (self.requests / (nonce+'.request.json')).write_text(json.dumps(request))
        started = threading.Event()
        original = subprocess.Popen
        processes = []

        def start(*args, **kwargs):
            process = original(*args, **kwargs)
            processes.append(process)
            started.set()
            return process

        with patch('native_ui_readback.subprocess.Popen', side_effect=start):
            self.reader.respond(nonce)
            started.wait()
            self.assertEqual(self.reader.finish(65), 65)
        self.assertTrue(processes)
        self.assertTrue(all(process.poll() is not None for process in processes))
        self.assertFalse(self.reader.worker.is_alive())
        self.assertFalse(self.reader.completed)
        self.assertTrue(self.reader.errors)


if __name__ == '__main__':
    unittest.main()
