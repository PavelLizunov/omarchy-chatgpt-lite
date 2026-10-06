"""Native profile preparation must never touch legacy data or follow links."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native_profile', ROOT / 'native/prepare-profile.py')
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class NativeProfileTests(unittest.TestCase):
    def test_private_new_profile_and_legacy_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            legacy = base / 'omarchy-chatgpt-lite'
            legacy.mkdir()
            sentinel = legacy / 'user-data'
            sentinel.write_text('never migrate credentials')
            profile.prepare(base, 'profile')
            profile.prepare(base, 'profile')
            for path in [base / 'omarchy-chatgpt-lite-qt', base / 'omarchy-chatgpt-lite-qt/profile']:
                self.assertEqual(path.stat().st_mode & 0o777, 0o700)
            self.assertEqual(sentinel.read_text(), 'never migrate credentials')

    def test_rejects_symlink_roots_children_and_ancestors(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            real = base / 'real'
            real.mkdir()
            linked = base / 'linked'
            linked.symlink_to(real, target_is_directory=True)
            with self.assertRaises(ValueError):
                profile.prepare(linked / 'missing', 'profile')
            root = base / 'omarchy-chatgpt-lite-qt'
            root.symlink_to(real, target_is_directory=True)
            with self.assertRaises(OSError):
                profile.prepare(base, 'profile')
            root.unlink()
            root.mkdir()
            (root / 'profile').symlink_to(real, target_is_directory=True)
            with self.assertRaises(OSError):
                profile.prepare(base, 'profile')
            with self.assertRaises(ValueError):
                profile.prepare(Path('relative'), 'profile')


if __name__ == '__main__':
    unittest.main()
