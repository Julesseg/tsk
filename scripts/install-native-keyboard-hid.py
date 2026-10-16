import argparse
import hashlib
import json
import pathlib
import platform
import subprocess
import sys
import tarfile
import urllib.request

ASSETS = {
    'idb-companion.macos-arm64.tar.gz': ('1a4e9dc2a90b93af83ac885b2b45b0e7357153f5e5736dbaa7bd9db6c164c783', 29093002),
    'fb_idb-1.7.3-py3-none-any.whl': ('b3933fa86c2499e446dc2e06f2fd475737c41a4a99fc1782bf32cd7133b2a29e', 466679),
}
DEPENDENCIES = {'aiofiles': '25.1.0', 'grpclib': '0.4.9', 'h2': '4.4.1', 'hpack': '4.2.0', 'hyperframe': '6.1.0', 'multidict': '7.1.0', 'protobuf': '7.36.2'}


def verify_asset(path, expected_digest, expected_size):
    if path.stat().st_size != expected_size or hashlib.sha256(path.read_bytes()).hexdigest() != expected_digest:
        raise ValueError('Pinned asset digest or byte count mismatch: ' + path.name)


def extract_companion(archive, destination):
    with tarfile.open(archive, 'r:gz') as tar:
        tar.extractall(destination, filter='data')
    if not (destination / 'idb_companion').is_file() or not (destination / 'Resources').is_dir():
        raise ValueError('Pinned companion resources are incomplete')


def install(root):
    if sys.version_info[:2] != (3, 12) or platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise RuntimeError('This pinned pilot requires Python3.12 on the arm64 Xcode27 runner')
    build = pathlib.Path(__file__).resolve().parents[1] / '.build'
    root = root.resolve()
    if not root.is_relative_to(build) or root == build:
        raise ValueError('Install only inside this checkout .build directory')
    root.mkdir(parents=True, exist_ok=False)
    receipt = dict(release='facebook/idb v1.7.3', commit='aaa7e7ab784df3c7027b16f2c21196119ae5adb4', assets=[], dependencies=DEPENDENCIES)
    for name, (digest, size) in ASSETS.items():
        url = 'https://github.com/facebook/idb/releases/download/v1.7.3/' + name
        target = root / name
        request = urllib.request.Request(url, headers={'User-Agent': 'tsk-owned-native-hid-pilot'})
        with urllib.request.urlopen(request, timeout=60) as response, target.open('xb') as file:
            count = 0
            while chunk := response.read(1024 * 1024):
                count += len(chunk)
                if count > size:
                    raise ValueError('Pinned download exceeds byte count')
                file.write(chunk)
        verify_asset(target, digest, size)
        receipt['assets'].append(dict(url=url, path=str(target), sha256=digest, bytes=size))
    extract_companion(root / 'idb-companion.macos-arm64.tar.gz', root / 'companion')
    subprocess.run([sys.executable, '-m', 'venv', str(root / 'venv')], check=True, timeout=60)
    python = root / 'venv/bin/python'
    requirements = root / 'requirements.txt'
    requirements.write_text(''.join(name + '==' + version + '\n' for name, version in DEPENDENCIES.items()))
    command = [str(python), '-m', 'pip', 'install', '--disable-pip-version-check', '--only-binary=:all:', '--no-deps', '--cache-dir', str(root / 'pip-cache'), '-r', str(requirements), str(root / 'fb_idb-1.7.3-py3-none-any.whl')]
    subprocess.run(command, check=True, timeout=180)
    expected = dict(DEPENDENCIES, **{'fb-idb': '1.7.3'})
    query = 'import importlib.metadata,json;print(json.dumps({name:importlib.metadata.version(name) for name in ' + repr(list(expected)) + '}))'
    installed = json.loads(subprocess.check_output([str(python), '-c', query], text=True, timeout=10))
    if installed != expected:
        raise ValueError('Installed dependency versions differ from the pinned capability proof')
    receipt.update(installed=installed, pipCommand=command, python=sys.version, architecture=platform.machine(), companionResourcesPreserved=True)
    (root / 'installer-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True, type=pathlib.Path)
    install(parser.parse_args().root)
