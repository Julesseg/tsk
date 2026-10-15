import json
import pathlib
import plistlib
import subprocess
import sys
import time


device, output = sys.argv[1:3]
result = {'device': device, 'time': time.time(), 'commands': []}
for arguments in [['listapps', device], ['spawn', device, 'launchctl', 'list']]:
    command = ['xcrun', 'simctl'] + arguments
    entry = {'command': command}
    try:
        completed = subprocess.run(command, capture_output=True, timeout=5)
        entry['exit'] = completed.returncode
        entry['stderr'] = completed.stderr.decode(errors='replace')[:2000]
        if completed.returncode == 0:
            if arguments[0] == 'listapps':
                apps = plistlib.loads(completed.stdout)
                entry['apps'] = {key: value for key, value in apps.items() if any(term in json.dumps([key, value]).lower() for term in ['spotlight', 'search', 'springboard'])}
            else:
                entry['processes'] = [line for line in completed.stdout.decode(errors='replace').splitlines() if any(term in line.lower() for term in ['spotlight', 'search', 'springboard'])]
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        entry['error'] = type(error).__name__ + ': ' + str(error)
    result['commands'].append(entry)
pathlib.Path(output).write_text(json.dumps(result, indent=2, default=str))
