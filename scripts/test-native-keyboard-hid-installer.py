import importlib.util
import io
import pathlib
import tarfile
import tempfile
import unittest

path = pathlib.Path(__file__).with_name('install-native-keyboard-hid.py')
spec = importlib.util.spec_from_file_location('hid_installer', path)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def test_digest_and_size_must_both_match_before_use(self):
        with tempfile.TemporaryDirectory() as root:
            path = pathlib.Path(root) / 'asset'
            path.write_bytes(b'abc')
            installer.verify_asset(path, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 3)
            for digest, size in [('0' * 64, 3), ('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 4)]:
                with self.assertRaises(ValueError):
                    installer.verify_asset(path, digest, size)

    def test_extraction_preserves_adjacent_companion_resources(self):
        with tempfile.TemporaryDirectory() as root:
            archive = pathlib.Path(root) / 'companion.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                for name in ['idb_companion', 'Resources/transport.json']:
                    info = tarfile.TarInfo(name)
                    info.size = 3
                    tar.addfile(info, io.BytesIO(b'abc'))
            destination = pathlib.Path(root) / 'companion'
            installer.extract_companion(archive, destination)
            self.assertEqual((destination / 'Resources/transport.json').read_bytes(), b'abc')

    def test_extraction_rejects_paths_outside_the_owned_directory(self):
        with tempfile.TemporaryDirectory() as root:
            archive = pathlib.Path(root) / 'companion.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                info = tarfile.TarInfo('../escape')
                info.size = 3
                tar.addfile(info, io.BytesIO(b'abc'))
            with self.assertRaises(tarfile.TarError):
                installer.extract_companion(archive, pathlib.Path(root) / 'companion')
            self.assertFalse((pathlib.Path(root) / 'escape').exists())


if __name__ == '__main__':
    unittest.main()
