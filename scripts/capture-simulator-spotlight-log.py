#!/usr/bin/env python3
import datetime
import json
import pathlib
import signal
import subprocess
import sys
import time


def capture(device, output, stop, maximum_seconds=60):
    path = pathlib.Path(output)
    stop = pathlib.Path(stop)
    predicate = 'process == "corespotlightd" OR subsystem CONTAINS[c] "corespotlight" OR subsystem BEGINSWITH[c] "com.apple.spotlight" OR (process == "searchd" AND (eventMessage CONTAINS[c] "IndexAgent" OR eventMessage CONTAINS[c] "SearchAgent")) OR (process == "Tsk" AND subsystem != "com.apple.dt.xctest" AND eventMessage CONTAINS[c] "spotlight")'
    command = ['xcrun', 'simctl', 'spawn', device, 'log', 'stream', '--style', 'compact', '--level', 'debug', '--predicate', predicate]
    metadata = dict(device=device, startedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), maximumSeconds=maximum_seconds, command=command)
    child = None
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
            deadline = time.monotonic() + maximum_seconds
            while child.poll() is None and not stop.exists() and interrupted is None and time.monotonic() < deadline:
                time.sleep(min(0.2, maximum_seconds))
            metadata['stoppedBy'] = 'signal' if interrupted is not None else 'test-completion' if stop.exists() else 'duration' if child.poll() is None else 'log-process-exit'
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
        if child is not None and child.poll() is None:
            child.kill()
            child.wait(timeout=5)
        for number, handler in old_handlers.items():
            signal.signal(number, handler)
        metadata['finishedUTC'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        path.with_suffix('.metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    return metadata


if __name__ == '__main__':
    capture(*sys.argv[1:])
