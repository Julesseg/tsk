import json
import os
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name('check-ui-shards.py')
spec = importlib.util.spec_from_file_location('shards', SCRIPT)
shards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shards)


def job(family, partition, conclusion='success', status='completed'):
    return dict(name=f'App · UI shard ({family}, {partition})', status=status, conclusion=conclusion)


class ShardChecksTests(unittest.TestCase):
    def poll(self, responses, timeout=3):
        now = [0]
        calls = []
        def fetch(remaining):
            calls.append(remaining)
            return responses[min(len(calls) - 1, len(responses) - 1)]
        def sleep(seconds):
            now[0] += seconds
        return shards.wait_for_shards(fetch, 'iPad', ['all'], timeout=timeout, interval=1, clock=lambda: now[0], sleep=sleep), calls

    def test_stale_running_or_missing_api_state_converges_without_replaying_tests(self):
        success = [job('iPad', 'all')]
        result, calls = self.poll([[], [job('iPad', 'all', None, 'in_progress')], success])
        self.assertEqual(result, success)
        self.assertEqual(calls, [3, 2, 1])

    def test_api_staleness_has_a_fixed_deadline(self):
        with self.assertRaisesRegex(ValueError, 'did not converge'):
            self.poll([[job('iPad', 'all', None, 'in_progress')]])

    def test_terminal_failure_and_duplicates_are_not_retried(self):
        for response in ([job('iPad', 'all', 'failure')], [job('iPad', 'all'), job('iPad', 'all')]):
            with self.subTest(response=response), self.assertRaises(ValueError):
                self.poll([response, [job('iPad', 'all')]])

    def test_late_success_cannot_pass_the_convergence_deadline(self):
        now = [0]
        def fetch(remaining):
            now[0] += remaining + 1
            return [job('iPad', 'all')]
        with self.assertRaisesRegex(ValueError, 'did not converge before deadline'):
            shards.wait_for_shards(fetch, 'iPad', ['all'], timeout=3, clock=lambda: now[0])

    def test_terminal_failure_outranks_another_pending_partition(self):
        with self.assertRaisesRegex(ValueError, 'completed/failure'):
            shards.validate([job('iPad', 'row-editing', 'failure')], 'iPad', ['workspace', 'row-editing'])

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
        self.assertIn('row-editing): missing', result.stderr)
        self.assertEqual(len(calls), 2)

    def test_transient_fetch_backoff_stays_within_gate_budget(self):
        now = [0]
        def request(*args, **kwargs):
            now[0] += 2
            raise subprocess.TimeoutExpired(args[0], kwargs['timeout'])
        def sleep(seconds):
            now[0] += seconds
        with patch.object(shards.time, 'monotonic', side_effect=lambda: now[0]), \
             patch.object(shards.time, 'sleep', side_effect=sleep), \
             patch.object(shards.subprocess, 'run', side_effect=request) as run:
            with self.assertRaisesRegex(ValueError, 'exceeded gate deadline'):
                shards.fetch_jobs('Julesseg/tsk', 77, 1, 3)
        self.assertEqual(now[0], 3)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.kwargs['timeout'], 3)


if __name__ == '__main__':
    unittest.main()
