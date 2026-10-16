import importlib.util
import asyncio
import copy
import json
import pathlib
import tempfile
import time
import unittest
import uuid
from types import SimpleNamespace
from unittest import mock

path = pathlib.Path(__file__).with_name('relay-native-keyboard-hid.py')
spec = importlib.util.spec_from_file_location('native_hid_relay', path)
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)
TOKEN = 'a2a514f2-fe63-40e1-9a42-b097cb8e9f23'


def request(case=relay.CASE, phase='commandReturn', sequence=0):
    value = dict(version=1, owner=TOKEN, attempt='343d52b5-399d-4e45-a357-bf8f8446452b', request=str(uuid.uuid4()), caseName=case, phase=phase, sequence=sequence, runnerPID=1234, runnerBundleID=relay.RUNNER, replica='b9d12d0d-fdcf-47f9-b5cf-3b49a71a8a4b', expiresAt=time.time()+12)
    if case == relay.CASE:
        value['nativeState'] = dict(processID=1245, firstResponder=True, textLength=1, textIsPlainN=True, commandNCount=1, commandReturnCount=0)
    return value


def marker(value):
    return relay.PREFIX + json.dumps(value).encode() + b'\n'


def boundary(case, outcome='started.'):
    suite, method = case.split('/')
    return ("Test Case '-[TskUITests." + suite + ' ' + method + "]' " + outcome).encode()


class MarkerTests(unittest.TestCase):
    def test_accepts_nonce_bound_native_focus_and_baseline(self):
        value = request()
        self.assertEqual(relay.parse_marker(marker(value), TOKEN), value)
        self.assertEqual(value['nativeState']['processID'], 1245)

    def test_rejects_wrong_session_case_phase_focus_and_baseline(self):
        changes = [('owner',str(uuid.uuid4())),('replica','not-a-uuid'),('caseName','AnotherTest/testInput'),('phase','plain'),('socket','/tmp/untrusted.sock')]
        states = [('processID',0),('processID',True),('firstResponder',False),('textLength',2),('textIsPlainN',False),('commandNCount',0),('commandNCount',True),('commandReturnCount',1)]
        for key,value in changes+states:
            candidate = request()
            (candidate['nativeState'] if (key,value) in states else candidate)[key] = value
            with self.subTest(key=key,value=value), self.assertRaises(ValueError):
                relay.parse_marker(marker(candidate),TOKEN)

    def test_rejects_truncated_oversized_duplicate_key_and_nonfinite_records(self):
        raw = marker(request())
        candidates = [raw[:-1],raw.replace(b'"phase": "commandReturn"',b'"phase":"plain","phase":"commandReturn"'),raw.replace(b'"processID": 1245',b'"processID":NaN'),relay.PREFIX+b'x'*2049+b'\n',relay.PREFIX+b'\xff\n']
        for line in candidates:
            with self.subTest(length=len(line)), self.assertRaises(ValueError):
                relay.parse_marker(line,TOKEN)

    def test_chunked_log_accepts_one_record_and_rejects_replay(self):
        value=request(); raw=marker(value); reader=relay.MarkerReader(TOKEN); protocol=relay.Protocol(TOKEN)
        protocol.line(boundary(relay.CASE))
        self.assertEqual(reader.feed(raw[:41]),[])
        self.assertEqual(reader.feed(raw[41:-1]),[])
        self.assertEqual(protocol.line(reader.feed(b'\n')[0]),value)
        with self.assertRaises(ValueError):
            protocol.line(raw.rstrip(b'\n'))

    def test_duplicate_batch_and_truncated_markers_fail_without_whole_log_limit(self):
        value=request(); protocol=relay.Protocol(TOKEN); protocol.line(boundary(relay.CASE)); reader=relay.MarkerReader(TOKEN)
        lines=reader.feed(marker(value)+marker(value))
        protocol.line(lines[0])
        with self.assertRaises(ValueError):protocol.line(lines[1])
        reader=relay.MarkerReader(TOKEN); reader.feed(marker(value)[:-1])
        with self.assertRaises(ValueError):reader.finish()
        reader=relay.MarkerReader(TOKEN)
        for _ in range(3000):reader.feed(b'x'*4096)
        self.assertLessEqual(len(reader.buffer),65536)
        self.assertEqual(reader.feed(b'\n'+marker(value)),[marker(value).rstrip(b'\n')])
        reader.finish()


