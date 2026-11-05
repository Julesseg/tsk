import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent


def test_plan(target, listing, sources):
    available = sorted(line.strip() for line in listing.splitlines() if line.startswith((target + '.', target + '/')))
    if not available or len(set(available)) != len(available):
        raise ValueError('Expected a nonempty, unique Native test inventory for ' + target)
    network = set()
    for source in sources:
        for declaration in re.finditer(r'@Test(?P<attributes>(?:(?!@Test).)*?)\bfunc\s+(?P<name>\w+)\(', source, re.DOTALL):
            if 'TSK_SYNC_TEST_URL' not in declaration['attributes']:
                continue
            name = declaration['name']
            matches = [test for test in available if re.search(r'[./]' + re.escape(name) + r'\(\)$', test)]
            if len(matches) != 1:
                raise ValueError('Expected exactly one discovered sync test for ' + name)
            if matches[0] in network:
                raise ValueError('Duplicate sync declaration: ' + name)
            network.add(matches[0])
    return [test for test in available if test not in network], sorted(network)


def selector(tests):
    names = [re.escape(test.removesuffix('()')).replace(r'\.', '[./]', 1) for test in tests]
    return '^(' + '|'.join(names) + r')(\(|/|$)'


def run_tests(command, environment, log, expected_count):
    incomplete = False
    completed = []
    with log.open('w') as receipt:
        with subprocess.Popen(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
            for line in process.stdout:
                print(line, end='', flush=True)
                receipt.write(line)
                if 'No matching test cases were run' in line or re.search(r'\bTest [^\n]+ skipped\.', line):
                    incomplete = True
                if summary := re.search(r'Test run with (\d+) tests?\b.* passed', line):
                    completed.append(int(summary[1]))
            status = process.wait()
    incomplete = incomplete or completed != [expected_count]
    if incomplete:
        print(f'Native coverage is incomplete: expected {expected_count} completed methods without skips; receipts {completed}.', file=sys.stderr)
    return status or int(incomplete)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', choices=('TskNativeTests', 'TskNativeAppleTests'), required=True)
    parser.add_argument('--server', required=True)
    parser.add_argument('--taskwarrior', required=True)
    parser.add_argument('--probe', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--skip-build', action='store_true')
    options = parser.parse_args()
    environment = dict(os.environ)
    taskwarrior = str(Path(options.taskwarrior).resolve())
    if subprocess.check_output([taskwarrior, '--version'], text=True).strip() != '3.5.0':
        parser.error('Native conformance requires Taskwarrior 3.5.0')
    environment['TSK_TASKWARRIOR_BINARY'] = taskwarrior
    environment['TSK_NATIVE_PROBE_BINARY'] = str(Path(options.probe).resolve())
    for key in list(environment):
        if key.startswith('TSK_SYNC_TEST_') or key == 'TSK_SPOTLIGHT_REAL_INDEX_TEST':
            del environment[key]
    if options.target == 'TskNativeAppleTests':
        environment['TSK_SPOTLIGHT_REAL_INDEX_TEST'] = '1'
    output = Path(options.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    swift = ['swift', 'test', '--package-path', str(ROOT / 'Native')]
    listing = subprocess.check_output(swift + ['list'] + (['--skip-build'] if options.skip_build else []), env=environment, text=True)
    sources = [path.read_text() for path in (ROOT / 'Native/Tests' / options.target).glob('*.swift')]
    ordinary, network = test_plan(options.target, listing, sources)
    (output / 'selection.json').write_text(json.dumps(dict(target=options.target, ordinary=ordinary, isolated_sync=network), indent=2) + '\n')
    commands = []
    if ordinary:
        command = swift + ['--skip-build', '--filter', '^' + options.target + r'[./]']
        if network:
            command += ['--skip', selector(network)]
        commands.append(('ordinary', command, len(ordinary)))
    for test in network:
        command = [sys.executable, str(ROOT / 'scripts/with-sync-fixture.py'), '--server', str(Path(options.server).resolve()),
                   '--output', str(output / 'sync'), '--'] + swift + ['--skip-build', '--filter', selector([test])]
        commands.append((test, command, 1))
    outcomes = []
    for name, command, expected_count in commands:
        print('Native tests: ' + name, flush=True)
        log = output / (re.sub(r'[^A-Za-z0-9_-]', '_', name) + '.log')
        status = run_tests(command, environment, log, expected_count)
        outcomes.append(dict(selection=name, expected_count=expected_count, status=status))
        (output / 'outcomes.json').write_text(json.dumps(outcomes, indent=2) + '\n')
    return int(any(outcome['status'] != 0 for outcome in outcomes))


if __name__ == '__main__':
    raise SystemExit(main())
