#!/usr/bin/env python3
"""Cross-check Swift schema metadata against the independent native scanner."""
import importlib.util
import json
import tempfile
import re
import sys
sys.dont_write_bytecode = True
import subprocess
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
specification = importlib.util.spec_from_file_location("protocol_generator", ROOT / "Scripts/generate-protocol.py")
generator = importlib.util.module_from_spec(specification)
specification.loader.exec_module(generator)

class InvalidProtocolTests(unittest.TestCase):
    def parse(self, body):
        return generator.parse(('<protocol name="test"><interface name="test_interface" version="2">' + body + '</interface></protocol>').encode())

    def test_duplicate_names(self):
        with self.assertRaises(ValueError): self.parse('<request name="same"/><request name="same"/>')

    def test_unknown_semantic_attributes(self):
        with self.assertRaises(ValueError): self.parse('<request name="send" unrecognized="true"/>')

    def test_nullable_scalar(self):
        with self.assertRaises(ValueError): self.parse('<event name="receive"><arg name="number" type="uint" allow-null="true"/></event>')

    def test_unknown_interface(self):
        with self.assertRaises(ValueError): self.parse('<event name="receive"><arg name="object" type="object" interface="missing"/></event>')

    def test_future_message(self):
        with self.assertRaises(ValueError): self.parse('<request name="send" since="3"/>')

    def test_opcode_version_order(self):
        with self.assertRaises(ValueError): self.parse('<request name="newer" since="2"/><request name="older"/>')

    def test_invalid_nesting(self):
        with self.assertRaises(ValueError): self.parse('<description><request name="hidden"/></description>')

    def test_entities_and_quota(self):
        with self.assertRaises(ValueError): generator.parse(b'<!DOCTYPE protocol [<!ENTITY test "data">]><protocol name="test"/>')
        with self.assertRaises(ValueError): generator.parse(b' ' * (4 * 1024 * 1024 + 1))

    def test_encoded_dtd_cannot_bypass_rejection(self):
        document = '<!DOCTYPE protocol [<!ENTITY test "data">]><protocol name="test"/>'
        for encoding in ['utf-16', 'utf-32']:
            with self.assertRaises(ValueError): generator.parse(document.encode(encoding))

    def test_copyright_cannot_inject_swift_source(self):
        model = generator.parse(b'<protocol name="test"><copyright>*/\nTHIS IS NOT VALID SWIFT SOURCE!\n/*</copyright><interface name="test_interface" version="1"/></protocol>')
        directory = ROOT / '.build/protocol-comment-probe'
        directory.mkdir(parents=True, exist_ok=True)
        generated = directory / 'Generated.swift'
        generated.write_text(generator.swift(model))
        toolchain_specification = importlib.util.spec_from_file_location('toolchain', ROOT / 'Scripts/verify-toolchain.py')
        toolchain = importlib.util.module_from_spec(toolchain_specification)
        toolchain_specification.loader.exec_module(toolchain)
        result = subprocess.run([toolchain.compiler_path(None), '-swift-version', '6', '-strict-memory-safety',
            '-warnings-as-errors', '-parse-as-library', '-package-name', 'swift_wayland', '-emit-module',
            '-module-name', 'ProtocolCommentProbe', str(ROOT / 'Sources/WaylandProtocol/Schema.swift'), str(generated),
            '-o', str(directory / 'ProtocolCommentProbe.swiftmodule')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_negative_and_unknown_enum_values(self):
        model = self.parse('<enum name="code"><entry name="negative" value="-1"/><entry name="future" value="0xffffffff"/></enum>')
        self.assertEqual([entry['value'] for entry in model['interfaces'][0]['enumerations'][0]['entries']], [0xffffffff, 0xffffffff])

class ImportedProtocolTests(unittest.TestCase):
    first = b'<protocol name="first"><interface name="alpha" version="2"><request name="create"><arg name="identifier" type="new_id" interface="beta"/></request><enum name="mode"><entry name="one" value="1"/></enum></interface></protocol>'
    second = b'<protocol name="second"><interface name="beta" version="1"><event name="reference"><arg name="parent" type="object" interface="alpha"/><arg name="mode" type="uint" enum="alpha.mode"/></event></interface></protocol>'

    def test_cross_file_cycles_and_enums(self):
        model = generator.parse_bundle([self.first, self.second])
        self.assertEqual([interface['name'] for interface in model['interfaces']], ['alpha', 'beta'])
        self.assertEqual(model['interfaces'][1]['events'][0]['arguments'][1]['enumeration'], 'alpha.mode')
        self.assertEqual(model, generator.parse_bundle([self.first, self.second]))
        self.assertNotEqual(model['sha256'], generator.parse_bundle([self.second, self.first])['sha256'])

    def test_missing_duplicate_and_invalid_imports(self):
        for documents in [[self.first], [self.first, self.first], [], [self.first] * 65,
                          [self.first, self.second.replace(b'alpha.mode', b'alpha.missing')],
                          [self.first, self.second.replace(b'type="object"', b'type="uint"')],
                          [self.first, self.second.replace(b'<event name="reference">', b'<event name="reference" unknown="true">')]]:
            with self.assertRaises(ValueError): generator.parse_bundle(documents)

    def test_native_integer_and_constructor_limits(self):
        for body in [b'<protocol name="test"><interface name="test" version="2147483648"/></protocol>',
                     b'<protocol name="test"><interface name="test" version="1"><event name="create"><arg name="identifier" type="new_id"/></event></interface></protocol>']:
            with self.assertRaises(ValueError): generator.parse(body)

    def test_cli_and_external_module_compilation(self):
        with tempfile.TemporaryDirectory(prefix='protocol-import-') as temporary:
            directory = Path(temporary)
            first = directory / 'first.xml'; first.write_bytes(self.first)
            second = directory / 'second.xml'; second.write_bytes(self.second)
            command = ['python3', str(ROOT/'Scripts/generate-protocol.py'), '--xml', str(first),
                       '--import', str(second), '--output-directory', str(directory), '--namespace', 'ImportedProtocol']
            subprocess.run(command, check=True, capture_output=True)
            subprocess.run(command + ['--check'], check=True, capture_output=True)
            self.assertEqual(len(json.loads((directory/'protocol-manifest.json').read_text())['inputs']), 2)
            specification = importlib.util.spec_from_file_location('toolchain_imports', ROOT/'Scripts/verify-toolchain.py')
            toolchain = importlib.util.module_from_spec(specification); specification.loader.exec_module(toolchain)
            compiler = toolchain.compiler_path(None)
            flags = [compiler, '-swift-version', '6', '-strict-memory-safety', '-warnings-as-errors', '-parse-as-library', '-emit-module']
            subprocess.run([*flags, '-module-name', 'WaylandProtocol', str(ROOT/'Sources/WaylandProtocol/Schema.swift'),
                            '-o', str(directory/'WaylandProtocol.swiftmodule')], check=True, capture_output=True)
            result = subprocess.run([*flags, '-module-name', 'ImportedProtocol', '-I', str(directory),
                            str(directory/'ImportedProtocol.swift'), '-o', str(directory/'ImportedProtocol.swiftmodule')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            for source in [first, second]:
                native_path = source.with_suffix('.c')
                subprocess.run(['wayland-scanner', 'private-code', str(source), str(native_path)], check=True, capture_output=True)
                native = native_path.read_text()
                interface = generator.parse_bundle([self.first, self.second])['interfaces'][0 if source == first else 1]
                for direction in ['requests', 'events']:
                    for message in interface[direction]:
                        self.assertIn('"' + message['name'] + '", "' + signature(message) + '"', native)

def signature(message):
    value = str(message['since']) if message['since'] > 1 else ''
    codes = {'int': 'i', 'uint': 'u', 'fixed': 'f', 'string': 's', 'object': 'o', 'new_id': 'n', 'array': 'a', 'fd': 'h'}
    for argument in message['arguments']:
        if argument['kind'] == 'new_id' and argument['interface'] is None: value += 'su'
        if argument['nullable']: value += '?'
        value += codes[argument['kind']]
    return value

def main():
    suite = unittest.TestSuite([unittest.defaultTestLoader.loadTestsFromTestCase(case) for case in [InvalidProtocolTests, ImportedProtocolTests]])
    if not unittest.TextTestRunner().run(suite).wasSuccessful(): return 1
    subprocess.run(['python3', str(ROOT / 'Scripts/generate-protocol.py'), '--check'], check=True)
    subprocess.run(['python3', str(ROOT / 'Scripts/generate-typed-protocol.py'), '--check'], check=True)
    output = ROOT / '.build/native-protocol.c'
    subprocess.run(['wayland-scanner', 'private-code', str(ROOT / 'Protocols/wayland.xml'), str(output)], check=True)
    native = output.read_text()
    model = generator.parse((ROOT / 'Protocols/wayland.xml').read_bytes())
    count = 0
    for interface in model['interfaces']:
        for direction in ['requests', 'events']:
            messages = interface[direction]
            if not messages: continue
            match = re.search(r'static const struct wl_message ' + interface['name'] + '_' + direction + r'\[\] = \{(.*?)\n\};', native, re.S)
            if not match: raise RuntimeError('Native message table missing: ' + interface['name'])
            actual = re.findall(r'\{ "([^"]+)", "([^"]*)",', match.group(1))
            expected = [(message['name'], signature(message)) for message in messages]
            if actual != expected: raise RuntimeError('Native schema mismatch: ' + interface['name'])
            count += len(messages)
    print('Native wayland-scanner equivalence passed for', count, 'message names, opcodes, and signatures.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
