import base64
import contextlib
import datetime
import io
import os
import plistlib
import tempfile
import importlib.util
import pathlib
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('profiles', pathlib.Path(__file__).with_name('install-provisioning-profiles.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ProfileValidationTests(unittest.TestCase):
    def profile(self):
        return {'Name': 'Owned Ad Hoc', 'UUID': 'fixture', 'ApplicationIdentifierPrefix': ['PREFIX'], 'TeamIdentifier': ['TEAM'], 'ProvisionedDevices': ['owned-device'], 'ExpirationDate': datetime.datetime(2099, 1, 1), 'Entitlements': {'application-identifier': 'PREFIX.com.julesseguin.tsk.widgets', 'com.apple.developer.team-identifier': 'TEAM', 'com.apple.security.application-groups': ['group.com.julesseguin.tsk']}}

    def test_explicit_target_app_group_distribution_and_expiry_are_required(self):
        now = datetime.datetime(2026, 1, 1)
        module.validate(self.profile(), 'com.julesseguin.tsk.widgets', 'TEAM', now)
        for key, value in [('application-identifier', 'PREFIX.*'), ('com.apple.security.application-groups', []), ('com.apple.developer.team-identifier', 'OTHER'), ('get-task-allow', True)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                profile = self.profile()
                profile['Entitlements'][key] = value
                module.validate(profile, 'com.julesseguin.tsk.widgets', 'TEAM', now)
        for key, value in [('ProvisionsAllDevices', True), ('ProvisionedDevices', []), ('ExpirationDate', datetime.datetime(2020, 1, 1))]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                profile = self.profile()
                profile[key] = value
                module.validate(profile, 'com.julesseguin.tsk.widgets', 'TEAM', now)


class ProfileTransportTests(unittest.TestCase):
    def environment(self, root):
        return {'RUNNER_TEMP': str(root / 'temporary'), 'GITHUB_ENV': str(root / 'environment'), 'APPLE_TEAM_ID': 'TEAM', **{secret: base64.b64encode(b'owned fixture').decode('ascii') for _, secret, _ in module.TARGETS}}

    def test_all_missing_secrets_are_reported_before_decode_or_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            environment = self.environment(root)
            environment['APPLE_PROVISIONING_PROFILE'] = 'invalid before preflight'
            environment['APPLE_SHARE_PROVISIONING_PROFILE'] = ''
            environment['APPLE_WIDGET_PROVISIONING_PROFILE'] = ' \t\r\n'
            with mock.patch.dict(os.environ, environment, clear=True), mock.patch.object(pathlib.Path, 'home', return_value=root / 'home'), mock.patch.object(module.base64, 'b64decode') as decode:
                with self.assertRaises(SystemExit) as error:
                    module.main()
                self.assertIn('APPLE_SHARE_PROVISIONING_PROFILE', str(error.exception))
                self.assertIn('APPLE_WIDGET_PROVISIONING_PROFILE', str(error.exception))
                decode.assert_not_called()
            self.assertEqual(list(root.iterdir()), [])

    def test_wrapped_ascii_base64_installs_only_after_existing_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            environment = self.environment(root)
            pathlib.Path(environment['RUNNER_TEMP']).mkdir()
            profiles = {}
            for index, (bundle, secret, _) in enumerate(module.TARGETS):
                payload = (bundle.encode('ascii') + b' owned synthetic profile') * 5
                environment[secret] = ' \t' + base64.encodebytes(payload).decode('ascii').replace('\n', '\r\n') + '\v\f'
                profile = ProfileValidationTests().profile()
                profile.update({'Name': 'Owned ' + bundle, 'UUID': 'owned-' + str(index), 'DeveloperCertificates': [b'owned certificate']})
                profile['Entitlements']['application-identifier'] = 'PREFIX.' + bundle
                profiles[payload] = profile
            def cms(command):
                self.assertEqual(command[:4], ['security', 'cms', '-D', '-i'])
                return plistlib.dumps(profiles[pathlib.Path(command[4]).read_bytes()])
            with mock.patch.dict(os.environ, environment, clear=True), mock.patch.object(pathlib.Path, 'home', return_value=root / 'home'), mock.patch.object(module.subprocess, 'check_output', side_effect=cms), contextlib.redirect_stdout(io.StringIO()):
                module.main()
            installed = root / 'home/Library/MobileDevice/Provisioning Profiles'
            self.assertEqual(len(list(installed.glob('*.mobileprovision'))), 3)
            for path in installed.glob('*.mobileprovision'):
                self.assertIn(path.read_bytes(), profiles)
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            export = plistlib.loads((root / 'temporary/ExportOptions.plist').read_bytes())
            self.assertEqual(export['method'], 'ad-hoc')
            self.assertEqual(set(export['provisioningProfiles']), {target[0] for target in module.TARGETS})
            self.assertEqual(len((root / 'environment').read_text().splitlines()), 3)

    def test_invalid_transport_names_its_secret_without_echoing_value_or_writing(self):
        for invalid in ['Zg==!private-marker', 'Zg', 'Zg==\u00a0', 'Zg==\x1b']:
            with self.subTest(invalid_kind=repr(invalid[-1:])), tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                environment = self.environment(root)
                environment['APPLE_WIDGET_PROVISIONING_PROFILE'] = invalid
                with mock.patch.dict(os.environ, environment, clear=True), mock.patch.object(pathlib.Path, 'home', return_value=root / 'home'), mock.patch.object(module.subprocess, 'check_output') as cms:
                    with self.assertRaises(SystemExit) as error:
                        module.main()
                    self.assertIn('APPLE_WIDGET_PROVISIONING_PROFILE', str(error.exception))
                    self.assertNotIn(invalid, str(error.exception))
                    cms.assert_not_called()
                self.assertEqual(list(root.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
