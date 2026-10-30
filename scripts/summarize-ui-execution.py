import argparse
import json
import os
from pathlib import Path
import subprocess


def test_methods(nodes):
    result = []
    for node in nodes:
        if node.get('nodeType') == 'Test Case':
            result.append(dict(name=node.get('nodeIdentifier', node['name']), result=node.get('result'), seconds=node.get('durationInSeconds')))
        result.extend(test_methods(node.get('children', [])))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--family', required=True)
    parser.add_argument('--partition', required=True)
    parser.add_argument('--suite', required=True)
    args = parser.parse_args()
    record = dict(source=os.environ.get('GITHUB_SHA'), run=os.environ.get('GITHUB_RUN_ID'), attempt=os.environ.get('GITHUB_RUN_ATTEMPT'), suite=args.suite, family=args.family, partition=args.partition, bundles=[], errors=[])
    for path in sorted(Path('App').glob('TestResults*.xcresult')):
        bundle = dict(path=str(path))
        for command in ('summary', 'tests'):
            try:
                raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', command, '--path', str(path), '--compact'], text=True, timeout=20)
                data = json.loads(raw)
                bundle[command] = test_methods(data.get('testNodes', [])) if command == 'tests' else data
            except (subprocess.SubprocessError, ValueError) as error:
                record['errors'].append(dict(path=str(path), command=command, error=str(error)))
        record['bundles'].append(bundle)
    output = Path('.build/ui-execution.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record, indent=2) + '\n')
    rows = [f'### {args.family} / {args.partition} / {args.suite}', '', f'Source `{record["source"]}`, attempt {record["attempt"]}.', '', '| Bundle | Result | Passed | Failed | Skipped | XCTest elapsed |', '| --- | --- | ---: | ---: | ---: | ---: |']
    for bundle in record['bundles']:
        summary = bundle.get('summary', {})
        seconds = max(0, summary.get('finishTime', 0) - summary.get('startTime', 0))
        rows.append(f'| {bundle["path"]} | {summary.get("result", "unavailable")} | {summary.get("passedTests", 0)} | {summary.get("failedTests", 0)} | {summary.get("skippedTests", 0)} | {seconds / 60:.1f} min |')
    methods = [method for bundle in record['bundles'] for method in bundle.get('tests', [])]
    if methods:
        rows += ['', 'Slowest completed methods:', '']
        for method in sorted(methods, key=lambda item: item.get('seconds') or 0, reverse=True)[:10]:
            rows.append(f'- `{method["name"]}`: {method["seconds"]} s ({method["result"]})')
    if not record['bundles']:
        rows += ['', 'No result bundle: inspect setup, simulator and transport evidence.']
    if record['errors']:
        rows += ['', 'Some result data could not be extracted; raw bundles remain the acceptance evidence.']
    print('\n'.join(rows))
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write('\n'.join(rows) + '\n')


if __name__ == '__main__':
    main()
