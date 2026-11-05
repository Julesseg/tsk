import importlib.util
import contextlib
import io
from pathlib import Path
import re
import sys
import subprocess
import tempfile
import unittest


spec = importlib.util.spec_from_file_location('native_tests', Path(__file__).with_name('run-native-tests.py'))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class NativeTestSelectionTests(unittest.TestCase):
    def test_each_method_runs_once_and_sync_cases_are_isolated(self):
        listing = 'TskNativeTests.persistent()\nTskNativeTests.Cases/sync()\nTskNativeAppleTests/intent()\n'
        source = '@Test(.enabled(if: environment["TSK_SYNC_TEST_URL"] != nil))\n    @MainActor func sync() async throws {}'
        ordinary, network = native.test_plan('TskNativeTests', listing, [source])
        self.assertEqual(ordinary, ['TskNativeTests.persistent()'])
        self.assertEqual(network, ['TskNativeTests.Cases/sync()'])
        self.assertFalse(set(ordinary) & set(network))

    def test_platform_attributes_do_not_hide_sync_requirements(self):
        source = '@Test(.enabled(if: env["TSK_SYNC_TEST_URL"] != nil)) @available(macOS 14.0, *)\nfunc indexed() {}'
        self.assertEqual(native.test_plan('TskNativeAppleTests', 'TskNativeAppleTests.indexed()', [source]), ([], ['TskNativeAppleTests.indexed()']))

    def test_multiline_traits_are_isolated_without_classifying_body_reads(self):
        source = '@Test(\n.enabled(if: env["TSK_SYNC_TEST_URL"] != nil)\n)\nfunc synced() {}\n@Test func local() { env["TSK_SYNC_TEST_URL"] }'
        self.assertEqual(native.test_plan('TskNativeTests', 'TskNativeTests/synced()\nTskNativeTests/local()', [source]),
                         (['TskNativeTests/local()'], ['TskNativeTests/synced()']))

    def test_missing_ambiguous_and_duplicate_inventory_fail_closed(self):
        source = '@Test(.enabled(if: env["TSK_SYNC_TEST_URL"] != nil))\nfunc sync() {}'
        for listing in ['', 'TskNativeTests.other()', 'TskNativeTests.One/sync()\nTskNativeTests.Two/sync()', 'TskNativeTests.sync()\nTskNativeTests.sync()']:
            with self.subTest(listing=listing), self.assertRaises(ValueError):
                native.test_plan('TskNativeTests', listing, [source])

    def test_selectors_support_swiftpm_regex_syntax_and_identity_boundaries(self):
        pattern = native.selector(['TskNativeTests.Suite/sync()'])
        for identity in ['TskNativeTests.Suite/sync', 'TskNativeTests/Suite/sync()', 'TskNativeTests.Suite/sync()/']:
            self.assertIsNotNone(re.match(pattern, identity))
        self.assertIsNone(re.match(pattern, 'TskNativeTests.Suite/syncAgain'))
        result = subprocess.run(['grep', '-E', pattern], input='TskNativeTests.Suite/sync()\nTskNativeTests.Suite/syncAgain()\n', text=True, capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, 'TskNativeTests.Suite/sync()\n')

    def test_empty_skipped_and_failed_execution_never_report_success(self):
        with tempfile.TemporaryDirectory() as directory:
            for text, exit_code, expected in [('warning: No matching test cases were run', 0, 1), ('Test sample() skipped.', 0, 1), ('actual failure', 2, 2), ('', 0, 1), ('Test run with 0 tests passed.', 0, 1), ('Test run with 2 tests passed.', 0, 1), ('Test run with 1 test passed.', 0, 0)]:
                with self.subTest(text=text), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    command = [sys.executable, '-c', 'import sys;print(sys.argv[1]);sys.exit(int(sys.argv[2]))', text, str(exit_code)]
                    self.assertEqual(native.run_tests(command, None, Path(directory) / 'test.log', 1), expected)


if __name__ == '__main__':
    unittest.main()
