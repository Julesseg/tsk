import argparse
import json
import sys


def validate(jobs, family, partitions):
    for partition in partitions:
        name = f'App · UI shard ({family}, {partition})'
        matches = [job for job in jobs if job['name'] == name]
        if len(matches) != 1:
            raise ValueError(f'{name}: expected one result, found {len(matches)}')
        job = matches[0]
        if job['status'] != 'completed' or job['conclusion'] != 'success':
            raise ValueError(f'{name}: {job["status"]}/{job["conclusion"]}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--family', choices=['iPhone', 'iPad'], required=True)
    parser.add_argument('--partitions', choices=['all', 'workspace,row-editing'], required=True)
    args = parser.parse_args()
    pages = json.load(sys.stdin)
    try:
        validate([job for page in pages for job in page['jobs']], args.family, args.partitions.split(','))
    except ValueError as error:
        parser.exit(1, str(error) + '\n')
    print(f'All {args.family} UI shards passed')


if __name__ == '__main__':
    main()
