import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('check-ui-shards.py')


def job(family, partition, conclusion='success', status='completed'):
    return dict(name=f'App · UI shard ({family}, {partition})', status=status, conclusion=conclusion)


class ShardChecksTests(unittest.TestCase):
    def check_jobs(self, jobs, partitions='workspace,row-editing'):
        return subprocess.run(['python3', str(SCRIPT), '--family', 'iPad', '--partitions', partitions], input=json.dumps([dict(jobs=jobs)]), capture_output=True, text=True)

    def test_each_family_requires_all_successful_shards(self):
        for bad in ('failure', 'cancelled', 'skipped', 'timed_out', None):
            with self.subTest(conclusion=bad):
                result = self.check_jobs([job('iPad', 'workspace'), job('iPad', 'row-editing', bad)])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('row-editing', result.stderr)
        self.assertEqual(self.check_jobs([job('iPad', 'workspace'), job('iPad', 'row-editing')]).returncode, 0)

    def test_missing_duplicate_and_running_shards_cannot_pass(self):
        for jobs in ([job('iPad', 'workspace')], [job('iPad', 'workspace'), job('iPad', 'workspace'), job('iPad', 'row-editing')], [job('iPad', 'workspace'), job('iPad', 'row-editing', None, 'in_progress')]):
            with self.subTest(jobs=jobs):
                self.assertNotEqual(self.check_jobs(jobs).returncode, 0)

    def test_other_family_does_not_mask_or_fail_the_selected_family(self):
        good = [job('iPad', 'workspace'), job('iPad', 'row-editing')]
        self.assertEqual(self.check_jobs(good + [job('iPhone', 'workspace', 'failure')]).returncode, 0)
        self.assertNotEqual(self.check_jobs([job('iPhone', 'workspace'), job('iPhone', 'row-editing')]).returncode, 0)

    def test_diagnostics_require_their_single_complete_shard(self):
        self.assertEqual(self.check_jobs([job('iPad', 'all')], 'all').returncode, 0)
        self.assertNotEqual(self.check_jobs([job('iPad', 'workspace')], 'all').returncode, 0)

    def test_api_error_payload_fails_with_an_actionable_message(self):
        result = subprocess.run(['python3', str(SCRIPT), '--family', 'iPad', '--partitions', 'all'], input=json.dumps([{'message': 'Server Error'}]), capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('GitHub jobs response', result.stderr)
        self.assertNotIn('Traceback', result.stderr)

    def fetch_jobs(self, responses):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'responses.json').write_text(json.dumps(responses))
            gh = root / 'gh'
            gh.write_text('''#!/usr/bin/env python3
import json
from pathlib import Path
import sys
root = Path(__file__).parent
calls = root / 'calls.jsonl'
index = len(calls.read_text().splitlines()) if calls.exists() else 0
with calls.open('a') as output:
    output.write(json.dumps(sys.argv[1:]) + '\\n')
response = json.loads((root / 'responses.json').read_text())[index]
print(json.dumps(response.get('pages', [{'message': 'Server Error'}])))
print(response.get('error', ''), file=sys.stderr)
sys.exit(response.get('code', 0))
''')
            gh.chmod(0o755)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'])
            endpoint = 'repos/Julesseg/tsk/actions/runs/123/attempts/2/jobs'
            result = subprocess.run(['python3', str(SCRIPT), '--family', 'iPad', '--partitions', 'workspace,row-editing', '--jobs-endpoint', endpoint], env=environment, capture_output=True, text=True, timeout=20)
            calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()] if (root / 'calls.jsonl').exists() else []
            return result, calls

    def test_transient_api_errors_retry_the_same_attempt_and_require_all_pages(self):
        result, calls = self.fetch_jobs([
            {'code': 1, 'error': 'gh: Server Error (HTTP 502)'},
            {'code': 1, 'error': 'gh: Request timed out (HTTP 504)'},
            {'pages': [{'jobs': [job('iPad', 'workspace')]}, {'jobs': [job('iPad', 'row-editing')]}]},
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [['api', '--paginate', '--slurp', 'repos/Julesseg/tsk/actions/runs/123/attempts/2/jobs']] * 3)

    def test_api_failure_budget_cannot_accept_success_shaped_error_output(self):
        response = {'code': 1, 'error': 'gh: Server Error (HTTP 502)', 'pages': [{'jobs': [job('iPad', 'workspace'), job('iPad', 'row-editing')]}]}
        result, calls = self.fetch_jobs([response] * 3)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('failed after 3 attempts', result.stderr)
        self.assertEqual(len(calls), 3)

    def test_authorization_failure_and_failed_shards_are_not_retried(self):
        for response, message in [
            ({'code': 1, 'error': 'gh: Forbidden (HTTP 403)'}, 'HTTP 403'),
            ({'pages': [{'jobs': [job('iPad', 'workspace'), job('iPad', 'row-editing', 'failure')]}]}, 'row-editing'),
        ]:
            with self.subTest(response=response):
                result, calls = self.fetch_jobs([response])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertEqual(len(calls), 1)

    def test_partial_failed_pagination_is_not_combined_with_the_retry(self):
        result, calls = self.fetch_jobs([
            {'code': 1, 'error': 'gh: Server Error (HTTP 503)', 'pages': [{'jobs': [job('iPad', 'row-editing')]}]},
            {'pages': [{'jobs': [job('iPad', 'workspace')]}]},
        ])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('row-editing): expected one result, found 0', result.stderr)
        self.assertEqual(len(calls), 2)


if __name__ == '__main__':
    unittest.main()