class ChordTests(unittest.IsolatedAsyncioTestCase):
    async def test_one_rpc_contains_all_four_explicit_key_directions(self):
        observed=[]
        async def send(events):observed.append(events)
        await relay.dispatch_chord(send)
        self.assertEqual(observed,[((227,'DOWN'),(40,'DOWN'),(40,'UP'),(227,'UP'))])

    async def test_error_and_cancellation_send_only_up_cleanup_then_fail(self):
        for error in [RuntimeError('RPC failed'),asyncio.CancelledError()]:
            observed=[]
            async def send(events):
                observed.append(events)
                if len(observed)==1:raise error
            with self.assertRaises(type(error)):await relay.dispatch_chord(send)
            self.assertEqual(observed,[((227,'DOWN'),(40,'DOWN'),(40,'UP'),(227,'UP')),((40,'UP'),(227,'UP'))])

    async def test_cleanup_failure_never_turns_original_failure_into_success(self):
        async def send(events):raise RuntimeError('RPC or cleanup failed')
        with self.assertRaisesRegex(RuntimeError,'RPC or cleanup failed') as raised:await relay.dispatch_chord(send)
        self.assertIn('HID UP cleanup unconfirmed',raised.exception.__notes__[0])


class ArmedLogTests(unittest.TestCase):
    def test_arming_skips_existing_bytes_and_future_requests_remain_owner_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'live.log'; value=request(); path.write_bytes(marker(value))
            with relay.ArmedLog(path,TOKEN) as log:
                self.assertEqual(log.poll(),[])
                with path.open('ab',buffering=0) as writer:writer.write(marker(value))
                self.assertEqual(relay.parse_marker(log.poll()[0]+b'\n',TOKEN),value)

    def test_truncation_or_replacement_after_arming_fails_closed(self):
        for replace in [False,True]:
            with self.subTest(replace=replace), tempfile.TemporaryDirectory() as directory:
                path=pathlib.Path(directory)/'live.log'; path.write_bytes(b'existing log\n')
                with relay.ArmedLog(path,TOKEN) as log:
                    if replace:path.unlink()
                    path.write_bytes(b'')
                    with self.assertRaises(ValueError):log.poll()


class ProtocolTests(unittest.TestCase):
    def test_fixed_order_and_atomic_matching_ack_are_required_before_next_phase(self):
        protocol=relay.Protocol(TOKEN); protocol.line(boundary(relay.ANNOTATIONS))
        first=request(relay.ANNOTATIONS,'secondNoteCommandN'); protocol.line(marker(first).rstrip(b'\n'))
        second=request(relay.ANNOTATIONS,'secondNoteSave',1); second['attempt']=first['attempt']
        with self.assertRaises(ValueError):protocol.line(marker(second).rstrip(b'\n'))
        protocol.acknowledged(first)
        self.assertEqual(protocol.line(marker(second).rstrip(b'\n')),second)
        protocol.acknowledged(second)
        with self.assertRaises(ValueError):protocol.line(boundary(relay.ANNOTATIONS,'passed (1.0 seconds).'))

    def test_inactive_changed_attempt_abort_and_expired_request_fail_closed(self):
        value=request()
        for raw in [marker(value).rstrip(b'\n'),(relay.ABORT+json.dumps(value).encode())]:
            with self.assertRaises(ValueError):relay.Protocol(TOKEN).line(raw)
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory); location=root/'Documents/TSKHID'/TOKEN/value['attempt']; location.mkdir(parents=True)
            (location/(value['request']+'.request.json')).write_bytes(json.dumps(value).encode())
            exchange=relay.Exchange(root,value)
            try:
                with self.assertRaises(ValueError):exchange.verify(value['expiresAt'])
                exchange.acknowledge(value['expiresAt']-1)
                ack=json.loads((location/(value['request']+'.ack.json')).read_text())
                self.assertEqual(ack,dict(request=value,state='transportComplete'))
                with self.assertRaises(ValueError):exchange.acknowledge(value['expiresAt']-1)
            finally:exchange.close()


