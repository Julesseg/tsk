# Retired local custom attributes

Local custom-attribute editing, definitions, storage integration and dedicated UI
coverage were removed at the user’s request. This is a product scope change,
not a repair or waiver of the native switch failure observed in the former UI.

Taskwarrior's generic byte-exact attribute maps remain. Ordinary editing,
completion, synchronization and recurrence preserve opaque task data. Legacy
attribute-definitions.json files are inert and left untouched; malformed retired
metadata cannot block task use. Built-in fields and filter behavior remain
covered by Core, Native and UI tests.
