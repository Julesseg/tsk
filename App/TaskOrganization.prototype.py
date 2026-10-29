import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description="Capture throwaway native Liquid Glass tag picker variants")
parser.add_argument("--variant", choices=["A", "B", "C", "all"], default="all")
parser.add_argument("--output", type=Path, default=Path(tempfile.gettempdir()) / "tsk-native-organization-prototype")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

def run(*command):
    return subprocess.check_output(command, text=True).strip()

runtime = next(runtime for runtime in json.loads(run("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"] if runtime["isAvailable"] and any(device["identifier"] == "com.apple.CoreSimulator.SimDeviceType.iPhone-17e" for device in runtime["supportedDeviceTypes"]))
sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
with tempfile.TemporaryDirectory(prefix="tsk-organization-prototype-") as scratch:
    app = Path(scratch) / "OrganizationPrototype.app"
    app.mkdir()
    run("xcrun", "--sdk", "iphonesimulator", "swiftc", str(Path(__file__).with_suffix(".swift")), "-parse-as-library", "-target", "arm64-apple-ios26.0-simulator", "-sdk", sdk, "-o", str(app / "OrganizationPrototype"))
    (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.julesseguin.tsk.organization-prototype", "CFBundleName": "OrganizationPrototype", "CFBundleExecutable": "OrganizationPrototype", "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "LSRequiresIPhoneOS": True, "MinimumOSVersion": "26.0", "UIDeviceFamily": [1, 2], "UILaunchScreen": {}, "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False}}))
    run("codesign", "--force", "--sign", "-", str(app))
    device = run("xcrun", "simctl", "create", "tsk-organization-prototype", "com.apple.CoreSimulator.SimDeviceType.iPhone-17e", runtime["identifier"])
    try:
        run("xcrun", "simctl", "boot", device)
        run("xcrun", "simctl", "bootstatus", device, "-b")
        run("xcrun", "simctl", "install", device, str(app))
        for variant in (["A", "B", "C"] if args.variant == "all" else [args.variant]):
            run("xcrun", "simctl", "launch", device, "com.julesseguin.tsk.organization-prototype", "--variant=" + variant)
            time.sleep(6)
            shot = args.output / (variant + ".png")
            run("xcrun", "simctl", "io", device, "screenshot", str(shot))
            run("xcrun", "simctl", "terminate", device, "com.julesseguin.tsk.organization-prototype")
            print(shot)
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)
        subprocess.run(["xcrun", "simctl", "delete", device], check=False)
        booted = json.loads(run("xcrun", "simctl", "list", "devices", "booted", "--json"))
        if not any(booted["devices"].values()):
            subprocess.run(["osascript", "-e", 'quit app "Simulator"'], check=False)
