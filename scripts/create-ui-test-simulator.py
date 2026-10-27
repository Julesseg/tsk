import argparse
import json
import os
import re
import subprocess


def select_template(devices, family, sdk_version):
    sdk_release = tuple(int(part) for part in sdk_version.split(".")[:2])
    available = []
    for runtime, entries in devices.items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?", runtime)
        if not match:
            continue
        version = tuple(int(part or 0) for part in match.groups())
        if version[:2] != sdk_release:
            continue
        for device in entries:
            if device["name"].startswith(family) and device.get("isAvailable", True):
                available.append((version, runtime, device))
    if not available:
        raise ValueError(f"No available {family} simulator runtime matches iOS Simulator SDK {sdk_version}")
    _, runtime, selected = max(available, key=lambda item: (item[0], "13-inch" in item[2]["name"] or "12.9-inch" in item[2]["name"], "Pro" in item[2]["name"], item[2]["name"]))
    return runtime, selected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--family", required=True, choices=["iPhone", "iPad"])
    arguments = parser.parse_args()
    sdk_version = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip()
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))["devices"]
    runtime, device = select_template(devices, arguments.family, sdk_version)
    identifier = subprocess.check_output(["xcrun", "simctl", "create", "tsk isolated " + arguments.family, device["deviceTypeIdentifier"], runtime], text=True).strip()
    print(f"Created isolated simulator: {device['name']} ({identifier}), runtime {runtime}, SDK {sdk_version}")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write("id=" + identifier + "\n")


if __name__ == "__main__":
    main()
