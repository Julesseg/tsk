import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import signal
import sys
import time


def run(command, timeout=120):
    print(json.dumps(command), flush=True)
    process = subprocess.run(command, text=True, capture_output=True, timeout=timeout)
    if process.stderr:
        print(process.stderr, file=sys.stderr, flush=True)
    process.check_returncode()
    result = process.stdout.strip()
    if command[1:3] == ['simctl', 'launch']:
        print(result, flush=True)
    return result


def interrupted(signum, frame):
    raise SystemExit(128 + signum)


def main():
    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, interrupted)
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    output = Path('.build/spotlight-minimal').resolve()
    output.mkdir(parents=True, exist_ok=True)
    bundle = output / 'SpotlightMinimal.app'
    bundle.mkdir(exist_ok=True)
    bundle_id = 'com.julesseguin.spotlight-minimal'
    info = dict(CFBundleIdentifier=bundle_id, CFBundleName='SpotlightMinimal', CFBundleExecutable='SpotlightMinimal', CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='1.0', MinimumOSVersion='27.0', LSRequiresIPhoneOS=True, UIDeviceFamily=[1, 2], UILaunchScreen={})
    (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
    sdk = run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'])
    run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-sdk', sdk, '-target', 'arm64-apple-ios27.0-simulator', '-framework', 'SwiftUI', '-framework', 'UIKit', '-framework', 'CoreSpotlight', 'scripts/diagnostics/SpotlightMinimal.swift', '-o', str(bundle / 'SpotlightMinimal')])
    run(['codesign', '--force', '--sign', '-', str(bundle)])
    if args.build_only:
        return
    initial = json.loads(run(['xcrun', 'simctl', 'list', 'devices', '--json']))
    (output / 'initial-devices.json').write_text(json.dumps(initial, indent=2))
    runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
    devices = [device for device in initial['devices'].get(runtime, []) if device.get('isAvailable') and device['name'].startswith('iPhone')]
    template = max(devices, key=lambda device: ('Pro' in device['name'], device['name']))
    device = run(['xcrun', 'simctl', 'create', 'tsk minimal Spotlight', template['deviceTypeIdentifier'], runtime])
    (output / 'owned-device.json').write_text(json.dumps(dict(id=device, runtime=runtime, template=template), indent=2))
    try:
        run(['xcrun', 'simctl', 'boot', device])
        run(['xcrun', 'simctl', 'bootstatus', device, '-b'], timeout=240)
        run(['xcrun', 'simctl', 'install', device, str(bundle)])
        container = Path(run(['xcrun', 'simctl', 'get_app_container', device, bundle_id, 'data']))
        if not container.is_absolute() or not container.is_dir():
            raise RuntimeError('Invalid application data container')
        (output / 'application-container.txt').write_text(str(container))
        result_path = container / 'Documents/result.json'
        run(['xcrun', 'simctl', 'launch', device, bundle_id])
        deadline = time.monotonic() + 135
        result = {'status': 'failed', 'reason': 'no-result-before-host-deadline'}
        while time.monotonic() < deadline:
            if result_path.exists():
                result = json.loads(result_path.read_text())
                if result['status'] != 'pending':
                    break
            time.sleep(0.5)
        (output / 'result.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2), flush=True)
        if result['status'] != 'passed':
            raise SystemExit(1)
    finally:
        cleanup = {}
        for action in ('shutdown', 'delete'):
            try:
                process = subprocess.run(['xcrun', 'simctl', action, device], capture_output=True, text=True, timeout=60)
                cleanup[action] = dict(status=process.returncode, stdout=process.stdout, stderr=process.stderr)
            except subprocess.TimeoutExpired:
                cleanup[action] = dict(status=124, error='cleanup-timeout')
        (output / 'cleanup.json').write_text(json.dumps(cleanup, indent=2))
        booted = json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
        (output / 'final-booted.json').write_text(json.dumps(booted, indent=2))
        if not any(booted['devices'].values()):
            subprocess.run(['osascript', '-e', 'quit app "Simulator"'], timeout=15, check=True)
        if any(record['status'] != 0 for record in cleanup.values()):
            raise RuntimeError('Owned simulator cleanup failed')


if __name__ == '__main__':
    main()
