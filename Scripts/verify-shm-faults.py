#!/usr/bin/env python3
"""Run the production SHM copy bridge against native malformed/truncated peers in an isolated process."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parent.parent
specification=importlib.util.spec_from_file_location('toolchain',ROOT/'Scripts/verify-toolchain.py')
toolchain=importlib.util.module_from_spec(specification);specification.loader.exec_module(toolchain)
compiler=Path(toolchain.compiler_path(None)).with_name('clang')
directory=ROOT/'.build/shm-faults';directory.mkdir(parents=True,exist_ok=True)
binary=directory/'shm-faults'
command=[str(compiler),'-g','-O1','-fsanitize=address,undefined','-fno-omit-frame-pointer','-Wall','-Wextra','-Werror',
         '-I'+str(ROOT/'Tests/RuntimeNativeTestSupport/include'),'-I'+str(ROOT/'Sources/CWaylandServer/include'),
         '-I'+str(ROOT/'Sources/CWaylandRuntime/include'),str(ROOT/'Tests/SharedMemoryFaults/Main.c'),
         str(ROOT/'Tests/RuntimeNativeTestSupport/SharedMemoryClient.c'),str(ROOT/'Sources/CWaylandServer/SharedMemory.c'),
         '-lwayland-client','-lwayland-server','-o',str(binary)]
subprocess.run(command,check=True)
environment=os.environ.copy()
for name in ['LD_PRELOAD','LSAN_OPTIONS']:environment.pop(name,None)
environment['ASAN_OPTIONS']='detect_leaks=1:halt_on_error=1'
environment['UBSAN_OPTIONS']='halt_on_error=1:print_stacktrace=1'
results=[]
for variant in ['system','client','server']:
    local=environment.copy()
    if variant!='system':local['LD_PRELOAD']=str(ROOT/('.build/native-address-install/lib/libwayland-'+variant+'.so.0'))
    result=subprocess.run([str(binary)],env=local,capture_output=True,text=True)
    (directory/(variant+'.log')).write_text(result.stdout+result.stderr)
    if result.returncode or 'PASS SHM ' not in result.stdout:raise RuntimeError('SHM faults failed: '+str(directory/(variant+'.log')))
    results.append({'variant':variant,'passed':True})
report={'results':results,'passed':True,'sanitizers':['address','undefined'],'leakDetection':True}
(directory/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
