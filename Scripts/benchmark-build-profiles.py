#!/usr/bin/env python3
"""Compare isolated release compiler profiles without replacing the acceptance benchmark."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / '.build/build-profile-benchmark'
OUTPUT.mkdir(parents=True, exist_ok=True)
REPORT = OUTPUT / 'report.json'
REPORT.write_text(json.dumps({'measurementCompleted': False}) + '\n')
specification = importlib.util.spec_from_file_location('toolchain', ROOT / 'Scripts/verify-toolchain.py')
toolchain = importlib.util.module_from_spec(specification)
specification.loader.exec_module(toolchain)
swift = Path(toolchain.compiler_path(None)).with_name('swift')
environment = os.environ.copy()
for name in ['LD_PRELOAD', 'CC', 'CXX', 'CPP', 'LD', 'AR', 'NM', 'RANLIB', 'STRIP']:
    environment.pop(name, None)


def input_snapshot():
    paths = [Path(__file__), ROOT / 'Package.swift']
    for folder in ['Protocols', 'Sources', 'Benchmarks/Typed', 'Tests/RuntimeNativeTestSupport']:
        paths.extend(path for path in (ROOT / folder).rglob('*') if path.is_file())
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


inputs = input_snapshot()
profiles = {'default': [], 'crossModule': ['-Xswiftc', '-cross-module-optimization', '-Xswiftc', '-package-cmo']}
binaries = {}
commands = {}
for profile, flags in profiles.items():
    scratch = OUTPUT / profile
    command = [str(swift), 'build', '--scratch-path', str(scratch), '-c', 'release',
               '--product', 'WaylandTypedBenchmarks', '-Xswiftc', '-warnings-as-errors', *flags]
    commands[profile] = command
    with (OUTPUT / (profile + '-build.log')).open('w') as log:
        subprocess.run(command, cwd=ROOT, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True)
    directory = Path(subprocess.check_output([str(swift), 'build', '--scratch-path', str(scratch),
                                             '-c', 'release', '--show-bin-path'], cwd=ROOT, env=environment, text=True).strip())
    binaries[profile] = directory / 'WaylandTypedBenchmarks'
binary_hashes = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in binaries.items()}
raw = {profile: {} for profile in profiles}
allowed = os.sched_getaffinity(0)
selected = min(allowed)
try:
    os.sched_setaffinity(0, {selected})
    for mode, arguments in [('scalar', []), ('requests', ['--requests']), ('strings', ['--string-requests'])]:
        for profile in profiles:
            raw[profile][mode] = []
        for index in range(3):
            order = ['default', 'crossModule'] if index % 2 == 0 else ['crossModule', 'default']
            for profile in order:
                raw[profile][mode].append(json.loads(subprocess.check_output(
                    [str(binaries[profile]), *arguments], cwd=ROOT, env=environment, text=True)))
finally:
    os.sched_setaffinity(0, allowed)

summary = {}
for profile, modes in raw.items():
    summary[profile] = {}
    for mode, runs in modes.items():
        samples = []
        for index in range(2):
            values = [run['samples'][index] for run in runs]
            native = [value for sample in values for value in sample['nativeSeconds']]
            swift_samples = [value for sample in values for value in sample['swiftSeconds']]
            samples.append({'batch': values[0]['batch'], 'iterations': values[0]['iterations'],
                            'throughputLoss': 1 - statistics.median(native) / statistics.median(swift_samples),
                            'processThroughputLosses': [sample['throughputLoss'] for sample in values]})
        summary[profile][mode] = samples
if inputs != input_snapshot():
    raise RuntimeError('Build-profile benchmark inputs changed during measurement.')
if binary_hashes != {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in binaries.items()}:
    raise RuntimeError('Build-profile benchmark binaries changed during measurement.')
report = {'measurementCompleted': True, 'acceptanceComplete': False,
          'scope': 'Diagnostic throughput comparison only; allocation, latency, sanitizer, and complete performance acceptance remain separate.',
          'compiler': subprocess.check_output([str(swift), '--version'], text=True).strip(),
          'architecture': platform.machine(), 'cpuAffinity': [selected], 'buildCommands': commands,
          'processRuns': 3, 'pairsPerProcess': 9, 'inputs': inputs, 'binaryHashes': binary_hashes,
          'raw': raw, 'summary': summary}
REPORT.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(summary, indent=2))
