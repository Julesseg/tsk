#!/usr/bin/env python3
import argparse
import datetime
import json
import math
import pathlib
import re
import signal
import subprocess
import sys
import time


class IndexWaitSampler:
    def __init__(self, path):
        self.path = path
        self.log = path.open(errors='replace')
        self.process = None
        self.record = None

    def tick(self):
        if self.record is None:
            while True:
                position = self.log.tell()
                line = self.log.readline()
                if not line:
                    break
                if not line.endswith('\n'):
                    self.log.seek(position)
                    break
                match = re.search(r'\bsearchd\[(\d+):[^\]]+\].*Starting the indexing watchdog.*bundleID:com\.julesseguin\.tsk(?:\s|,|$)', line)
                if match:
                    command = ['sudo', '-n', sys.executable, '-I', str(pathlib.Path(__file__).with_name('sample-spotlight-index.py')), match[1], str(self.path.with_suffix('.index-wait.sample.txt'))]
                    self.record = dict(command=command, trigger=line.strip(), startedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), timeoutSeconds=12)
                    try:
                        with self.path.with_suffix('.index-wait.helper.log').open('wb') as output:
                            self.process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
                        self.record['pid'] = self.process.pid
                        self.deadline = time.monotonic() + 12
                    except OSError as error:
                        self.record['error'] = str(error)
                    break
        if self.process is not None and self.process.poll() is None and time.monotonic() >= self.deadline:
            self.record['timedOut'] = True
            self.process.kill()
            self.process.wait(timeout=1)

    def finish(self):
        self.log.close()
        if self.record is None:
            return dict(state='owned-index-watchdog-not-observed')
        if self.process is not None:
            try:
                if self.process.poll() is None:
                    self.record['stoppedBy'] = 'capture-completion'
                    self.process.terminate()
                    try:
                        self.process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        self.process.kill()
                        self.process.wait(timeout=1)
            except (OSError, subprocess.TimeoutExpired) as error:
                self.record['cleanupError'] = str(error)
            self.record.update(returnCode=self.process.returncode, reaped=self.process.returncode is not None)
        self.record['finishedUTC'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        return self.record


def capture(device, output, stop, maximum_seconds=60, sample_index_wait=False):
    path = pathlib.Path(output)
    stop = pathlib.Path(stop)
    predicate = 'process == "corespotlightd" OR subsystem CONTAINS[c] "corespotlight" OR subsystem BEGINSWITH[c] "com.apple.spotlight" OR (process == "searchd" AND (eventMessage CONTAINS[c] "IndexAgent" OR eventMessage CONTAINS[c] "SearchAgent")) OR (process == "Tsk" AND subsystem != "com.apple.dt.xctest" AND eventMessage CONTAINS[c] "spotlight")'
    command = ['xcrun', 'simctl', 'spawn', device, 'log', 'stream', '--timeout', str(max(1, math.ceil(maximum_seconds))), '--style', 'compact', '--level', 'debug', '--predicate', predicate]
    metadata = dict(device=device, startedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), maximumSeconds=maximum_seconds, command=command)
    child = None
    sampler = None
    interrupted = None
    old_handlers = {}

    def interrupt(number, _frame):
        nonlocal interrupted
        interrupted = number

    for number in (signal.SIGINT, signal.SIGTERM):
        old_handlers[number] = signal.signal(number, interrupt)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('wb') as log:
            child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            if sample_index_wait:
                sampler = IndexWaitSampler(path)
            deadline = time.monotonic() + maximum_seconds
            while child.poll() is None and not stop.exists() and interrupted is None:
                if sampler is not None:
                    sampler.tick()
                time.sleep(min(0.2, maximum_seconds))
            metadata['stoppedBy'] = 'signal' if interrupted is not None else 'test-completion' if stop.exists() else 'duration' if time.monotonic() >= deadline else 'log-process-exit'
            metadata['signal'] = interrupted
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)
            metadata['returnCode'] = child.returncode
    except Exception as error:
        metadata['error'] = str(error)
    finally:
        if sampler is not None:
            metadata['indexWaitSample'] = sampler.finish()
        if child is not None and child.poll() is None:
            child.kill()
            child.wait(timeout=5)
        for number, handler in old_handlers.items():
            signal.signal(number, handler)
        metadata['finishedUTC'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        path.with_suffix('.metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    return metadata


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('device')
    parser.add_argument('output')
    parser.add_argument('stop')
    parser.add_argument('--maximum-seconds', type=int, default=60, choices=range(1, 601), metavar='1..600')
    parser.add_argument('--sample-index-wait', action='store_true')
    args = parser.parse_args()
    capture(args.device, args.output, args.stop, args.maximum_seconds, args.sample_index_wait)
