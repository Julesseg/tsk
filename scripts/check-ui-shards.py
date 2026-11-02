import argparse
import json
import re
import subprocess
import sys
import time


def validate(jobs, family, partitions):
    for partition in partitions:
        name = f'App · UI shard ({family}, {partition})'
        matches = [job for job in jobs if job['name'] == name]
        if len(matches) != 1:
            raise ValueError(f'{name}: expected one result, found {len(matches)}')
        job = matches[0]
        if job['status'] != 'completed' or job['conclusion'] != 'success':
            raise ValueError(f'{name}: {job["status"]}/{job["conclusion"]}')


def jobs_from_pages(pages):
    if not isinstance(pages, list) or not pages:
        raise ValueError('Invalid GitHub jobs response: expected paginated job lists')
    jobs = []
    for page in pages:
        if not isinstance(page, dict) or not isinstance(page.get('jobs'), list):
            raise ValueError('Invalid GitHub jobs response: expected a jobs list on every page')
        for job in page['jobs']:
            if not isinstance(job, dict) or not {'name', 'status', 'conclusion'} <= job.keys():
                raise ValueError('Invalid GitHub jobs response: incomplete job result')
            jobs.append(job)
    return jobs


def fetch_pages(endpoint):
    for attempt in range(3):
        try:
            result = subprocess.run(['gh', 'api', '--paginate', '--slurp', endpoint], capture_output=True, text=True, timeout=45)
        except subprocess.TimeoutExpired:
            error = 'GitHub jobs request timed out'
        except OSError as error:
            raise ValueError(f'Could not request GitHub jobs: {error}') from error
        else:
            if result.returncode == 0:
                return json.loads(result.stdout)
            error = result.stderr.strip() or f'GitHub CLI exited with status {result.returncode}'
            if not re.search(r'HTTP (429|500|502|503|504)\b', error):
                raise ValueError(f'Could not request GitHub jobs: {error}')
        if attempt == 2:
            raise ValueError(f'GitHub jobs request failed after 3 attempts: {error}')
        print(f'Transient GitHub jobs error; retrying request ({attempt + 1}/3): {error}', file=sys.stderr)
        time.sleep(2 ** (attempt + 1))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--family', choices=['iPhone', 'iPad'], required=True)
    parser.add_argument('--partitions', choices=['all', 'workspace,row-editing'], required=True)
    parser.add_argument('--jobs-endpoint')
    args = parser.parse_args()
    try:
        pages = fetch_pages(args.jobs_endpoint) if args.jobs_endpoint else json.load(sys.stdin)
        validate(jobs_from_pages(pages), args.family, args.partitions.split(','))
    except ValueError as error:
        parser.exit(1, str(error) + '\n')
    print(f'All {args.family} UI shards passed')


if __name__ == '__main__':
    main()
