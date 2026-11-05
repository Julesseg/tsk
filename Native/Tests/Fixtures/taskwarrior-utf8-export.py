import json
import sys


rows = json.load(sys.stdin)
json.dump([
    {'fields': [{'key': key, 'value': value} for key, value in row.items() if isinstance(value, str)],
     'tags': row.get('tags', [])}
    for row in rows
], sys.stdout)
