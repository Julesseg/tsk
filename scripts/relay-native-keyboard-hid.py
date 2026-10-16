import argparse
import asyncio
import importlib.metadata
import json
import logging
import os
import pathlib
import signal
import stat
import sys
import time
import uuid

PREFIX = b"TSK_NATIVE_KEYBOARD_HID_REQUEST_V1 "
CASE = "TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys"
MAX_PAYLOAD = 1024
CHORD = ((227, "DOWN"), (40, "DOWN"), (40, "UP"), (227, "UP"))
RELEASES = ((40, "UP"), (227, "UP"))


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate marker field")
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError("Nonfinite marker value: " + value)


def parse_marker(line, expected_token):
    if PREFIX not in line:
        return None
    if line.count(PREFIX) != 1 or not line.endswith(b"\n"):
        raise ValueError("Ambiguous or truncated HID marker")
    before, payload = line.split(PREFIX, 1)
    if len(before) > 256 or len(payload.rstrip(b"\r\n")) > MAX_PAYLOAD:
        raise ValueError("HID marker exceeds its byte budget")
    request = json.loads(payload, object_pairs_hook=unique_object, parse_constant=reject_constant)
    if not isinstance(request, dict) or set(request) != {"caseName", "phase", "relayToken", "token", "state"}:
        raise ValueError("Unexpected HID marker fields")
    if request["caseName"] != CASE or request["phase"] != "commandReturn":
        raise ValueError("Unexpected HID case or phase")
    try:
        if uuid.UUID(request["relayToken"]) != uuid.UUID(expected_token):
            raise ValueError("HID relay token does not match this run")
        uuid.UUID(request["token"])
    except (AttributeError, TypeError) as error:
        raise ValueError("HID marker token is not a UUID") from error
    state = request["state"]
    expected = {"firstResponder": True, "textLength": 1, "textIsPlainN": True, "commandNCount": 1, "commandReturnCount": 0}
    if not isinstance(state, dict) or set(state) != {"processID", *expected}:
        raise ValueError("Unexpected native state fields")
    if type(state["processID"]) is not int or not 0 < state["processID"] <= 2_147_483_647:
        raise ValueError("Native app PID is invalid")
    if any(type(state[key]) is not type(value) or state[key] != value for key, value in expected.items()):
        raise ValueError("Native focus or input baseline is not ready")
    return request


class MarkerReader:
    def __init__(self, expected_token):
        self.expected_token = expected_token
        self.buffer = b""
        self.request = None
        self.total = 0

    def feed(self, chunk):
        self.total += len(chunk)
        if self.total > 8 * 1024 * 1024:
            raise ValueError("Live log exceeds the relay byte budget")
        self.buffer += chunk
        received = None
        while b"\n" in self.buffer:
            line, self.buffer = self.buffer.split(b"\n", 1)
            if len(line) > 4096:
                raise ValueError("Live log line exceeds the relay byte budget")
            candidate = parse_marker(line + b"\n", self.expected_token)
            if candidate is not None:
                if self.request is not None:
                    raise ValueError("Duplicate HID request; no second chord permitted")
                self.request = received = candidate
        if len(self.buffer) > 4096:
            raise ValueError("Truncated or oversized live log line")
        return received

    def finish(self):
        if self.buffer and (PREFIX in self.buffer or PREFIX.startswith(self.buffer)):
            raise ValueError("Truncated HID marker")
        if self.request is None:
            raise ValueError("No HID request marker before the deadline")
        return self.request


class ArmedLog:
    def __init__(self, path, token):
        self.path = pathlib.Path(path)
        self.file = self.path.open("rb", buffering=0)
        info = os.fstat(self.file.fileno())
        if not stat.S_ISREG(info.st_mode):
            self.file.close()
            raise ValueError("The explicit live log must be a regular file")
        self.identity = (info.st_dev, info.st_ino)
        self.file.seek(0, os.SEEK_END)
        self.start_offset = self.file.tell()
        self.reader = MarkerReader(token)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.file.close()

    def poll(self):
        info = self.path.stat()
        if (info.st_dev, info.st_ino) != self.identity or info.st_size < self.file.tell():
            raise ValueError("The armed log was replaced or truncated")
        while chunk := self.file.read(4096):
            self.reader.feed(chunk)
        return self.reader.request


