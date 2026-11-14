"""Check that DocC retains include paths already present in CPATH."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

specification = importlib.util.spec_from_file_location(
    'documentation', Path(__file__).resolve().parents[2] / 'Scripts/build-documentation.py')
documentation = importlib.util.module_from_spec(specification)
specification.loader.exec_module(documentation)


class DocumentationFlagsTests(unittest.TestCase):
    def test_cpath_does_not_remove_explicit_include_flags(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            include = root / 'include'
            include.mkdir()
            for name in ['client', 'server', 'cursor', 'egl']:
                (root / ('wayland-' + name + '.pc')).write_text(
                    'Name: fixture\nDescription: Header search regression\n'
                    'Version: 1.26.0\nCflags: -I' + str(include) + '\n')
            environment = dict(os.environ, PKG_CONFIG_LIBDIR=str(root),
                               PKG_CONFIG_PATH=str(root), CPATH=str(include))
            environment.pop('PKG_CONFIG_ALLOW_SYSTEM_CFLAGS', None)
            baseline = subprocess.check_output(
                ['pkg-config', '--cflags', 'wayland-client'], env=environment, text=True)
            self.assertNotIn(str(include), baseline)
            flags = documentation.native_compiler_flags(environment)
            self.assertIn('-I' + str(include), flags)
            self.assertEqual(flags[flags.index('-I' + str(include)) - 1], '-Xcc')
            self.assertNotIn('PKG_CONFIG_ALLOW_SYSTEM_CFLAGS', environment)


if __name__ == '__main__':
    unittest.main()
