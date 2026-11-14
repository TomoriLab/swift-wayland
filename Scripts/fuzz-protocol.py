#!/usr/bin/env python3
"""Run a deterministic bounded XML/typed-generation mutation corpus without external dependencies."""
import importlib.util
import json
from pathlib import Path
import random
import xml.etree.ElementTree as ElementTree
ROOT = Path(__file__).resolve().parent.parent
def load(name):
    specification = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT/'Scripts'/(name+'.py'))
    module = importlib.util.module_from_spec(specification); specification.loader.exec_module(module)
    return module
schema = load('generate-protocol'); typed = load('generate-typed-protocol')
seed = 0x5741594c414e44
randomizer = random.Random(seed)
base = b'<protocol name="fixture"><interface name="fixture_object" version="2"><request name="send"><arg name="value" type="uint"/></request><event name="receive"><arg name="descriptor" type="fd"/></event></interface></protocol>'
corpus = [base, (ROOT/'Protocols/wayland.xml').read_bytes(), b'', b'\xff',
          b'<!DOCTYPE protocol><protocol name="test"/>', b'\xef\xbb\xbf'+base,
          base.replace(b'name="value"', b'name="id" type="uint"/><arg name="identifier"'),
          base.replace(b'name="send"',b'name="_"'),
          base.replace(b'<event',b'<request name="s_end"/><request name="s__end"/><event')]
for _ in range(2000):
    value = bytearray(base)
    for _ in range(randomizer.randrange(1, 6)):
        operation = randomizer.randrange(3)
        index = randomizer.randrange(len(value)+1)
        if operation == 0: value[index:index] = bytes([randomizer.randrange(256)])
        elif operation == 1 and index < len(value): del value[index]
        elif index < len(value): value[index] = randomizer.randrange(256)
    corpus.append(bytes(value))
accepted = rejected = 0
for value in corpus:
    try:
        model = schema.parse(value)
        first = typed.generate(model)
        assert first == typed.generate(model)
        assert schema.swift(model) == schema.swift(model)
        accepted += 1
    except (ValueError, UnicodeDecodeError, ElementTree.ParseError): rejected += 1
# Names that differ in XML but collapse to one Swift spelling must fail generation.
collisions = [b'<request name="a_b"/><request name="a__b"/>',
              b'<request name="send"><arg name="id" type="uint"/><arg name="identifier" type="uint"/></request>']
for contents in collisions:
    model = schema.parse(b'<protocol name="test"><interface name="test_object" version="1">'+contents+b'</interface></protocol>')
    try: typed.generate(model)
    except ValueError: pass
    else: raise RuntimeError('Typed identifier collision was accepted.')
report = {'seed': seed, 'inputs':len(corpus), 'accepted':accepted, 'rejected':rejected,
          'collisionRegressions':len(collisions), 'passed':True,
          'scope':'Deterministic bounded mutation corpus; not an exhaustive fuzzing proof.'}
(ROOT/'.build/protocol-fuzz.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
