import argparse
import importlib.util
import json
import os
from pathlib import Path


spec = importlib.util.spec_from_file_location('selection', Path(__file__).with_name('ui-test-selection.py'))
selection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selection)


def plan(suite):
    families = ['iPhone'] if suite == 'diagnostic' else ['iPhone', 'iPad']
    partitions = ['workspace', 'row-editing'] if suite == 'full' else ['all']
    workers = []
    for family in families:
        for partition in partitions:
            filters = selection.selection(suite, family, partition)
            workers.append(dict(family=family, partition=partition, native_keyboard=selection.requires_native_keyboard(filters), server=selection.requires_sync_server(filters), peer=selection.requires_sync_peer(filters)))
    return dict(matrix=dict(include=workers), families=families, partitions=partitions, suite=suite,
                server=any(worker['server'] for worker in workers), peer=any(worker['peer'] for worker in workers))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('suite', choices=['smoke', 'full', 'diagnostic', 'keyboard', 'text'])
    args = parser.parse_args()
    result = plan(args.suite)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            for key, value in result.items():
                output.write(key + '=' + (value if isinstance(value, str) else json.dumps(value, separators=(',', ':'))) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
