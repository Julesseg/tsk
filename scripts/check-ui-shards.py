import argparse
import json
import os
import subprocess
import sys
import time


class PendingShards(ValueError):
    pass


def validate(jobs, family, partitions):
    pending = []
    for partition in partitions:
        name = f'App · UI shard ({family}, {partition})'
        matches = [job for job in jobs if job['name'] == name]
        if not matches:
            pending.append(name + ': missing')
            continue
        if len(matches) != 1:
            raise ValueError(f'{name}: expected one result, found {len(matches)}')
        job = matches[0]
        if job['status'] != 'completed':
            pending.append(f'{name}: {job["status"]}/{job["conclusion"]}')
        elif job['conclusion'] != 'success':
            raise ValueError(f'{name}: {job["status"]}/{job["conclusion"]}')
    if pending:
        raise PendingShards('; '.join(pending))


def wait_for_shards(fetch, family, partitions, timeout=90, interval=2, clock=time.monotonic, sleep=time.sleep):
    deadline = clock() + timeout
    while True:
        jobs = fetch(max(0, deadline - clock()))
        try:
            validate(jobs, family, partitions)
            return jobs
        except PendingShards as error:
            remaining = deadline - clock()
            if remaining <= 0:
                raise ValueError('Shard status did not converge: ' + str(error)) from error
            print(str(error) + '; refreshing GitHub job state', file=sys.stderr)
            sleep(min(interval, remaining))


def fetch_jobs(repository, run_id, attempt, remaining):
    endpoint = f'repos/{repository}/actions/runs/{run_id}/attempts/{attempt}/jobs'
    result = subprocess.run(['gh', 'api', '--paginate', '--slurp', endpoint], capture_output=True, text=True, check=True, timeout=max(0.1, min(30, remaining)))
    return [job for page in json.loads(result.stdout) for job in page['jobs']]


def write_summary(jobs, family, partitions):
    path = os.environ.get('GITHUB_STEP_SUMMARY')
    if not path:
        return
    from datetime import datetime
    rows = [f'### {family} UI execution', '', '| Worker | Outcome | Queue | Runner time |', '| --- | --- | ---: | ---: |']
    for job in jobs:
        if job['name'] not in {f'App · UI shard ({family}, {partition})' for partition in partitions} | {'App · Shared UI products'}:
            continue
        def elapsed(start, end):
            if not start or not end:
                return '—'
            return f'{max(0, (datetime.fromisoformat(end.replace("Z", "+00:00")) - datetime.fromisoformat(start.replace("Z", "+00:00"))).total_seconds()) / 60:.1f} min'
        queue = elapsed(job.get('created_at'), job.get('started_at')) if job.get('runner_id') else 'unassigned'
        runtime = elapsed(job.get('started_at'), job.get('completed_at')) if job.get('runner_id') else '0 min'
        name = job['name']
        if job.get('html_url'):
            name = f'[{name}]({job["html_url"]})'
        rows.append(f'| {name} | {job["conclusion"]} | {queue} | {runtime} |')
    with open(path, 'a') as output:
        output.write('\n'.join(rows) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--family', choices=['iPhone', 'iPad'], required=True)
    parser.add_argument('--partitions', required=True)
    parser.add_argument('--run-id', type=int)
    parser.add_argument('--attempt', type=int, default=int(os.environ.get('GITHUB_RUN_ATTEMPT', '1')))
    parser.add_argument('--repository', default=os.environ.get('GITHUB_REPOSITORY'))
    parser.add_argument('--timeout-seconds', type=float, default=90)
    args = parser.parse_args()
    partitions = args.partitions.split(',')
    jobs = []
    try:
        if args.run_id:
            if not args.repository or args.timeout_seconds <= 0:
                raise ValueError('A repository and positive polling deadline are required')
            def refresh(remaining):
                nonlocal jobs
                jobs = fetch_jobs(args.repository, args.run_id, args.attempt, remaining)
                return jobs
            wait_for_shards(refresh, args.family, partitions, args.timeout_seconds)
        else:
            jobs = [job for page in json.load(sys.stdin) for job in page['jobs']]
            validate(jobs, args.family, partitions)
    except (ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, str(error) + '\n')
    finally:
        write_summary(jobs, args.family, partitions)
    print(f'All {args.family} UI shards passed')


if __name__ == '__main__':
    main()