class RunTests(unittest.IsolatedAsyncioTestCase):
    async def test_overlap_already_in_same_log_batch_cannot_receive_ack_or_dispatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory); log=root/'live.log'; log.touch(); socket=root/'owned.sock';socket.touch(); stop=root/'stop'
            value=request(); location=root/'Documents/TSKHID'/TOKEN/value['attempt'];location.mkdir(parents=True)
            (location/(value['request']+'.request.json')).write_text(json.dumps(value))
            args=SimpleNamespace(log=str(log),socket=str(socket),udid=str(uuid.uuid4()),companion_pid=123,relay_token=TOKEN,receipt=str(root/'relay.json'),stop_file=str(stop))
            observed=[]; armed=asyncio.Event()
            async def send(events):observed.append(events)
            async def lookup(*args):return root
            original_save=relay.save_receipt
            def save(path,value):
                original_save(path,value)
                if value['state']=='waiting':armed.set()
            with mock.patch.object(relay,'make_sender',return_value=send),mock.patch.object(relay,'container_for',side_effect=lookup),mock.patch.object(relay.stat,'S_ISSOCK',return_value=True),mock.patch.object(relay,'save_receipt',side_effect=save):
                task=asyncio.create_task(relay.run(args));await asyncio.wait_for(armed.wait(),1)
                with log.open('ab',buffering=0) as writer:writer.write(boundary(relay.CASE)+b'\n'+marker(value)+marker(value))
                stop.touch()
                with self.assertRaises(ValueError):await asyncio.wait_for(task,1)
            self.assertEqual(observed,[])
            self.assertFalse((location/(value['request']+'.ack.json')).exists())


class DispatchBudgetTests(unittest.IsolatedAsyncioTestCase):
    async def assert_no_late_dispatch(self, remaining, persistence_seconds):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory); log=root/'live.log'; log.touch(); socket=root/'owned.sock';socket.touch(); stop=root/'stop'
            clock=100.0
            value=request();value['expiresAt']=clock+remaining
            location=root/'Documents/TSKHID'/TOKEN/value['attempt'];location.mkdir(parents=True)
            (location/(value['request']+'.request.json')).write_text(json.dumps(value))
            args=SimpleNamespace(log=str(log),socket=str(socket),udid=str(uuid.uuid4()),companion_pid=123,relay_token=TOKEN,receipt=str(root/'relay.json'),stop_file=str(stop))
            observed=[];armed=asyncio.Event()
            async def send(events):observed.append(events)
            async def lookup(*args):return root
            original_save=relay.save_receipt
            def save(path,receipt):
                nonlocal clock
                original_save(path,receipt)
                if receipt['state']=='waiting':armed.set()
                if receipt['state']=='sending':clock+=persistence_seconds
            with mock.patch.object(relay,'make_sender',return_value=send),mock.patch.object(relay,'container_for',side_effect=lookup),mock.patch.object(relay.stat,'S_ISSOCK',return_value=True),mock.patch.object(relay,'save_receipt',side_effect=save),mock.patch.object(relay.time,'time',side_effect=lambda:clock):
                task=asyncio.create_task(relay.run(args));await asyncio.wait_for(armed.wait(),1)
                with log.open('ab',buffering=0) as writer:writer.write(boundary(relay.CASE)+b'\n'+marker(value))
                stop.touch()
                with self.assertRaises(ValueError):await asyncio.wait_for(task,1)
            self.assertEqual(observed,[],'Expired transport budget must never dispatch DOWN')
            self.assertFalse((location/(value['request']+'.ack.json')).exists())

    async def test_less_than_five_seconds_remaining_cannot_start_a_fresh_five_second_rpc(self):
        await self.assert_no_late_dispatch(4.9,0)

    async def test_receipt_persistence_consuming_dispatch_budget_is_rechecked_before_down(self):
        await self.assert_no_late_dispatch(12,8)


