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
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("spotlight_log", pathlib.Path(__file__).with_name("capture-simulator-spotlight-log.py"))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)
sample_path = pathlib.Path(__file__).with_name('sample-spotlight-index.py')
sample_spec = importlib.util.spec_from_file_location('index_sample', sample_path)
index_sample = importlib.util.module_from_spec(sample_spec)
sample_spec.loader.exec_module(index_sample)


class SpotlightLogTests(unittest.TestCase):
    def test_sampler_deadline_kills_and_reaps_its_owned_process(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / 'sample'
            tool.write_text('#!' + sys.executable + '\nimport time\ntime.sleep(3)\n')
            tool.chmod(0o700)
            output = root / 'stack.txt'
            self.assertEqual(index_sample.sample(654, output, executable=str(tool), timeout=.05), 124)
            metadata = json.loads(output.with_suffix('.metadata.json').read_text())
            self.assertEqual(metadata['timedOut'], True)
            self.assertEqual(metadata['returnCode'], -9)
            self.assertEqual(metadata['reaped'], True)

    def test_sampler_cancellation_reaps_the_worker_before_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / 'sample'
            ready = root / 'ready'
            tool.write_text('#!' + sys.executable + '\nimport os,pathlib,time\npathlib.Path(' + repr(str(ready)) + ').write_text(str(os.getpid()))\ntime.sleep(3)\n')
            tool.chmod(0o700)
            output = root / 'stack.txt'
            wrapper = "import importlib.util,sys;s=importlib.util.spec_from_file_location('sampler',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);raise SystemExit(m.sample(654,sys.argv[2],executable=sys.argv[3]))"
            process = subprocess.Popen([sys.executable, '-c', wrapper, str(sample_path), str(output), str(tool)])
            try:
                deadline = time.monotonic() + 2
                while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(.01)
                self.assertTrue(ready.exists())
                process.send_signal(signal.SIGTERM)
                self.assertEqual(process.wait(timeout=3), 143)
                metadata = json.loads(output.with_suffix('.metadata.json').read_text())
                self.assertEqual(metadata['signal'], signal.SIGTERM)
                self.assertEqual(metadata['returnCode'], -9)
                self.assertEqual(metadata['reaped'], True)
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=2)
                if ready.exists() and not output.with_suffix('.metadata.json').exists():
                    try:
                        os.kill(int(ready.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_unfinished_index_sample_is_reaped_when_capture_ends(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / "xcrun"
            tool.write_text("#!" + sys.executable + "\nimport time\nprint('searchd[654:def] Starting the indexing watchdog, bundleID:com.julesseguin.tsk',flush=True)\ntime.sleep(.6)\n")
            tool.chmod(0o700)
            sample = root / "sudo"
            sample.write_text("#!" + sys.executable + "\nimport time\ntime.sleep(5)\n")
            sample.chmod(0o700)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", ""))
            result = subprocess.run([sys.executable, str(pathlib.Path(capture.__file__)), "owned-device", str(root / "stream.log"), str(root / "stop"), "--sample-index-wait"], env=environment, capture_output=True, text=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)
            metadata = json.loads((root / "stream.metadata.json").read_text())
            self.assertEqual(metadata["indexWaitSample"]["stoppedBy"], "capture-completion")
            self.assertEqual(metadata["indexWaitSample"]["returnCode"], -15)
            self.assertEqual(metadata["indexWaitSample"]["reaped"], True)

    def test_index_wait_sampling_ignores_other_clients_and_runs_only_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / "xcrun"
            tool.write_text("#!" + sys.executable + "\nimport time\nprint('searchd[321:abc] Starting the indexing watchdog, bundleID:com.example.other',flush=True)\nprint('searchd[654:def] Starting the indexing watchdog, bundleID:com.julesseguin.tsk',flush=True)\nprint('searchd[654:def] Starting the indexing watchdog, bundleID:com.julesseguin.tsk',flush=True)\ntime.sleep(.6)\n")
            tool.chmod(0o700)
            sample = root / "sudo"
            sample.write_text("#!" + sys.executable + "\nimport json,os,pathlib,sys\np=pathlib.Path(os.environ['SAMPLE_CALLS'])\np.write_text(p.read_text()+json.dumps(sys.argv[1:])+'\\n' if p.exists() else json.dumps(sys.argv[1:])+'\\n')\npathlib.Path(sys.argv[-1]).write_text('owned indexing worker stack')\n")
            sample.chmod(0o700)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", ""), SAMPLE_CALLS=str(root / "sample-calls"))
            result = subprocess.run([sys.executable, str(pathlib.Path(capture.__file__)), "owned-device", str(root / "stream.log"), str(root / "stop"), "--sample-index-wait"], env=environment, capture_output=True, text=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = (root / "sample-calls").read_text().splitlines()
            self.assertEqual(len(calls), 1)
            self.assertEqual(json.loads(calls[0])[:3], ["-n", sys.executable, "-I"])
            self.assertEqual(json.loads(calls[0])[-2], "654")
            self.assertEqual((root / "stream.index-wait.sample.txt").read_text(), "owned indexing worker stack")
            metadata = json.loads((root / "stream.metadata.json").read_text())
            self.assertEqual(metadata["indexWaitSample"]["returnCode"], 0)
            self.assertEqual(metadata["indexWaitSample"]["reaped"], True)

    def test_long_method_capture_stops_and_reaps_at_test_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / "xcrun"
            tool.write_text("#!" + sys.executable + "\nimport signal,sys,time\nsignal.signal(signal.SIGTERM,lambda *_:sys.exit(143))\nprint('ready',flush=True)\nwhile True:time.sleep(.01)\n")
            tool.chmod(0o700)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", ""))
            process = subprocess.Popen([sys.executable, str(pathlib.Path(capture.__file__)), "owned-device", str(root / "stream.log"), str(root / "stop"), "--maximum-seconds", "600"], env=environment)
            try:
                deadline = time.monotonic() + 2
                while not (root / "stream.log").exists() or not (root / "stream.log").read_text():
                    self.assertLess(time.monotonic(), deadline)
                    time.sleep(.01)
                (root / "stop").touch()
                self.assertEqual(process.wait(timeout=2), 0)
                metadata = json.loads((root / "stream.metadata.json").read_text())
                self.assertEqual(metadata["stoppedBy"], "test-completion")
                self.assertEqual(metadata["returnCode"], 143)
            finally:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=7)

    def test_cli_accepts_a_method_window_without_changing_the_test_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / "xcrun"
            tool.write_text("#!" + sys.executable + "\nimport sys\nprint(sys.argv[sys.argv.index('--timeout')+1],flush=True)\n")
            tool.chmod(0o700)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", ""))
            subprocess.run([sys.executable, str(pathlib.Path(capture.__file__)), "owned-device", str(root / "stream.log"), str(root / "stop"), "--maximum-seconds", "600"], env=environment, check=True, timeout=2)
            self.assertEqual((root / "stream.log").read_text().strip(), "600")
            metadata = json.loads((root / "stream.metadata.json").read_text())
            self.assertEqual(metadata["maximumSeconds"], 600)
            self.assertEqual(metadata["returnCode"], 0)

    def test_duration_expires_in_guest_without_a_host_termination_signal(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tool = root / "xcrun"
            tool.write_text("#!" + sys.executable + "\nimport signal,sys,time\nsignal.signal(signal.SIGTERM, lambda *_: sys.exit(143))\nif '--timeout' in sys.argv:\n time.sleep(.05)\n sys.exit(0)\nwhile True: time.sleep(.01)\n")
            tool.chmod(0o700)
            with patch.dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", "")):
                result = capture.capture("owned-device", root / "stream.log", root / "stop", maximum_seconds=.1)
            self.assertEqual(result["returnCode"], 0)
            command = result["command"]
            self.assertEqual(command[command.index("--timeout") + 1], "1")


if __name__ == "__main__":
    unittest.main()
