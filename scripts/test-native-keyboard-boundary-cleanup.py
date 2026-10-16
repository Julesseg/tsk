import importlib.util
import json
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest

path = pathlib.Path(__file__).with_name('relay-ui-test-boundaries.py').resolve()


class NestedOwnerCleanupTests(unittest.TestCase):
    def test_nested_owner_waits_for_actual_slow_owned_child_cleanup_before_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            ready = root / 'ready'
            child_pid = root / 'child-pid'
            receipt = root / 'owner-cleanup.json'
            child = root / 'child.py'
            child.write_text("import pathlib,signal,sys,time\ndef stop(*args):\n time.sleep(6)\n sys.exit(0)\nsignal.signal(signal.SIGTERM,stop)\npathlib.Path(sys.argv[1]).touch()\nwhile True:time.sleep(.01)\n")
            owner = root / 'owner.py'
            owner.write_text("import json,pathlib,signal,subprocess,sys,time\np=subprocess.Popen([sys.executable,sys.argv[1],sys.argv[2]],start_new_session=True)\ndef stop(*args):\n p.terminate()\n p.wait(timeout=9)\n pathlib.Path(sys.argv[4]).write_text(json.dumps(dict(childPID=p.pid,reaped=True,status=p.returncode)))\n sys.exit(143)\nsignal.signal(signal.SIGTERM,stop)\nwhile not pathlib.Path(sys.argv[2]).exists():time.sleep(.01)\npathlib.Path(sys.argv[3]).write_text(str(p.pid))\nwhile True:time.sleep(.01)\n")
            wrapper = "import importlib.util,pathlib,sys;s=importlib.util.spec_from_file_location('boundary',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);raise SystemExit(m.run([sys.executable,*sys.argv[3:]],'owned-host-fixture',sys.argv[2],cleanup_grace=120))"
            process = subprocess.Popen([sys.executable, '-c', wrapper, str(path), str(root), str(owner), str(child), str(ready), str(child_pid), str(receipt)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                deadline = time.monotonic() + 3
                while not child_pid.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(.01)
                self.assertTrue(child_pid.exists())
                process.send_signal(signal.SIGTERM)
                raw, _ = process.communicate(timeout=12)
                self.assertEqual(process.returncode, 143, raw.decode())
                self.assertTrue(receipt.exists(), 'Outer relay must not kill the owner at five seconds while actual owned cleanup is still running')
                self.assertEqual(json.loads(receipt.read_text())['reaped'], True)
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=2)
                if child_pid.exists() and not receipt.exists():
                    try:
                        os.kill(int(child_pid.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass


class DefaultBoundaryTests(unittest.TestCase):
    def test_default_capture_path_keeps_original_process_labels_and_status(self):
        spec=importlib.util.spec_from_file_location('boundary',path)
        boundary=importlib.util.module_from_spec(spec);spec.loader.exec_module(boundary)
        with tempfile.TemporaryDirectory() as directory:
            command=[sys.executable,'-c','raise SystemExit(23)']
            self.assertEqual(boundary.run(command,'owned-host-fixture',directory),23)
            metadata=json.loads((pathlib.Path(directory)/'test-aligned-boundaries.json').read_text())
            self.assertEqual(metadata['events'][0]['event'],'xcodebuild-start')
            self.assertEqual(metadata['events'][0]['command'],command)
            self.assertNotIn('cleanupGraceSeconds',metadata['events'][0])

    def test_extended_cli_grace_rejects_anything_except_fixed_owned_hid_owner(self):
        environment=dict(os.environ,CI='true',TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR='1',TSK_NATIVE_KEYBOARD_HID='1')
        with tempfile.TemporaryDirectory() as directory:
            command=[sys.executable,str(path),'--device','owned','--evidence',directory,'--owned-simulator','--owned-cleanup-grace-seconds','120','--',sys.executable,'-c','raise SystemExit(99)']
            result=subprocess.run(command,env=environment,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=2)
            self.assertEqual(result.returncode,2)
            self.assertIn(b'only for the explicit native HID owner',result.stdout)


if __name__ == '__main__': unittest.main()
