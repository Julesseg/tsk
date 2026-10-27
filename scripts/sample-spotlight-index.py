import json
import pathlib
import signal
import subprocess
import sys


def sample(pid, output, executable='/usr/bin/sample', timeout=10):
    output = pathlib.Path(output)
    process = None
    receipt = dict(targetPID=pid, timeoutSeconds=timeout)
    handlers = {}

    def interrupt(number, _frame):
        receipt['signal'] = number
        raise SystemExit(128 + number)

    for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        handlers[number] = signal.signal(number, interrupt)
    try:
        process = subprocess.Popen([executable, str(pid), '2', '1', '-mayDie', '-file', str(output)], start_new_session=True)
        receipt['pid'] = process.pid
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            receipt['timedOut'] = True
            return 124
    finally:
        if process is not None:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=1)
            receipt.update(returnCode=process.returncode, reaped=True)
        if output.exists():
            output.chmod(0o644)
        metadata = output.with_suffix('.metadata.json')
        metadata.write_text(json.dumps(receipt, indent=2) + '\n')
        metadata.chmod(0o644)
        for number, handler in handlers.items():
            signal.signal(number, handler)


if __name__ == '__main__':
    pid = int(sys.argv[1])
    if pid <= 1:
        raise SystemExit('Expected a simulator worker PID')
    raise SystemExit(sample(pid, sys.argv[2]))
