import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


client = load("remote-ios")
worker = load("remote-ios-worker")


class RemoteIOSTests(unittest.TestCase):
    def test_snapshot_includes_current_edits_and_new_source_without_deleted_ignored_or_environment_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "tracked.swift").write_text("original")
            (root / "deleted.swift").write_text("deleted")
            (root / ".gitignore").write_text(".build/\n")
            subprocess.run(["git", "-C", str(root), "add", "."], check=True)
            (root / "tracked.swift").write_text("edited")
            (root / "deleted.swift").unlink()
            (root / "new.swift").write_text("new")
            (root / ".env.local").write_text("private")
            (root / ".build").mkdir()
            (root / ".build/output").write_text("build")
            (root / "linked.swift").symlink_to("tracked.swift")
            snapshot = io.BytesIO()
            client.write_snapshot(root, snapshot)
            with tarfile.open(fileobj=snapshot) as archive:
                self.assertEqual(set(archive.getnames()), {".gitignore", "tracked.swift", "new.swift", "linked.swift"})
                self.assertEqual(archive.extractfile("tracked.swift").read(), b"edited")
                self.assertEqual(archive.extractfile("linked.swift").read(), b"edited")

    def test_snapshot_rejects_a_link_outside_the_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "external").symlink_to("/etc/hosts")
            with self.assertRaisesRegex(ValueError, "leaves this checkout"):
                client.write_snapshot(root, io.BytesIO())

    def test_resync_removes_stale_source_and_preserves_mac_build_caches(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            source = workspace / "source"
            for name in ["Core/.build/cache", "Native/Bridge/target/cache", "Native/Artifacts/cache", "obsolete.swift"]:
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("old")
            snapshot = io.BytesIO()
            with tarfile.open(fileobj=snapshot, mode="w:gz") as archive:
                info = tarfile.TarInfo("Core/current.swift")
                info.size = 3
                info.mtime = 1700000000
                archive.addfile(info, io.BytesIO(b"new"))
                archive.addfile(tarfile.TarInfo("Native/Bridge/Cargo.toml"), io.BytesIO())
            snapshot.seek(0)
            worker.sync_snapshot(snapshot, workspace, os.environ.copy())
            self.assertFalse((source / "obsolete.swift").exists())
            self.assertEqual((source / "Core/current.swift").read_text(), "new")
            self.assertEqual((source / "Core/current.swift").stat().st_mtime, 1700000000)
            for name in ["Core/.build/cache", "Native/Bridge/target/cache", "Native/Artifacts/cache"]:
                self.assertEqual((source / name).read_text(), "old")
            (source / "Core/current.swift").write_text("old")
            os.utime(source / "Core/current.swift", (1700000000, 1700000000))
            snapshot.seek(0)
            worker.sync_snapshot(snapshot, workspace, os.environ.copy())
            self.assertEqual((source / "Core/current.swift").read_text(), "new")

    def test_unsafe_archives_leave_existing_source_untouched(self):
        for name, kind in [("../outside", tarfile.REGTYPE), ("/outside", tarfile.REGTYPE), ("linked", tarfile.SYMTYPE)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                workspace = Path(directory)
                (workspace / "source").mkdir()
                existing = workspace / "source/current.swift"
                existing.write_text("retained")
                snapshot = io.BytesIO()
                with tarfile.open(fileobj=snapshot, mode="w:gz") as archive:
                    info = tarfile.TarInfo(name)
                    info.type = kind
                    info.linkname = "../outside" if kind == tarfile.SYMTYPE else ""
                    archive.addfile(info)
                snapshot.seek(0)
                with self.assertRaisesRegex(ValueError, "Invalid source archive"):
                    worker.sync_snapshot(snapshot, workspace, os.environ.copy())
                self.assertEqual(existing.read_text(), "retained")

    def test_ambiguous_or_option_like_hosts_require_an_explicit_valid_target(self):
        with self.assertRaisesRegex(ValueError, "exactly one"):
            client.select_host(None, {"deviceHosts": [{"kind": "ssh", "target": "mac-one"}, {"kind": "ssh", "target": "mac-two"}]})
        with self.assertRaises(ValueError):
            client.select_host("-oProxyCommand=bad", {})
        self.assertEqual(client.select_host("user@mac", {})["target"], "user@mac")

    def test_install_and_unfocused_tests_fail_before_connecting(self):
        for arguments in [["install"], ["test", "--device", "invalid"], ["test", "--device", "B35FFC8F-C663-4EAD-83CD-97167A8F7D50"]]:
            result = subprocess.run(["python3", str(Path(client.__file__)), *arguments], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("Remote Mac:", result.stdout)

    def test_launcher_clears_inherited_electron_mode_before_starting_python(self):
        environment = dict(os.environ, ELECTRON_RUN_AS_NODE="1")
        result = subprocess.run(["bash", str(Path(client.__file__).with_suffix(".sh")), "--help"],
                                capture_output=True, text=True, env=environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("isolated Mac cache", result.stdout)


if __name__ == "__main__":
    unittest.main()
