import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys


ROW = 'TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion'
NATIVE = 'TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys'


def target_stall(output):
    active = False
    deleted = False
    before_input = False
    for line in output.splitlines():
        if 'Test Case ' in line and ' started.' in line:
            active = all(part in line for part in ROW.split('/'))
            deleted = False
            before_input = False
        if not active:
            continue
        if 'Type ' in line and '\x7f' in line and '"task-description" TextField' in line:
            deleted = True
        if "Type ' ' into \"task-description\" TextField" in line:
            before_input = deleted
        if before_input and 'App animations complete notification not received' in line:
            return True
        if 'Synthesize event' in line:
            before_input = False
    return False


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


def inspection_observed(evidence, expected):
    modes = set()
    observations_valid = True
    for path in evidence.glob('keyboard-fixture-*.json'):
        value = json.loads(path.read_text())
        if isinstance(value, list):
            modes.update(row['runtimeCommandInspection'] for row in value
                         if isinstance(row, dict) and 'runtimeCommandInspection' in row)
            for row in value:
                if not isinstance(row, dict) or 'runtimeCommandInspection' not in row:
                    continue
                observations = [node.get('returnCommands') for node in row.get('runtimeCommands', [])]
                observations += [node.get('runtimeReturnCommands') for node in row.get('declarations', [])]
                observations += [node.get('returnCommands') for window in row.get('directWindowResponders', [])
                                 for node in window.get('chain', [])]
                observations_valid &= all(isinstance(item, list) if expected == 'inspected' else item is None
                                          for item in observations)
    return modes == {expected} and observations_valid


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--control-id', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--derived-data', required=True, type=Path)
    options = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    output = options.output.resolve()
    derived = options.derived_data.resolve()
    output.mkdir(parents=True, exist_ok=True)
    inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))
    initial = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
    write_json(output / 'initial-booted.json', initial)
    runtime, control = next((runtime, device) for runtime, devices in inventory['devices'].items()
                            for device in devices if device['udid'] == options.control_id)
    if control['state'] != 'Shutdown':
        raise RuntimeError('The experiment requires a newly created, unbooted control device')
    results = []
    active = None

    def interrupted(signum, frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)

    def stop_active():
        nonlocal active
        if active is not None and active.poll() is None:
            active.terminate()
            try:
                active.wait(timeout=30)
            except subprocess.TimeoutExpired:
                active.kill()
                active.wait()
        if active is not None and active.stdout is not None:
            active.stdout.close()
        active = None

    def run_arm(name, device, setting):
        nonlocal active
        arm = output / name
        evidence = arm / 'evidence'
        evidence.mkdir(parents=True, exist_ok=True)
        environment = dict(os.environ, TEST_RUNNER_TSK_TEST_COMMAND_INSPECTION=setting,
                           TSK_EVENTKIT_EVIDENCE_DIR=str(evidence))
        command = [str(repo / 'scripts/run-ui-tests.sh'), device, '--skip-build',
                   '-project', 'Tsk.xcodeproj', '-scheme', 'Tsk',
                   '-only-testing:TskUITests/' + NATIVE, '-only-testing:TskUITests/' + ROW,
                   '-derivedDataPath', str(derived), '-resultBundlePath', str(arm / 'TestResults.xcresult'),
                   'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'CODE_SIGN_STYLE=Manual', 'DEVELOPMENT_TEAM=']
        write_json(arm / 'invocation.json', dict(arm=name, device=device, runtime=runtime,
                   deviceType=control['deviceTypeIdentifier'], inspection=setting, command=command))
        with (arm / 'console.log').open('w') as log:
            active = subprocess.Popen(command, cwd=repo / 'App', env=environment,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in active.stdout:
                log.write(line)
                print(line, end='', flush=True)
            status = active.wait()
            active.stdout.close()
            active = None
        text = (arm / 'console.log').read_text()
        expected = 'inspected' if setting == '1' else 'not-inspected'
        result = dict(arm=name, device=device, status=status, targetStall=target_stall(text),
                      independentPassed=any(' passed (' in line and all(part in line for part in NATIVE.split('/'))
                                            for line in text.splitlines()),
                      animationWaits=text.count('App animations complete notification not received'),
                      inspectionConfirmed=inspection_observed(evidence, expected))
        if status == 0:
            summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results',
                                'summary', '--path', str(arm / 'TestResults.xcresult')]))
            write_json(arm / 'summary.json', summary)
            result['completeTwoPasses'] = summary['passedTests'] == 2 and summary['failedTests'] == 0 and summary['skippedTests'] == 0
        results.append(result)
        write_json(output / 'results.json', results)
        return result

    try:
        control_result = run_arm('control', options.control_id, '1')
        if (control_result['status'] == 0 or not control_result['targetStall']
                or not control_result['inspectionConfirmed'] or not control_result['independentPassed']):
            write_json(output / 'decision.json', dict(result='inconclusive-control', treatmentStarted=False))
            return 1
        treatment = subprocess.check_output(['xcrun', 'simctl', 'create', 'tsk command inspection treatment',
                    control['deviceTypeIdentifier'], runtime], text=True).strip()
        (output / 'treatment-device.txt').write_text(treatment + '\n')
        try:
            result = run_arm('treatment', treatment, '0')
            supported = (result['status'] == 0 and result.get('completeTwoPasses') is True
                         and result['inspectionConfirmed'] and result['animationWaits'] == 0)
            write_json(output / 'decision.json', dict(result='supports-candidate' if supported else 'not-supported',
                       treatmentStarted=True, canonicalAcceptance=False))
        finally:
            stop_active()
            subprocess.run(['xcrun', 'simctl', 'shutdown', treatment], check=False)
            subprocess.run(['xcrun', 'simctl', 'delete', treatment], check=False)
        return 1
    finally:
        stop_active()
        write_json(output / 'final-booted.json', json.loads(subprocess.check_output(
            ['xcrun', 'simctl', 'list', 'devices', 'booted', '--json'])))


if __name__ == '__main__':
    sys.exit(main())
