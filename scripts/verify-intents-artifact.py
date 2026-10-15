import json
import pathlib
import plistlib
import struct
import sys

app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Info.plist').read_bytes())
def verify_group(bundle):
    bundle_info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    binary = (bundle / bundle_info['CFBundleExecutable']).read_bytes()
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
        raise SystemExit(f'{bundle.name} has no shared task App Group entitlement')


verify_group(app)
widget = app / 'PlugIns' / 'TskWidgets.appex'
widget_info = plistlib.loads((widget / 'Info.plist').read_bytes())
if widget_info['CFBundleIdentifier'] != 'com.julesseguin.tsk.widgets' or widget_info['NSExtension']['NSExtensionPointIdentifier'] != 'com.apple.widgetkit-extension':
    raise SystemExit('The app must embed the real WidgetKit extension')
verify_group(widget)
widget_metadata = json.loads((widget / 'Metadata.appintents' / 'extract.actionsdata').read_bytes())
if not {'TaskWidgetConfiguration', 'CompleteTaskIntent'}.issubset(widget_metadata['actions']):
    raise SystemExit('Widget metadata is missing native view configuration or common completion action')
if 'WidgetTaskViewEntity' not in widget_metadata['entities']:
    raise SystemExit('Widget metadata is missing its registered-view entity')

share = app / "PlugIns" / "TskShare.appex"
verify_group(share)
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
print('Verified App + Share + Widget shared entitlements, embedded WidgetKit target/configuration/completion, and four App Shortcuts')
