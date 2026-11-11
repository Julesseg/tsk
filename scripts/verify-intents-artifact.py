import json
import pathlib
import plistlib
import struct
import sys

app = pathlib.Path(sys.argv[1])


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
if 'AddTaskIntent' in widget_metadata['actions']:
    raise SystemExit('Add Task must run in the app, not the widget extension')
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
if not {'AddTaskIntent', 'FindTasksIntent', 'DeleteTaskIntent', 'CompleteTaskIntent', 'RescheduleTaskIntent'}.issubset(metadata['actions']):
    raise SystemExit('The app metadata is missing its add/find/delete/complete/reschedule actions')
shortcuts = {shortcut['actionIdentifier'] for shortcut in metadata['autoShortcuts']}
if 'IntentTaskEntity' not in metadata['entities'] or not {'AddTaskIntent', 'FindTasksIntent', 'DeleteTaskIntent', 'CompleteTaskIntent', 'RescheduleTaskIntent'}.issubset(shortcuts):
    raise SystemExit('The app metadata is missing its task entity or App Shortcuts')
print('Verified App + Share + Widget shared entitlements, embedded WidgetKit target/configuration/completion, and five App Shortcuts')

if 'CreateTaskIntent' in metadata['actions']:
    raise SystemExit('The retired Create Task intent must not remain as a compatibility action')
info = plistlib.loads((app / 'Info.plist').read_bytes())
if not any('tsk' in item.get('CFBundleURLSchemes', []) for item in info.get('CFBundleURLTypes', [])):
    raise SystemExit('The app must register the tsk URL scheme')

add_parameters = {item['name']: item for item in metadata['actions']['AddTaskIntent']['parameters']}
if set(add_parameters) != {'taskDescription', 'project', 'tags', 'priority', 'scheduled', 'deadline', 'waitingUntil'}:
    raise SystemExit('Add Task must expose exactly its seven named inputs')
if add_parameters['taskDescription']['isOptional'] or any(not item['isOptional'] for name, item in add_parameters.items() if name != 'taskDescription'):
    raise SystemExit('Only the Add Task Description input is required')
for name in ('scheduled', 'deadline', 'waitingUntil'):
    if add_parameters[name]['valueType'] != {'primitive': {'wrapper': {'typeIdentifier': 8}}}:
        raise SystemExit('Add Task date inputs must be native dates: ' + name)
properties = {item['identifier'] for item in metadata['entities']['IntentTaskEntity']['properties']}
if not {'uuid', 'description', 'project', 'tags', 'priority', 'scheduled', 'deadline', 'waitingUntil', 'status', 'openTaskURL'}.issubset(properties):
    raise SystemExit('The task entity must expose all rich result properties')
print('Verified seven Add Task inputs, native dates, required Description, rich entity properties and tsk URL registration')

find_parameters = {item['name']: item for item in metadata['actions']['FindTasksIntent']['parameters']}
if set(find_parameters) != {'searchText', 'project', 'tags', 'status', 'priority', 'scheduledFrom', 'scheduledThrough', 'deadlineFrom', 'deadlineThrough', 'waitingUntilFrom', 'waitingUntilThrough', 'sort', 'limit', 'offset'}:
    raise SystemExit('Find Tasks must expose exactly its named filters, sort and pagination inputs')
for name in ('scheduledFrom', 'scheduledThrough', 'deadlineFrom', 'deadlineThrough', 'waitingUntilFrom', 'waitingUntilThrough'):
    if find_parameters[name]['valueType'] != {'primitive': {'wrapper': {'typeIdentifier': 8}}}:
        raise SystemExit('Find Tasks bounds must be native dates: ' + name)
if metadata['actions']['FindTasksIntent']['outputType'] != {'array': {'wrapper': {'capabilities': 3, 'memberValueType': {'entity': {'wrapper': {'typeName': 'IntentTaskEntity'}}}}}}:
    raise SystemExit('Find Tasks must return a native list of task entities')
print('Verified fourteen structured Find Tasks inputs, native date bounds and native entity list result')

parameters = metadata['actions']['DeleteTaskIntent']['parameters']
if len(parameters) != 1 or parameters[0]['name'] != 'task' or parameters[0]['isOptional']:
    raise SystemExit('Delete Task must require exactly one task entity')
if metadata['actions']['DeleteTaskIntent']['outputType'] != metadata['actions']['CompleteTaskIntent']['outputType']:
    raise SystemExit('Delete Task must return the shared rich task entity')
print('Verified one required Delete Task entity and shared rich entity result')
