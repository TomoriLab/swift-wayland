#!/usr/bin/env python3
"""Record a pinned-CPU exploratory dispatcher benchmark and its exact source inputs."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent

def main():
    specification = importlib.util.spec_from_file_location('toolchain', ROOT / 'Scripts/verify-toolchain.py')
    toolchain = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(toolchain)
    swift = Path(toolchain.compiler_path(None)).with_name('swift')
    environment = os.environ.copy()
    for name in ['CC', 'CXX', 'CPP', 'LD', 'AR', 'NM', 'RANLIB', 'STRIP', 'LD_PRELOAD', 'LD_LIBRARY_PATH']:
        environment.pop(name, None)
    scratch = ROOT / '.build/benchmarks'
    with (ROOT / '.build/dispatcher-benchmark-build.log').open('w') as log:
        subprocess.run([str(swift), 'build', '--scratch-path', str(scratch), '-c', 'release', '--product', 'WaylandBenchmarks',
                        '-Xswiftc', '-warnings-as-errors'], cwd=ROOT, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True)
    directory = Path(subprocess.check_output([str(swift), 'build', '--scratch-path', str(scratch), '-c', 'release', '--show-bin-path'],
                                            cwd=ROOT, env=environment, text=True).strip())
    allowed = os.sched_getaffinity(0)
    selected = min(allowed)
    try:
        os.sched_setaffinity(0, {selected})
        report = json.loads(subprocess.check_output([str(directory / 'WaylandBenchmarks')], cwd=ROOT, env=environment, text=True))
    finally:
        os.sched_setaffinity(0, allowed)
    report['cpuAffinity'] = [selected]
    report['cpuModel'] = next(line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name'))
    report['kernel'] = platform.release()
    report['architecture'] = platform.machine()
    report['compiler'] = subprocess.check_output([str(swift), '--version'], text=True).strip()
    report['nativeVersions'] = {name: subprocess.check_output(['pkg-config', '--modversion', name], text=True).strip() for name in ['wayland-client', 'wayland-server']}
    inputs = [*sorted((ROOT / 'Sources').rglob('*.swift')), *sorted((ROOT / 'Sources').rglob('*.c')),
              *sorted((ROOT / 'Sources').rglob('*.h')), ROOT / 'Benchmarks/Dispatcher.swift',
              ROOT / 'Tests/RuntimeNativeTestSupport/RuntimeNativeTestSupport.c', Path(__file__)]
    report['sourceHashes'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    randomizer = random.Random(0)
    native = report['nativeSeconds']
    swift_samples = report['swiftSeconds']
    bootstrap = []
    for _ in range(10000):
        indices = [randomizer.randrange(len(native)) for _ in native]
        bootstrap.append(1 - statistics.median(native[index] for index in indices) / statistics.median(swift_samples[index] for index in indices))
    bootstrap.sort()
    report['exploratoryLossBootstrap95Percent'] = [bootstrap[249], bootstrap[9749]]
    report['comparisonLimit'] = 'The generic Swift observer copies dynamic metadata; the C reference counts scalar callbacks. This is not the equivalent generated typed-path acceptance benchmark.'
    output = ROOT / 'docs/reference/dispatcher-benchmark.json'
    output.write_text(json.dumps(report, indent=2) + '\n')
    print('Recorded', output)
    print('Native events/s:', round(report['nativeMedianEventsPerSecond']))
    print('Swift events/s:', round(report['swiftMedianEventsPerSecond']))
    print('Exploratory throughput loss:', round(report['swiftThroughputLossFraction'] * 100, 2), 'percent')

if __name__ == '__main__':
    main()
