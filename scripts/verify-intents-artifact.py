import json
import pathlib
import plistlib
import struct
import sys

app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Info.plist').read_bytes())
binary = (app / info['CFBundleExecutable']).read_bytes()
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

metadata = json.loads((app / 'Metadata.appintents' / 'extract.actionsdata').read_bytes())
if not {'CreateTaskIntent', 'FindTasksIntent'}.issubset(metadata['actions']):
    raise SystemExit('The app metadata is missing its create/find actions')
shortcuts = {shortcut['actionIdentifier'] for shortcut in metadata['autoShortcuts']}
if 'IntentTaskEntity' not in metadata['entities'] or not {'CreateTaskIntent', 'FindTasksIntent'}.issubset(shortcuts):
    raise SystemExit('The app metadata is missing its task entity or App Shortcuts')
print('Verified embedded simulator App Group entitlement and create/find App Shortcut metadata')
