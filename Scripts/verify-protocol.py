#!/usr/bin/env python3
"""Cross-check Swift schema metadata against the independent native scanner."""
import importlib.util
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

def signature(message):
    value = str(message['since']) if message['since'] > 1 else ''
    codes = {'int': 'i', 'uint': 'u', 'fixed': 'f', 'string': 's', 'object': 'o', 'new_id': 'n', 'array': 'a', 'fd': 'h'}
    for argument in message['arguments']:
        if argument['kind'] == 'new_id' and argument['interface'] is None: value += 'su'
        if argument['nullable']: value += '?'
        value += codes[argument['kind']]
    return value

def main():
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(InvalidProtocolTests)
    if not unittest.TextTestRunner().run(suite).wasSuccessful(): return 1
    subprocess.run(['python3', str(ROOT / 'Scripts/generate-protocol.py'), '--check'], check=True)
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
