import base64
import datetime
import os
import pathlib
import plistlib
import subprocess

TARGETS = (
    ('com.julesseguin.tsk', 'APPLE_PROVISIONING_PROFILE', 'TSK_APP_PROVISIONING_PROFILE'),
    ('com.julesseguin.tsk.share', 'APPLE_SHARE_PROVISIONING_PROFILE', 'TSK_SHARE_PROVISIONING_PROFILE'),
    ('com.julesseguin.tsk.widgets', 'APPLE_WIDGET_PROVISIONING_PROFILE', 'TSK_WIDGET_PROVISIONING_PROFILE'),
)


def validate(profile, bundle, team, now):
    entitlements = profile.get('Entitlements', {})
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    identifiers = {prefix + '.' + bundle for prefix in prefixes}
    if entitlements.get('application-identifier') not in identifiers:
        raise ValueError(f'Profile must explicitly authorize {bundle}')
    if team not in profile.get('TeamIdentifier', []) or entitlements.get('com.apple.developer.team-identifier') != team:
        raise ValueError(f'Profile for {bundle} belongs to another team')
    if 'group.com.julesseguin.tsk' not in entitlements.get('com.apple.security.application-groups', []):
        raise ValueError(f'Profile for {bundle} must authorize group.com.julesseguin.tsk')
    if not profile.get('ProvisionedDevices') or entitlements.get('get-task-allow') or profile.get('ProvisionsAllDevices'):
        raise ValueError(f'Profile for {bundle} must use Ad Hoc distribution')
    if profile['ExpirationDate'] <= now:
        raise ValueError(f'Profile for {bundle} has expired')
    if not profile.get('Name') or not profile.get('UUID') or any(c in profile['Name'] for c in '\r\n'):
        raise ValueError(f'Profile for {bundle} has invalid identity metadata')


def main():
    temporary = pathlib.Path(os.environ['RUNNER_TEMP'])
    installed = pathlib.Path.home() / 'Library/MobileDevice/Provisioning Profiles'
    installed.mkdir(parents=True, exist_ok=True)
    mappings = {}
    environment = []
    profiles = []
    for bundle, secret, setting in TARGETS:
        raw = os.environ.get(secret)
        if not raw:
            raise SystemExit(f'Missing {secret}: create an Ad Hoc profile for {bundle} with group.com.julesseguin.tsk enabled')
        encoded = temporary / (bundle + '.mobileprovision')
        encoded.write_bytes(base64.b64decode(raw, validate=True))
        encoded.chmod(0o600)
        decoded = subprocess.check_output(['security', 'cms', '-D', '-i', str(encoded)])
        profile = plistlib.loads(decoded)
        validate(profile, bundle, os.environ['APPLE_TEAM_ID'], datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None))
        profiles.append(profile)
        mappings[bundle] = profile['Name']
        environment.append(setting + '=' + profile['Name'])
    devices = [set(p['ProvisionedDevices']) for p in profiles]
    if not all(group == devices[0] for group in devices):
        raise SystemExit('App, Share, and Widget profiles must authorize the same Ad Hoc devices')
    certificates = [set(p.get('DeveloperCertificates', [])) for p in profiles]
    if not set.intersection(*certificates):
        raise SystemExit('App, Share, and Widget profiles must authorize a common distribution certificate')
    for (bundle, _, _), profile in zip(TARGETS, profiles):
        destination = installed / (profile['UUID'] + '.mobileprovision')
        destination.write_bytes((temporary / (bundle + '.mobileprovision')).read_bytes())
        destination.chmod(0o600)
    with open(os.environ['GITHUB_ENV'], 'a') as file:
        file.write('\n'.join(environment) + '\n')
    export = {'method': 'ad-hoc', 'teamID': os.environ['APPLE_TEAM_ID'], 'signingStyle': 'manual', 'compileBitcode': False, 'provisioningProfiles': mappings}
    (temporary / 'ExportOptions.plist').write_bytes(plistlib.dumps(export))
    print('Installed validated App, Share, and Widget profiles and target-specific export mapping')


if __name__ == '__main__':
    main()
