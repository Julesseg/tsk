import argparse
import io
import json
from pathlib import Path
import subprocess
import zipfile


def api(endpoint):
    return json.loads(subprocess.check_output(['gh', 'api', endpoint], text=True))


def matching_run(runs, sha, branch, suite, expected_identity=None, load_identity=None):
    matches = sorted((run for run in runs if run['head_sha'] == sha and run['head_branch'] == branch
                      and run['event'] == 'workflow_dispatch' and run['display_title'].startswith('CI · ' + suite + ' · ')), key=lambda run: run['id'], reverse=True)
    for run in matches:
        if run['status'] in ('queued', 'in_progress', 'requested', 'waiting', 'pending'):
            if expected_identity is not None:
                actual = load_identity(run)
                if actual is None:
                    raise ValueError('Matching active run is awaiting its execution identity: ' + run['html_url'])
                if actual != expected_identity:
                    raise ValueError('Matching active run has a different execution identity: ' + run['html_url'])
            return run
        if run['conclusion'] == 'success' and expected_identity is not None and load_identity(run) == expected_identity:
            return run
    return None


def run_identity(repository, run):
    artifacts = api(f'repos/{repository}/actions/runs/{run["id"]}/artifacts?per_page=100')['artifacts']
    matches = [item for item in artifacts if item['name'] == 'ui-execution-identity' and not item['expired']]
    if len(matches) != 1:
        return None
    archive = subprocess.check_output(['gh', 'api', f'repos/{repository}/actions/artifacts/{matches[0]["id"]}/zip'])
    with zipfile.ZipFile(io.BytesIO(archive)) as source:
        return json.loads(source.read('ui-products.tar.json'))['identity']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', default='Julesseg/tsk')
    parser.add_argument('--ref', required=True)
    parser.add_argument('--suite', required=True, choices=['smoke', 'full', 'diagnostic', 'keyboard', 'text'])
    parser.add_argument('--reason', required=True)
    parser.add_argument('--identity', type=Path)
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    if not args.reason.strip():
        parser.error('Explain why this coverage is needed')
    sha = api(f'repos/{args.repo}/commits/{args.ref}')['sha']
    runs = api(f'repos/{args.repo}/actions/workflows/ci.yml/runs?head_sha={sha}&event=workflow_dispatch&per_page=100')['workflow_runs']
    identity = json.loads(args.identity.read_text()) if args.identity else None
    if identity and 'identity' in identity:
        identity = identity['identity']
    if identity is not None and identity.get('source') != sha:
        parser.error('Expected execution identity belongs to a different source revision')
    try:
        existing = matching_run(runs, sha, args.ref, args.suite, identity, lambda run: run_identity(args.repo, run))
    except ValueError as error:
        parser.error(str(error))
    if existing and not args.force:
        print(('Reusing verified completed coverage: ' if existing['status'] == 'completed' else 'Matching coverage is already pending; verify its result and identity: ') + existing['html_url'])
        return
    failed = [run for run in runs if run['head_branch'] == args.ref and run['display_title'].startswith('CI · ' + args.suite + ' · ') and run['conclusion'] == 'failure']
    if failed and not args.force:
        parser.error('Matching coverage already failed. Inspect it and rerun only the failed job; --force requires an explicit new experiment reason.')
    if api(f'repos/{args.repo}/commits/{args.ref}')['sha'] != sha:
        parser.error('Branch moved during admission; resolve the new source before dispatching')
    command = ['gh', 'workflow', 'run', 'ci.yml', '--repo', args.repo, '--ref', args.ref,
               '-f', 'ui_suite=' + ('smoke' if args.suite == 'diagnostic' else args.suite), '-f', 'reason=' + args.reason,
               '-f', 'expected_sha=' + sha,
               '-f', 'diagnostic_only=' + ('true' if args.suite == 'diagnostic' else 'false')]
    subprocess.run(command, check=True)
    print(f'Requested {args.suite} at {sha}; verify the resulting run SHA before accepting it.')


if __name__ == '__main__':
    main()
