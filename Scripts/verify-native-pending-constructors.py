#!/usr/bin/env python3
"""Compare pinned native queued-proxy leaks with an isolated repair candidate."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / '.build/native-pending'
PATCH = ROOT / 'Patches/libwayland-1.26.0-pending-proxy-ownership.patch'
ARCHIVE = ROOT / '.build/native-source/wayland-1.26.0.tar.gz'
ARCHIVE_HASH = '56b3a985cbfe17a926e3bcf037e4d374f44eaa33f3a4b364549dddf0d324cebc'


def run(command, log, environment=None):
    with log.open('w') as stream:
        return subprocess.run(command, cwd=ROOT, env=environment, stdout=stream,
                              stderr=subprocess.STDOUT, check=False).returncode


def exported_symbols(library):
    result = subprocess.run(['nm', '-D', '--defined-only', str(library)],
                            cwd=ROOT, text=True, capture_output=True, check=True)
    return sorted(line.split()[-1] for line in result.stdout.splitlines() if line.split())


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    report = {'passed': False, 'nativeBaselineLeakFree': False, 'candidateLeakFree': False,
              'archiveSha256': ARCHIVE_HASH, 'patchSha256': hashlib.sha256(PATCH.read_bytes()).hexdigest(),
              'cases': []}
    report_path = OUTPUT / 'report.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    clean = os.environ.copy()
    for name in ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'LD_DEBUG', 'CC', 'CFLAGS', 'LDFLAGS'):
        clean.pop(name, None)
    for variant in ('original', 'candidate'):
        command = [sys.executable, str(ROOT / 'Scripts/build-instrumented-native.py'),
                   '--sanitizer', 'address']
        if variant == 'candidate':
            command.append('--pending-constructor-fix')
        log = OUTPUT / f'{variant}-build.log'
        if run(command, log, clean):
            raise RuntimeError(f'{variant} isolated native build failed: {log}')
    if hashlib.sha256(ARCHIVE.read_bytes()).hexdigest() != ARCHIVE_HASH:
        raise RuntimeError('Pinned archive changed after native build.')
    original = ROOT / '.build/native-address-install/lib/libwayland-client.so.0'
    candidate = ROOT / '.build/native-address-pending-install/lib/libwayland-client.so.0'
    if exported_symbols(original) != exported_symbols(candidate):
        raise RuntimeError('Candidate changed the exported native client symbol set.')
    report['exportedSymbolsEqual'] = True
    upstream_build = ROOT / '.build/native-pending-upstream-tests'
    upstream_source = ROOT / '.build/native-pending-source/wayland-1.26.0'
    setup = ['meson', 'setup', str(upstream_build), str(upstream_source),
             '-Dtests=true', '-Dscanner=true', '-Ddocumentation=false',
             '-Ddtd_validation=false', '-Db_sanitize=none']
    if (upstream_build / 'meson-private/coredata.dat').exists():
        setup.append('--reconfigure')
    for name, command in (
        ('upstream-setup', setup),
        ('upstream-build', ['meson', 'compile', '-C', str(upstream_build)]),
        ('upstream-tests', ['meson', 'test', '-C', str(upstream_build), '--print-errorlogs']),
    ):
        log = OUTPUT / (name + '.log')
        if run(command, log, clean):
            raise RuntimeError(f'Candidate upstream regression check failed: {log}')
    upstream_results = [json.loads(line) for line in
                        (upstream_build / 'meson-logs/testlog.json').read_text().splitlines() if line]
    if len(upstream_results) != 26 or any(result['result'] != 'OK' for result in upstream_results):
        raise RuntimeError('Expected all 26 pinned upstream tests to pass without skips.')
    report['upstreamRegression'] = {
        'passed': True, 'sanitizer': 'none',
        'tests': [{key: result[key] for key in ('name', 'result', 'returncode')}
                  for result in upstream_results],
        'log': str((OUTPUT / 'upstream-tests.log').relative_to(ROOT)),
    }
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    executable = OUTPUT / 'reproduce'
    command = ['clang', '-std=c11', '-D_GNU_SOURCE', '-g', '-O1', '-Wall', '-Wextra',
               '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
               '-I', str(ROOT / 'Tests/RuntimeNativeTestSupport/include'),
               str(ROOT / 'Tests/NativePendingConstructors/Main.c'),
               str(ROOT / 'Tests/RuntimeNativeTestSupport/ProtocolClientPeer.c'),
               '-lwayland-client', '-lwayland-server', '-o', str(executable)]
    compile_log = OUTPUT / 'compile.log'
    if run(command, compile_log, clean):
        raise RuntimeError(f'Native fixture compilation failed: {compile_log}')
    for variant, library in (('original', original), ('candidate', candidate)):
        directory = OUTPUT / f'{variant}-client-library'
        directory.mkdir(exist_ok=True)
        link = directory / 'libwayland-client.so.0'
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(library.resolve())
        if link.resolve() != library.resolve():
            raise RuntimeError('Isolated loader link points at a different native library.')
        for mode in range(4):
            environment = clean.copy()
            environment['LD_LIBRARY_PATH'] = str(directory)
            environment['LD_DEBUG'] = 'libs'
            environment['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1:abort_on_error=0:exitcode=23'
            environment['LSAN_OPTIONS'] = 'exitcode=23'
            environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
            log = OUTPUT / f'{variant}-{mode}.log'
            returncode = run([str(executable), str(mode)], log, environment)
            contents = log.read_text(errors='replace')
            loaded = any('calling init: ' + str(link) in line
                         for line in contents.splitlines())
            leaked = 'ERROR: LeakSanitizer: detected memory leaks' in contents
            expected = (returncode == 23 and leaked) if variant == 'original' else returncode == 0
            report['cases'].append({'variant': variant, 'mode': mode, 'returncode': returncode,
                                    'loaderVerified': loaded, 'leakDetected': leaked,
                                    'expectedResult': expected, 'log': str(log.relative_to(ROOT))})
            report_path.write_text(json.dumps(report, indent=2) + '\n')
            if not loaded or not expected:
                raise RuntimeError(f'Unexpected native queued-proxy result: {log}')
            print(variant, mode, 'baseline leak' if leaked else 'candidate clean', flush=True)
    report['candidateLeakFree'] = True
    report['passed'] = True
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print('Candidate reproduced and repaired all four isolated cases; native baseline remains leaking.')


if __name__ == '__main__':
    main()
