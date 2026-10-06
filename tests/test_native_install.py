"""Inert installer failure tests; no host commands, profiles or credentials."""
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location('native_install', ROOT / 'install-native.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NativeInstall(unittest.TestCase):
    def test_failed_activation_restores_known_files_preserves_unknown(self):
        for fault in (ValueError('incompatible host'), module.subprocess.TimeoutExpired('ipc', 1)):
            with self.subTest(fault=type(fault).__name__), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                target, stage, backup = root / 'target', root / 'stage', root / 'backup'
                target.mkdir()
                stage.mkdir()
                (target / 'manifest.json').write_text('old-routing')
                (target / 'native').mkdir()
                (target / 'native/Browser.qml').write_text('old-browser')
                (target / 'unknown-user-data').write_text('preserve')
                old = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob('*') if p.is_file()}
                shutil.copytree(target, backup / module.PLUGIN_ID)
                for name in (*module.FILES, 'manifest.json'):
                    file = stage / name
                    file.parent.mkdir(exist_ok=True)
                    file.write_text('candidate:' + name)
                commands = []
                def activation():
                    raise fault
                with self.assertRaisesRegex(ValueError, 'rolled back'):
                    module.publish(stage, target, backup, activation, lambda *args: commands.append(args))
                self.assertEqual(old, {str(p.relative_to(target)): p.read_bytes() for p in target.rglob('*') if p.is_file()})
                self.assertEqual(commands, [('omarchy', 'plugin', 'disable', module.PLUGIN_ID),
                                            ('omarchy-shell', 'shell', 'rescanPlugins')])

    def test_success_keeps_native_routing_and_manifest_loaded(self):
        candidate = module.manifest()
        self.assertIs(candidate['keepLoaded'], True)
        self.assertEqual(candidate['kinds'], ['service', 'bar-widget'])
        self.assertNotIn('panel', candidate['entryPoints'])
        self.assertEqual(candidate['entryPoints']['service'], 'native/Service.qml')
        self.assertEqual(candidate['entryPoints']['barWidget'], 'native/BarWidget.qml')
        self.assertIs(candidate['barWidget']['allowMultiple'], False)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target, stage = root / 'target', root / 'stage'
            target.mkdir()
            stage.mkdir()
            for name in (*module.FILES, 'manifest.json'):
                file = stage / name
                file.parent.mkdir(exist_ok=True)
                file.write_text('candidate')
            module.publish(stage, target, root / 'unused-backup', lambda: None, lambda *args: self.fail('unexpected command'))
            self.assertTrue(all((target / name).read_text() == 'candidate' for name in (*module.FILES, 'manifest.json')))

    def test_concurrent_edit_never_overwritten_by_rollback(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target, stage = root / 'target', root / 'stage'
            target.mkdir()
            stage.mkdir()
            for name in (*module.FILES, 'manifest.json'):
                file = stage / name
                file.parent.mkdir(exist_ok=True)
                file.write_text('candidate')
            def activation():
                (target / 'native/Browser.qml').write_text('concurrent')
                raise ValueError('timeout')
            with self.assertRaisesRegex(ValueError, 'concurrent code change'):
                module.publish(stage, target, root / 'backup', activation, lambda *args: None)
            self.assertEqual((target / 'native/Browser.qml').read_text(), 'concurrent')


if __name__ == '__main__':
    unittest.main()
