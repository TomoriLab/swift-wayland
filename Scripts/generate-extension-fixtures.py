#!/usr/bin/env python3
"""Keep managed extension lifecycle schemas tied to their XML fixture."""
import argparse
import importlib.util
from pathlib import Path
import sys
import subprocess
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
specification = importlib.util.spec_from_file_location('schema_generator', ROOT/'Scripts/generate-protocol.py')
generator = importlib.util.module_from_spec(specification);specification.loader.exec_module(generator)
parser = argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');arguments=parser.parse_args()
model = generator.parse_bundle([(ROOT/'Protocols/Fixtures/lifecycle.xml').read_bytes()])
content = generator.swift(model, 'ExtensionFixture', external=True)
path = ROOT/'Tests/WaylandRuntimeTests/ExtensionFixtureSchemas.swift'
if arguments.check:generator.require(path.read_text()==content,'Extension fixture schema differs from its XML.')
else:path.write_text(content)
binding_command = [sys.executable, str(ROOT/'Scripts/generate-extension-bindings.py'), '--xml',
                   str(ROOT/'Protocols/Fixtures/lifecycle.xml'), '--output-directory',
                   str(ROOT/'Tests/WaylandRuntimeTests'), '--namespace', 'ExtensionFixture']
if arguments.check: binding_command.append('--check')
subprocess.run(binding_command, check=True)
print('Verified' if arguments.check else 'Generated','extension lifecycle fixture schemas.')
