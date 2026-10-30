import argparse
import hashlib
import json
import platform
import subprocess
import tarfile
from pathlib import Path


def identity(root):
    def read(*command):
        return subprocess.check_output(command, cwd=root, text=True).strip()
    sdk = read('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version')
    release = '.'.join(sdk.split('.')[:2])
    runtimes = json.loads(read('xcrun', 'simctl', 'list', 'runtimes', '--json'))['runtimes']
    matches = sorted((dict(identifier=item['identifier'], version=item['version'], build=item['buildversion']) for item in runtimes
                      if item.get('isAvailable', False) and item.get('version', '').split('.')[:2] == release.split('.') and 'iOS' in item['identifier']), key=lambda item: item['identifier'])
    if not matches:
        raise ValueError('No available runtime matches simulator SDK ' + sdk)
    return dict(source=read('git', 'rev-parse', 'HEAD'), tree=read('git', 'rev-parse', 'HEAD^{tree}'),
                xcode=read('xcodebuild', '-version'), sdk=sdk, sdk_build=read('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-build-version'),
                architecture=platform.machine(), runtimes=matches)


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def verify_identity(expected, actual):
    if expected != actual:
        differences = [key for key in set(expected) | set(actual) if expected.get(key) != actual.get(key)]
        raise ValueError('Prebuilt products do not match this source/toolchain/runtime: ' + ', '.join(sorted(differences)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['pack', 'unpack'])
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('--archive', type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    archive = args.archive.resolve()
    manifest = archive.with_suffix('.json')
    current = identity(root)
    if args.command == 'pack':
        paths = ['.build/ui/Build/Products', '.build/ui-tools']
        if not (root / paths[0] / 'Debug-iphonesimulator/Tsk.app').is_dir():
            raise ValueError('Signed UI products are missing')
        archive.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive, 'w:gz') as output:
            for path in paths:
                output.add(root / path, arcname=path)
        manifest.write_text(json.dumps(dict(identity=current, sha256=digest(archive)), indent=2) + '\n')
    else:
        data = json.loads(manifest.read_text())
        verify_identity(data['identity'], current)
        if data['sha256'] != digest(archive):
            raise ValueError('Prebuilt product archive checksum mismatch')
        with tarfile.open(archive) as source:
            source.extractall(root, filter='data')
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(root / '.build/ui/Build/Products/Debug-iphonesimulator/Tsk.app')], check=True)
    print(json.dumps(current, indent=2))


if __name__ == '__main__':
    main()
