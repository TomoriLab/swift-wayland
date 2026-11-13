#!/usr/bin/env python3
"""Check concrete client ownership against the actual runtime and client modules."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
specification = importlib.util.spec_from_file_location('toolchain', ROOT / 'Scripts/verify-toolchain.py')
toolchain = importlib.util.module_from_spec(specification)
specification.loader.exec_module(toolchain)

def main():
    compiler = toolchain.compiler_path(None)
    output = ROOT / '.build/client-compiler'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'report.json').write_text(json.dumps({'passed': False, 'status': 'building'}) + '\n')
    environment = os.environ.copy()
    for name in ['CC', 'CXX', 'CPP', 'LD', 'AR', 'NM', 'RANLIB', 'STRIP']: environment.pop(name, None)
    (output / 'module.modulemap').write_text('\n'.join('module ' + name + ' { header ' + json.dumps(str(ROOT / 'Sources' / name / 'include' / (name + '.h'))) + ' export * }' for name in ['CWaylandRuntime', 'CWaylandClient']) + '\n')
    fixtures = ROOT / 'Tests/ClientCompileChecks'
    patterns = {'Accepted': None, 'CopyRead': "'copy' cannot be applied to noncopyable types",
                'EscapeRead': 'borrowed|borrowing', 'SendConnection': "non-Sendable type 'ClientConnection'"}
    assert {path.stem for path in fixtures.glob('*.swift')} == patterns.keys()
    inputs = [Path(__file__), ROOT / 'Scripts/verify-toolchain.py', *(ROOT / 'Sources').rglob('*.swift'),
              *(ROOT / 'Sources').rglob('*.h'), *(ROOT / 'Sources').rglob('*.c'), *fixtures.glob('*.swift')]
    hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    report = {'inputs': hashes, 'results': []}
    for configuration, optimization in [('debug', '-Onone'), ('release', '-O')]:
        directory = output / configuration
        directory.mkdir(exist_ok=True)
        flags = [*toolchain.COMMON_FLAGS, optimization, '-package-name', 'swift_wayland', '-I', output, '-I', directory]
        for module in ['WaylandRuntime', 'WaylandClient']:
            compilation = toolchain.invoke([compiler, *flags, '-emit-module', '-module-name', module,
                *sorted((ROOT / 'Sources' / module).glob('*.swift')), '-o', directory / (module + '.swiftmodule')], environment)
            toolchain.require_success(compilation)
        for name, pattern in patterns.items():
            compilation = toolchain.invoke([compiler, *flags, '-c', fixtures / (name + '.swift'), '-o', directory / (name + '.o')], environment)
            passed = compilation['returncode'] == 0 if pattern is None else (
                compilation['returncode'] == 1 and re.search(pattern, compilation['stderr']) is not None
                and 'error:' in compilation['stderr'] and 'Stack dump:' not in compilation['stderr'])
            report['results'].append({'id': name, 'configuration': configuration, 'passed': passed, 'compile': compilation})
            print(('PASS' if passed else 'FAIL'), configuration, name)
            if not passed: print(compilation['stderr'])
    assert hashes == {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    report['passed'] = all(result['passed'] for result in report['results'])
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
