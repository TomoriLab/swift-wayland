#!/usr/bin/env python3
"""Verify wrapper tests against isolated instrumented native libraries without sanitizer exclusions."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sanitizer', choices=['address', 'thread'], required=True)
    arguments = parser.parse_args()
    specification = importlib.util.spec_from_file_location('toolchain', ROOT / 'Scripts/verify-toolchain.py')
    toolchain = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(toolchain)
    swift = Path(toolchain.compiler_path(None)).with_name('swift')
    mode = arguments.sanitizer
    (ROOT / '.build').mkdir(exist_ok=True)
    (ROOT / ('.build/native-' + mode + '-verification.json')).write_text(json.dumps({'passed': False, 'status': 'building'}) + '\n')
    environment = os.environ.copy()
    for name in ['CC', 'CXX', 'CPP', 'LD', 'AR', 'NM', 'RANLIB', 'STRIP', 'LD_PRELOAD', 'LD_LIBRARY_PATH']:
        environment.pop(name, None)
    environment['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1:abort_on_error=0:exitcode=23'
    environment['LSAN_OPTIONS'] = 'exitcode=23'
    environment['TSAN_OPTIONS'] = 'halt_on_error=1:exitcode=66'
    subprocess.run([sys.executable, str(ROOT / 'Scripts/build-instrumented-native.py'), '--sanitizer', mode],
                   cwd=ROOT, env=environment, check=True)
    scratch = ROOT / ('.build/runtime-' + mode)
    command = [str(swift), 'test', '--scratch-path', str(scratch), '--disable-xctest', '--sanitize', mode,
               '-Xswiftc', '-warnings-as-errors']
    # First verify the ordinary system-library configuration and build its exact test runner.
    baseline = ROOT / ('.build/proxy-' + mode + '.log')
    with baseline.open('w') as stream:
        subprocess.run(command, cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT, check=True)
    binary_directory = Path(subprocess.check_output([str(swift), 'build', '--scratch-path', str(scratch), '--show-bin-path'],
                                                  cwd=ROOT, env=environment, text=True).strip())
    runner = binary_directory / 'WaylandRuntimeTests-test-runner'
    prefix = ROOT / ('.build/native-' + mode + '-install/lib')
    results = []
    variants = ['client', 'server'] if mode == 'address' else ['both']
    for variant in variants:
        local = environment.copy()
        if mode == 'address':
            # Both DSOs deliberately export the same protocol globals. Preloading one
            # instrumented DSO at a time preserves native interposition and ODR checks.
            local['LD_PRELOAD'] = str(prefix / ('libwayland-' + variant + '.so.0'))
        else:
            local['LD_LIBRARY_PATH'] = str(prefix)
        local['LD_DEBUG'] = 'libs'
        log = ROOT / ('.build/proxy-native-' + mode + '-' + variant + '.log')
        with log.open('w') as stream:
            result = subprocess.run([str(runner), '--testing-library', 'swift-testing'], cwd=ROOT, env=local,
                                    stdout=stream, stderr=subprocess.STDOUT)
        contents = log.read_text()
        expected = [str(prefix / ('libwayland-' + name + '.so.0')) for name in (['client', 'server'] if variant == 'both' else [variant])]
        if result.returncode != 0 or 'Test run with' not in contents or 'passed after' not in contents:
            raise RuntimeError('Instrumented native test failed; inspect ' + str(log))
        if not all(any('calling init: ' + path in line for line in contents.splitlines()) for path in expected):
            raise RuntimeError('Loader output does not confirm the requested instrumented libraries.')
        results.append({'variant': variant, 'returncode': result.returncode, 'log': str(log.relative_to(ROOT)),
                        'libraries': expected})
        print('PASS', mode, variant, 'with native loader verification')
    (ROOT / ('.build/native-' + mode + '-verification.json')).write_text(json.dumps({'passed': True, 'results': results}, indent=2) + '\n')

if __name__ == '__main__':
    main()
