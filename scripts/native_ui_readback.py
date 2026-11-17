import json
import hashlib
import os
from pathlib import Path
import re
import subprocess
import time
import uuid


CHECKPOINTS = {
    'TaskBulkSelectionUITests/testBulkDateFailureRetainsPendingOperationAndEverySelectedTask': ['failed-apply'],
    'TaskRowEditingUITests/testOutsideSaveValidationPickersAndDurableCompletion': ['edited', 'completed'],
    'TaskBulkSelectionUITests/testBulkDatesRequireApplyKeepMixedFieldsAndPersistAfterRelaunch': ['cancelled', 'applied'],
    'SeriesMetadataUITests/testSeriesMetadataPreviewCancelSaveAndPersistentFutureOccurrences': ['saved'],
    'TaskScheduledUITests/testNonMidnightScheduledEditsKeepOtherDatesAndPersist': ['saved'],
    'TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations': ['saved'],
    'TskUITests/testCaptureReviewCancelSaveAndRelaunch': ['saved'],
    'TaskRowEditingUITests/testSupportingInformationEditsKeepTheExpandedDraftAndPersist': ['saved'],
    'TaskRowEditingUITests/testOrganizationSelectionClearingInvalidTagsAndReopening': ['tagged', 'cleared'],
}
REQUEST = re.compile(r'^TSK_NATIVE_READBACK_REQUEST ([A-Fa-f0-9-]{36})$')


class NativeReadback:
    def __init__(self, device, probe, library, plan, evidence, token):
        self.device, self.probe, self.library = device, probe, library
        self.expected = {(method, checkpoint) for method, checkpoints in plan.items() for checkpoint in checkpoints}
        self.completed = set()
        self.nonces = set()
        self.evidence = Path(evidence)
        self.evidence.mkdir(parents=True, exist_ok=True)
        self.token = token
        self.errors = []
        self.containers = {}
        self.deadline = float("inf")

    def container(self, bundle, kind):
        key = (bundle, kind)
        if key in self.containers:
            return self.containers[key]
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Native readback service deadline expired')
        value = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', self.device, bundle, kind], text=True, timeout=min(2, remaining)).strip()
        path = Path(value)
        if not path.is_absolute() or not path.is_dir():
            raise ValueError('Platform container is missing')
        self.containers[key] = path
        return path

    def respond(self, nonce):
        nonce = str(uuid.UUID(nonce)).upper()
        output = None
        self.deadline = time.monotonic() + 5
        response = dict(nonce=nonce, session=self.token)
        evidence = dict(nonce=nonce, device=self.device, source=os.environ.get('GITHUB_SHA'), probe_sha256=hashlib.sha256(Path(self.probe).read_bytes()).hexdigest(), library_sha256=hashlib.sha256(Path(self.library).read_bytes()).hexdigest() if Path(self.library).is_file() else None)
        try:
            if nonce in self.nonces:
                raise ValueError('Duplicate readback nonce')
            self.nonces.add(nonce)
            folder = self.container('com.julesseguin.tsk.uitests.xctrunner', 'data') / 'Documents/TskNativeReadback'
            request_file = folder / (nonce + '.request.json')
            output = folder / (nonce + '.response.json')
            if request_file.is_symlink() or request_file.stat().st_size > 65536:
                raise ValueError('Invalid readback request file')
            request = json.loads(request_file.read_text())
            if request['session'] != self.token or request['nonce'] != nonce or request['schema'] != 1:
                raise ValueError('Readback session/nonce/schema mismatch')
            key = (request['method'], request['checkpoint'])
            if key not in self.expected or key in self.completed:
                raise ValueError('Unexpected or duplicate readback checkpoint')
            replica = str(uuid.UUID(request['replica'])).upper()
            if replica != request['replica'] or not time.time() < request['expiresAt'] <= time.time() + 15:
                raise ValueError('Invalid replica or expired readback request')
            fixtures = self.container('com.julesseguin.tsk', 'group.com.julesseguin.tsk') / 'UITests'
            directory = fixtures / replica / 'TaskChampion'
            if not directory.resolve().is_relative_to(fixtures.resolve()):
                raise ValueError('Fixture storage escaped its registered App Group')
            if not directory.is_dir() or directory.is_symlink():
                raise ValueError('Existing fixture replica is missing')
            environment = dict(os.environ, TSK_TASKCHAMPION_LIBRARY=self.library)
            remaining = min(self.deadline - time.monotonic(), request['expiresAt'] - time.time())
            if remaining <= 0:
                raise TimeoutError('Native readback service deadline expired')
            result = subprocess.run([self.probe, 'read-tasks', str(directory)], env=environment, capture_output=True, text=True, timeout=remaining)
            if result.returncode:
                raise ValueError('Native existing-store query failed: ' + result.stderr.strip())
            records = json.loads(result.stdout)
            if not isinstance(records, list) or len(records) > 1000:
                raise ValueError('Invalid native records')
            identities = [str(uuid.UUID(record['id'])) for record in records]
            if len(identities) != len(set(identities)) or time.time() >= request['expiresAt']:
                raise ValueError('Duplicate identities or expired native result')
            response.update(replica=replica, method=key[0], checkpoint=key[1], records=records)
            evidence.update(response)
            self.completed.add(key)
        except Exception as error:
            response['error'] = str(error)
            evidence['error'] = str(error)
            self.errors.append(str(error))
        if output is not None:
            temporary = output.with_suffix('.tmp')
            temporary.write_text(json.dumps(response))
            temporary.replace(output)
        evidence.pop('session', None)
        (self.evidence / (nonce + '.json')).write_text(json.dumps(evidence, indent=2) + '\n')

    def finish(self, status):
        missing = sorted(self.expected - self.completed)
        (self.evidence / 'summary.json').write_text(json.dumps(dict(expected=sorted(self.expected), completed=sorted(self.completed), missing=missing, errors=self.errors), indent=2) + '\n')
        if missing or self.errors:
            print('::error title=Native readback incomplete::Required native checkpoints missing or failed.', flush=True)
        return status or int(bool(missing or self.errors))