class AcknowledgementRunTests(unittest.IsolatedAsyncioTestCase):
    async def test_actual_relay_acknowledges_only_after_rpc_and_completes_sequential_case(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory); log=root/'live.log'; log.touch(); socket=root/'owned.sock'; socket.touch(); stop=root/'stop'
            value=request(relay.ANNOTATIONS,'secondNoteCommandN'); location=root/'Documents/TSKHID'/TOKEN/value['attempt']; location.mkdir(parents=True)
            args=SimpleNamespace(log=str(log),socket=str(socket),udid=str(uuid.uuid4()),companion_pid=123,relay_token=TOKEN,receipt=str(root/'relay.json'),stop_file=str(stop))
            observed=[]; armed=asyncio.Event(); sending=asyncio.Event(); release=asyncio.Event()
            async def send(events):
                observed.append(events)
                if len(observed)==1:
                    sending.set()
                    await release.wait()
            async def lookup(*args):return root
            original_save=relay.save_receipt
            def save(path,receipt):
                original_save(path,receipt)
                if receipt['state']=='waiting':armed.set()
            def append(raw):
                with log.open('ab',buffering=0) as writer:writer.write(raw+b'\n')
            with mock.patch.object(relay,'make_sender',return_value=send),mock.patch.object(relay,'container_for',side_effect=lookup) as lookup_mock,mock.patch.object(relay.stat,'S_ISSOCK',return_value=True),mock.patch.object(relay,'save_receipt',side_effect=save):
                task=asyncio.create_task(relay.run(args)); await asyncio.wait_for(armed.wait(),1)
                try:
                    append(boundary(relay.ANNOTATIONS))
                    for index,phase in enumerate(['secondNoteCommandN','secondNoteSave','editSelectAll','editedNoteSave']):
                        current=dict(value,phase=phase,sequence=index,request=str(uuid.uuid4()),expiresAt=time.time()+12)
                        (location/(current['request']+'.request.json')).write_text(json.dumps(current))
                        append(marker(current).rstrip(b'\n'))
                        ack=location/(current['request']+'.ack.json')
                        if index==0:
                            await asyncio.wait_for(sending.wait(),1)
                            self.assertFalse(ack.exists())
                            release.set()
                        async def wait_ack():
                            while not ack.exists():
                                if task.done():await task
                                await asyncio.sleep(.001)
                        await asyncio.wait_for(wait_ack(),1)
                        self.assertEqual(json.loads(ack.read_text()),dict(request=current,state='transportComplete'))
                    append(boundary(relay.ANNOTATIONS,'passed (1.0 seconds).'))
                    stop.touch(); await asyncio.wait_for(task,1)
                finally:
                    if not task.done():
                        task.cancel()
                        await asyncio.gather(task,return_exceptions=True)
            receipt=json.loads((root/'relay.json').read_text())
            self.assertEqual(receipt['state'],'completed_native_assertions_required')
            self.assertEqual(receipt['cases'][relay.ANNOTATIONS]['completed'],['secondNoteCommandN','secondNoteSave','editSelectAll','editedNoteSave'])
            self.assertEqual(observed,[((227,'DOWN'),(17,'DOWN'),(17,'UP'),(227,'UP')),((227,'DOWN'),(40,'DOWN'),(40,'UP'),(227,'UP')),((227,'DOWN'),(4,'DOWN'),(4,'UP'),(227,'UP')),((227,'DOWN'),(40,'DOWN'),(40,'UP'),(227,'UP'))])
            self.assertEqual(lookup_mock.await_count,1)


class FileAndMappingTests(unittest.TestCase):
    def test_marker_and_file_must_match_typed_protocol_not_python_numeric_aliases(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory); value=request(); location=root/'Documents/TSKHID'/TOKEN/value['attempt']; location.mkdir(parents=True)
            changed=copy.deepcopy(value); changed['version']=True
            (location/(value['request']+'.request.json')).write_text(json.dumps(changed))
            exchange=relay.Exchange(root,value)
            try:
                with self.assertRaises(ValueError):exchange.verify(value['expiresAt']-1)
            finally:exchange.close()

    def test_each_fixed_phase_uses_only_its_literal_chord_and_up_only_recovery(self):
        expected={
            relay.CASE: {'commandReturn': ((227,'DOWN'),(40,'DOWN'),(40,'UP'),(227,'UP'))},
            relay.ANNOTATIONS: {'secondNoteCommandN': ((227,'DOWN'),(17,'DOWN'),(17,'UP'),(227,'UP')), 'secondNoteSave': ((227,'DOWN'),(40,'DOWN'),(40,'UP'),(227,'UP')), 'editSelectAll': ((227,'DOWN'),(4,'DOWN'),(4,'UP'),(227,'UP')), 'editedNoteSave': ((227,'DOWN'),(40,'DOWN'),(40,'UP'),(227,'UP'))},
            relay.WORKSPACE: {'capture': ((227,'DOWN'),(17,'DOWN'),(17,'UP'),(227,'UP')), 'saveNew': ((227,'DOWN'),(40,'DOWN'),(40,'UP'),(227,'UP')), 'select': ((227,'DOWN'),(81,'DOWN'),(81,'UP'),(227,'UP')), 'edit': ((227,'DOWN'),(8,'DOWN'),(8,'UP'),(227,'UP')), 'saveEdit': ((227,'DOWN'),(40,'DOWN'),(40,'UP'),(227,'UP')), 'complete': ((227,'DOWN'),(225,'DOWN'),(40,'DOWN'),(40,'UP'),(225,'UP'),(227,'UP')), 'completedView': ((227,'DOWN'),(33,'DOWN'),(33,'UP'),(227,'UP'))}}
        self.assertEqual(relay.CHORDS,expected)
        self.assertEqual(relay.releases(expected[relay.WORKSPACE]['complete']),((40,'UP'),(225,'UP'),(227,'UP')))


if __name__=='__main__':unittest.main()
