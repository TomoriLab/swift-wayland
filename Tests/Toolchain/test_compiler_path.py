"""Check compiler discovery through external launcher links and driver aliases."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

specification = importlib.util.spec_from_file_location(
    'toolchain', Path(__file__).resolve().parents[2] / 'Scripts/verify-toolchain.py')
toolchain = importlib.util.module_from_spec(specification)
specification.loader.exec_module(toolchain)


class CompilerPathTests(unittest.TestCase):
    def test_external_launcher_resolves_sibling_tools_and_preserves_driver_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binaries = root / 'toolchain/usr/bin'
            binaries.mkdir(parents=True)
            (binaries / 'swift-driver').touch()
            (binaries / 'swiftc').symlink_to('swift-driver')
            for name in ['clang', 'swift', 'docc']:
                (binaries / name).touch()
            launcher = root / 'launchers/swiftc'
            launcher.parent.mkdir()
            launcher.symlink_to(binaries / 'swiftc')
            for mode in ['argument', 'environment', 'path']:
                with self.subTest(mode=mode), patch.dict(os.environ, {}, clear=True), patch.object(
                    toolchain.shutil, 'which', return_value=str(launcher)):
                    if mode == 'environment':
                        os.environ['SWIFTC'] = str(launcher)
                    compiler = toolchain.compiler_path(str(launcher) if mode == 'argument' else None)
                    self.assertEqual(compiler, binaries / 'swiftc')
                    for name in ['clang', 'swift', 'docc']:
                        self.assertTrue(compiler.with_name(name).is_file())

    def test_missing_compiler_entry_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            driver = Path(directory) / 'swift-driver'
            driver.touch()
            with self.assertRaisesRegex(RuntimeError, 'no swiftc entry point'):
                toolchain.compiler_path(str(driver))


if __name__ == '__main__':
    unittest.main()
