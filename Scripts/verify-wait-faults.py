#!/usr/bin/env python3
"""Inject syscall failures into the actual production C wait loop in an isolated executable."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
output = ROOT / '.build/wait-faults'
output.mkdir(parents=True, exist_ok=True)
macros = ['poll=runtime_fault_poll', 'clock_gettime=runtime_fault_clock',
          'wl_display_flush=runtime_fault_flush', 'wl_display_get_fd=runtime_fault_get_fd']
command = ['clang', '-std=c11', '-D_POSIX_C_SOURCE=200809L', '-Wall', '-Wextra', '-Werror',
           '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
           '-I', str(ROOT / 'Sources/CWaylandClient/include'),
           '-I', str(ROOT / 'Sources/CWaylandRuntime/include'), *['-D' + macro for macro in macros],
           '-x', 'c', str(ROOT / 'Sources/CWaylandClient/Proxy.c'),
           str(ROOT / 'Tests/RuntimeNativeTestSupport/WaitFaults.c.fixture'),
           '-lwayland-client', '-o', str(output / 'wait-faults')]
subprocess.run(command, check=True)
result = subprocess.run([str(output / 'wait-faults')], check=True, capture_output=True, text=True)
print(result.stdout, end='')
(output / 'report.json').write_text(json.dumps({'passed': True, 'scenarios': 8, 'stdout': result.stdout,
                                             'command': command}, indent=2) + '\n')
