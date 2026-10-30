import json
import importlib.util
from pathlib import Path
import subprocess
import unittest

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


if __name__ == '__main__':
    unittest.main()
