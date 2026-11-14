#!/usr/bin/env python3
"""Inject allocation failures into production bridge objects without altering the native allocator."""
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
specification = importlib.util.spec_from_file_location('toolchain', ROOT / 'Scripts/verify-toolchain.py')
toolchain = importlib.util.module_from_spec(specification)
specification.loader.exec_module(toolchain)
compiler = Path(toolchain.compiler_path(None)).with_name('clang')
output = ROOT / '.build/bridge-allocation-faults'
output.mkdir(parents=True, exist_ok=True)
sources = ['Sources/CWaylandProtocol/Arguments.c', 'Sources/CWaylandServer/Lifetime.c',
           'Sources/CWaylandUtilities/ByteArray.c', 'Sources/CWaylandProtocol/Descriptors.c',
           'Sources/CWaylandRuntime/Synchronization.c']
fixture = ROOT / 'Tests/BridgeAllocationFaults/Main.c'
inputs = [ROOT / path for path in sources] + [fixture, Path(__file__)]
inputs += [path for module in ['CWaylandProtocol','CWaylandServer','CWaylandRuntime','CWaylandUtilities'] for path in (ROOT/'Sources'/module/'include').rglob('*.h')]
hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
flags = ['-std=c11', '-g', '-O1', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
         '-fno-omit-frame-pointer']
flags += ['-I' + str(ROOT / ('Sources/' + module + '/include'))
          for module in ['CWaylandProtocol', 'CWaylandServer', 'CWaylandRuntime', 'CWaylandUtilities']]
objects = []
for source in sources:
    target = output / (Path(source).stem + '.o')
    substitutions = ['-Dpthread_mutex_init=runtime_fault_pthread_mutex_init'] if source.endswith('/Synchronization.c') else []
    subprocess.run([str(compiler), *flags, *substitutions, '-Dmalloc=runtime_fault_malloc', '-Dcalloc=runtime_fault_calloc',
                    '-Dfree=runtime_fault_free', '-c', str(ROOT / source), '-o', str(target)], check=True)
    objects.append(str(target))
binary = output / 'bridge-allocation-faults'
subprocess.run([str(compiler), *flags, str(fixture), *objects, '-lwayland-server', '-o', str(binary)], check=True)
environment = os.environ.copy()
for name in ['LD_PRELOAD', 'LSAN_OPTIONS']: environment.pop(name, None)
environment['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1'
environment['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
result = subprocess.run([str(binary)], env=environment, capture_output=True, text=True)
(output / 'run.log').write_text(result.stdout + result.stderr)
if result.returncode:
    print(result.stdout + result.stderr, flush=True)
    raise RuntimeError('Bridge allocation fault validation failed; inspect ' + str(output / 'run.log'))
if hashes != {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}:
    raise RuntimeError('Bridge fault inputs changed during validation.')
(output / 'report.json').write_text(json.dumps({'passed': True, 'injectedFailures': int(re.search(r'PASS: (\d+)', result.stdout)[1]), 'inputs': hashes,
    'scope': 'Production bridge allocations and pthread mutex initialization; native libwayland and Swift fatal allocation policy is unchanged.'}, indent=2) + '\n')
print(result.stdout, end='')
