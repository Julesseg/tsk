import argparse
import base64
import datetime
import hashlib
import json
import os
import pathlib
import plistlib
import subprocess
import time
from xml.parsers.expat import ExpatError


TERMS = ['spotlight', 'search', 'indexagent', 'springboard', 'widget']


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def decode_apps(raw, entry, run=subprocess.run):
    entry['stdoutBytes'] = len(raw)
    entry['stdoutSHA256'] = hashlib.sha256(raw).hexdigest()
    entry['stdoutPrefixBase64'] = base64.b64encode(raw[:16384]).decode('ascii')
    entry['stdoutPrefixTruncated'] = len(raw) > 16384
    try:
        apps = plistlib.loads(raw)
        entry['format'] = 'plistlib'
    except (ValueError, ExpatError):
        command = ['plutil', '-convert', 'xml1', '-o', '-', '--', '-']
        conversion = {'command': command, 'startedUTC': utc()}
        entry['conversion'] = conversion
        try:
            completed = run(command, input=raw, capture_output=True, timeout=5)
            conversion.update(exit=completed.returncode, stderr=completed.stderr.decode(errors='replace')[:2000])
            if completed.returncode != 0:
                return
            apps = plistlib.loads(completed.stdout)
            entry['format'] = 'plutil'
        except (OSError, ValueError, ExpatError, subprocess.TimeoutExpired) as error:
            conversion['error'] = type(error).__name__ + ': ' + str(error)
            return
        finally:
            conversion['finishedUTC'] = utc()
    if not isinstance(apps, dict):
        entry['error'] = 'Installed application response is not a dictionary'
        return
    entry['apps'] = {key: value for key, value in apps.items() if any(term in json.dumps([key, value], default=str).lower() for term in TERMS)}


def capture(device, observed_pids, run=subprocess.run):
    result = {'device': device, 'time': time.time(), 'startedUTC': utc(), 'observedPIDs': sorted(observed_pids), 'commands': []}
    for arguments in [['listapps', device], ['spawn', device, 'launchctl', 'list']]:
        command = ['xcrun', 'simctl'] + arguments
        entry = {'command': command, 'startedUTC': utc()}
        try:
            completed = run(command, capture_output=True, timeout=5)
            entry['exit'] = completed.returncode
            entry['stderr'] = completed.stderr.decode(errors='replace')[:2000]
            if completed.returncode == 0:
                if arguments[0] == 'listapps':
                    decode_apps(completed.stdout, entry, run)
                else:
                    entry['processes'] = [line for line in completed.stdout.decode(errors='replace').splitlines()
                                          if any(term in line.lower() for term in TERMS) or (line.split() and line.split()[0] in observed_pids)]
                    entry['registrations'] = [{'label': parts[2], 'runningPID': int(parts[0]) if parts[0].isdigit() and int(parts[0]) > 0 else None,
                                               'lastExitStatus': parts[1]} for line in entry['processes'] if len(parts := line.split(maxsplit=2)) == 3]
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            entry['error'] = type(error).__name__ + ': ' + str(error)
        entry['finishedUTC'] = utc()
        result['commands'].append(entry)
    result['finishedUTC'] = utc()
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('device')
    parser.add_argument('output')
    parser.add_argument('--observed-pid', action='append', type=int, default=[])
    arguments = parser.parse_args()
    if os.environ.get('CI') != 'true' or os.environ.get('TEST_RUNNER_TSK_UI_ISOLATED_SIMULATOR') != '1':
        parser.error('Context capture requires the isolated CI simulator lane')
    result = capture(arguments.device, {str(pid) for pid in arguments.observed_pid})
    pathlib.Path(arguments.output).write_text(json.dumps(result, indent=2, default=str) + '\n')
