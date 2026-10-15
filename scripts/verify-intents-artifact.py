import json
import pathlib
import plistlib
import struct
import sys

app = pathlib.Path(sys.argv[1])
def verify_shared_group(bundle):
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    binary = (bundle / info['CFBundleExecutable']).read_bytes()
    if struct.unpack_from('<I', binary)[0] != 0xFEEDFACF:
        raise SystemExit('Expected a thin 64-bit simulator Mach-O executable')

    position = 32
    groups = []
    for _ in range(struct.unpack_from('<I', binary, 16)[0]):
        command, size = struct.unpack_from('<II', binary, position)
        if command == 0x19:
            count = struct.unpack_from('<I', binary, position + 64)[0]
            for index in range(count):
                section = struct.unpack_from('<16s16sQQIIIIIIII', binary, position + 72 + 80 * index)
                if section[0].rstrip(b'\0') == b'__entitlements':
                    entitlements = plistlib.loads(binary[section[4]:section[4] + section[3]])
                    groups = entitlements.get('com.apple.security.application-groups', [])
        position += size
    if 'group.com.julesseguin.tsk' not in groups:
        raise SystemExit('The simulator executable has no shared task App Group entitlement')


verify_shared_group(app)
share = app / "PlugIns" / "TskShare.appex"
verify_shared_group(share)
share_info = plistlib.loads((share / "Info.plist").read_bytes())
extension = share_info["NSExtension"]
if share_info["CFBundleIdentifier"] != "com.julesseguin.tsk.share" or extension["NSExtensionPointIdentifier"] != "com.apple.share-services":
    raise SystemExit("The embedded share extension has incorrect identity or extension point")
activation = extension["NSExtensionAttributes"]["NSExtensionActivationRule"]
if activation.get("NSExtensionActivationSupportsText") is not True or activation.get("NSExtensionActivationSupportsWebURLWithMaxCount", 0) < 1:
    raise SystemExit("The embedded share extension does not activate for text and web URLs")

metadata = json.loads((app / 'Metadata.appintents' / 'extract.actionsdata').read_bytes())
if not {'CreateTaskIntent', 'FindTasksIntent', 'CompleteTaskIntent', 'RescheduleTaskIntent'}.issubset(metadata['actions']):
    raise SystemExit('The app metadata is missing its create/find/complete/reschedule actions')
shortcuts = {shortcut['actionIdentifier'] for shortcut in metadata['autoShortcuts']}
if 'IntentTaskEntity' not in metadata['entities'] or not {'CreateTaskIntent', 'FindTasksIntent', 'CompleteTaskIntent', 'RescheduleTaskIntent'}.issubset(shortcuts):
    raise SystemExit('The app metadata is missing its task entity or App Shortcuts')
print('Verified embedded app/share simulator App Group entitlements, text/URL activation and create/find/complete/reschedule App Shortcut metadata')
