import importlib.util
import asyncio
import json
import pathlib
import tempfile
import unittest

path = pathlib.Path(__file__).with_name("relay-native-keyboard-hid.py")
spec = importlib.util.spec_from_file_location("native_hid_relay", path)
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)

TOKEN = "A2A514F2-FE63-40E1-9A42-B097CB8E9F23"
MARKER = b'TSK_NATIVE_KEYBOARD_HID_REQUEST_V1 {"caseName":"TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys","phase":"commandReturn","relayToken":"A2A514F2-FE63-40E1-9A42-B097CB8E9F23","token":"343D52B5-399D-4E45-A357-BF8F8446452B","state":{"processID":1245,"firstResponder":true,"textLength":1,"textIsPlainN":true,"commandNCount":1,"commandReturnCount":0}}\n'


class MarkerTests(unittest.TestCase):
    def test_accepts_nonce_bound_native_focus_and_baseline(self):
        request = relay.parse_marker(MARKER, TOKEN)
        self.assertEqual(request["token"], "343D52B5-399D-4E45-A357-BF8F8446452B")
        self.assertEqual(request["state"]["processID"], 1245)

    def test_rejects_wrong_session_case_phase_focus_and_baseline(self):
        original = json.loads(MARKER.split(b" ", 1)[1])
        changes = [
            ("relayToken", "FD031656-16F5-48B5-8560-2CF485ADABAD"),
            ("token", "not-a-uuid"),
            ("caseName", "AnotherTest/testInput"),
            ("phase", "plain"),
            ("socket", "/tmp/untrusted.sock"),
        ]
        states = [
            ("processID", 0), ("processID", True), ("firstResponder", False),
            ("textLength", 2), ("textIsPlainN", False),
            ("commandNCount", 0), ("commandNCount", True), ("commandReturnCount", 1),
        ]
        for key, value in changes + states:
            with self.subTest(key=key, value=value):
                candidate = json.loads(json.dumps(original))
                target = candidate["state"] if (key, value) in states else candidate
                target[key] = value
                line = b"TSK_NATIVE_KEYBOARD_HID_REQUEST_V1 " + json.dumps(candidate).encode() + b"\n"
                with self.assertRaises(ValueError):
                    relay.parse_marker(line, TOKEN)

    def test_rejects_truncated_oversized_duplicate_key_and_nonfinite_records(self):
        candidates = [
            MARKER[:-1],
            MARKER.replace(b'"phase":"commandReturn"', b'"phase":"plain","phase":"commandReturn"'),
            MARKER.replace(b'"processID":1245', b'"processID":NaN'),
            MARKER.replace(b'{"caseName"', b'{"padding":"' + b"x" * 1100 + b'","caseName"'),
            b"TSK_NATIVE_KEYBOARD_HID_REQUEST_V1 \xff\n",
        ]
        for line in candidates:
            with self.subTest(length=len(line)), self.assertRaises(ValueError):
                relay.parse_marker(line, TOKEN)

    def test_chunked_log_accepts_one_record_and_rejects_replay(self):
        reader = relay.MarkerReader(TOKEN)
        self.assertIsNone(reader.feed(b"unrelated XCTest log\n" + MARKER[:41]))
        self.assertIsNone(reader.feed(MARKER[41:-1]))
        self.assertEqual(reader.feed(b"\n")["state"]["processID"], 1245)
        with self.assertRaises(ValueError):
            reader.feed(MARKER)

    def test_duplicate_batch_and_missing_truncated_oversized_logs_fail(self):
        with self.assertRaises(ValueError):
            relay.MarkerReader(TOKEN).feed(MARKER + MARKER)
        for partial in [b"", MARKER[:-1]]:
            reader = relay.MarkerReader(TOKEN)
            reader.feed(partial)
            with self.assertRaises(ValueError):
                reader.finish()
        with self.assertRaises(ValueError):
            relay.MarkerReader(TOKEN).feed(b"x" * 4097)


class ChordTests(unittest.IsolatedAsyncioTestCase):
    async def test_one_rpc_contains_all_four_explicit_key_directions(self):
        observed = []

        async def send(events):
            observed.append(events)

        await relay.dispatch_chord(send)
        self.assertEqual(observed, [((227, "DOWN"), (40, "DOWN"), (40, "UP"), (227, "UP"))])

    async def test_error_and_cancellation_send_only_up_cleanup_then_fail(self):
        for error in [RuntimeError("RPC failed"), asyncio.CancelledError()]:
            observed = []

            async def send(events):
                observed.append(events)
                if len(observed) == 1:
                    raise error

            with self.assertRaises(type(error)):
                await relay.dispatch_chord(send)
            self.assertEqual(observed, [((227, "DOWN"), (40, "DOWN"), (40, "UP"), (227, "UP")), ((40, "UP"), (227, "UP"))])

    async def test_cleanup_failure_never_turns_original_failure_into_success(self):
        async def send(events):
            raise RuntimeError("RPC or cleanup failed")

        with self.assertRaisesRegex(RuntimeError, "RPC or cleanup failed") as raised:
            await relay.dispatch_chord(send)
        self.assertIn("HID UP cleanup unconfirmed", raised.exception.__notes__[0])


class ArmedLogTests(unittest.TestCase):
    def test_arming_skips_existing_bytes_and_observes_only_one_future_request(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "live.log"
            path.write_bytes(MARKER)
            with relay.ArmedLog(path, TOKEN) as log:
                self.assertIsNone(log.poll())
                with path.open("ab", buffering=0) as writer:
                    writer.write(MARKER)
                self.assertEqual(log.poll()["state"]["processID"], 1245)
                with path.open("ab", buffering=0) as writer:
                    writer.write(MARKER)
                with self.assertRaises(ValueError):
                    log.poll()

    def test_truncation_or_replacement_after_arming_fails_closed(self):
        for replace in [False, True]:
            with self.subTest(replace=replace), tempfile.TemporaryDirectory() as directory:
                path = pathlib.Path(directory) / "live.log"
                path.write_bytes(b"existing log\n")
                with relay.ArmedLog(path, TOKEN) as log:
                    if replace:
                        path.unlink()
                    path.write_bytes(b"")
                    with self.assertRaises(ValueError):
                        log.poll()


if __name__ == "__main__":
    unittest.main()