async def dispatch_chord(send):
    try:
        await asyncio.wait_for(send(CHORD), timeout=5)
    except BaseException as error:
        cleanup = asyncio.create_task(asyncio.wait_for(send(RELEASES), timeout=5))
        try:
            await asyncio.shield(cleanup)
            error.add_note("HID UP cleanup RPC completed; native key state remains unverified")
        except BaseException as cleanup_error:
            error.add_note("HID UP cleanup unconfirmed: " + repr(cleanup_error))
        raise


def make_sender(socket):
    if importlib.metadata.version("fb-idb") != "1.7.3":
        raise ValueError("This comparison requires pinned fb-idb 1.7.3")
    from idb.common.types import DomainSocketAddress, HIDDirection, HIDKey, HIDPress
    from idb.grpc.client import Client

    async def send(events):
        presses = [HIDPress(action=HIDKey(keycode=code), direction=getattr(HIDDirection, direction)) for code, direction in events]
        async with Client.build(address=DomainSocketAddress(path=socket), logger=logging.getLogger("owned-native-hid"), exchange_metadata=False) as client:
            await client.send_events(presses)

    return send


def save_receipt(path, receipt):
    temporary = path.with_name(path.name + "." + str(os.getpid()) + ".tmp")
    with temporary.open("w") as file:
        json.dump(receipt, file, indent=2)
        file.write("\n")
        file.flush()
        os.fsync(file.fileno())
    temporary.replace(path)


async def run(args):
    receipt_path = pathlib.Path(args.receipt)
    with receipt_path.open("x"):
        pass
    receipt = {"state": "preparing", "udid": args.udid, "socket": args.socket, "companionPID": args.companion_pid, "relayToken": args.relay_token, "targetBinding": "Owner supplied; no target discovery or independent UDID lookup", "nativeAcceptance": "Only unchanged XCTest counter/text assertions can establish acceptance"}
    save_receipt(receipt_path, receipt)
    loop = asyncio.get_running_loop()
    task = asyncio.current_task()
    loop.add_signal_handler(signal.SIGTERM, task.cancel)
    try:
        if not stat.S_ISSOCK(pathlib.Path(args.socket).stat().st_mode):
            raise ValueError("The explicit companion address is not a Unix socket")
        send = make_sender(args.socket)
        with ArmedLog(args.log, args.relay_token) as log:
            receipt.update(state="waiting", log=args.log, logStartOffset=log.start_offset, armedMonotonic=time.monotonic())
            save_receipt(receipt_path, receipt)
            print("TSK_NATIVE_HID_RELAY_ARMED_V1 " + args.relay_token, flush=True)
            deadline = time.monotonic() + args.wait_seconds
            while time.monotonic() < deadline:
                request = log.poll()
                if request is not None:
                    break
                await asyncio.sleep(0.01)
            else:
                request = log.reader.finish()
            log.reader.finish()
            receipt.update(state="sending", request=request, markerObservedMonotonic=time.monotonic())
            await dispatch_chord(send)
            receipt["rpcCompletedMonotonic"] = time.monotonic()
            log.poll()
            log.reader.finish()
            receipt.update(state="hid_rpc_completed_native_assertions_required", events=CHORD)
            save_receipt(receipt_path, receipt)
    except BaseException as error:
        receipt.update(state="failed", error=repr(error), notes=getattr(error, "__notes__", []))
        save_receipt(receipt_path, receipt)
        raise
    finally:
        loop.remove_signal_handler(signal.SIGTERM)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--udid", required=True)
    parser.add_argument("--companion-pid", required=True, type=int)
    parser.add_argument("--relay-token", required=True)
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--wait-seconds", type=float, default=120)
    args = parser.parse_args()
    for value in [args.udid, args.relay_token]:
        uuid.UUID(value)
    if args.companion_pid <= 0 or not 0 < args.wait_seconds <= 120:
        parser.error("Companion PID and bounded wait must be positive")
    if not all(pathlib.Path(value).is_absolute() for value in [args.log, args.socket, args.receipt]):
        parser.error("Log, socket and receipt paths must be explicit absolute paths")
    return args


if __name__ == "__main__":
    try:
        asyncio.run(run(parse_args()))
    except BaseException as error:
        if isinstance(error, SystemExit):
            raise
        print("Native HID relay failed: " + repr(error), file=sys.stderr, flush=True)
        raise SystemExit(1)
