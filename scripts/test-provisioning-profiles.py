import datetime
import importlib.util
import pathlib
import unittest

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


if __name__ == '__main__':
    unittest.main()
