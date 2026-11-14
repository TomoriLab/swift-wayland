#!/usr/bin/env python3
"""Run at least 10000 complete native lifecycles under isolated native instrumentation."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sanitizer',choices=['address','thread'],default='address')
parser.add_argument('--iterations',type=int,default=10000)
arguments=parser.parse_args()
if arguments.iterations<10000:raise ValueError('Acceptance requires at least 10000 iterations.')
specification=importlib.util.spec_from_file_location('toolchain',ROOT/'Scripts/verify-toolchain.py')
toolchain=importlib.util.module_from_spec(specification);specification.loader.exec_module(toolchain)
swift=Path(toolchain.compiler_path(None)).with_name('swift')
output=ROOT/('.build/lifecycle-'+arguments.sanitizer);output.mkdir(parents=True,exist_ok=True)
environment=os.environ.copy()
for name in ['LD_PRELOAD','LD_LIBRARY_PATH','CC','CXX','CPP','LD','AR','NM','RANLIB','STRIP','LSAN_OPTIONS']:environment.pop(name,None)
environment['ASAN_OPTIONS']='detect_leaks=1:halt_on_error=1:exitcode=23'
environment['TSAN_OPTIONS']='halt_on_error=1:exitcode=66'
scratch=ROOT/('.build/soak-'+arguments.sanitizer)
def input_snapshot():
    paths=[path for folder in ['Sources','Tests/LifecycleSoak','Tests/RuntimeNativeTestSupport']
           for path in (ROOT/folder).rglob('*') if path.is_file()]
    paths += [ROOT/'Package.swift',Path(__file__)]
    return {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
initial_inputs=input_snapshot()
with (output/'build.log').open('w') as log:
    subprocess.run([str(swift),'build','--scratch-path',str(scratch),'-c','release','--sanitize',arguments.sanitizer,
                    '--product','WaylandLifecycleSoak','-Xswiftc','-warnings-as-errors'],cwd=ROOT,env=environment,stdout=log,stderr=subprocess.STDOUT,check=True)
directory=Path(subprocess.check_output([str(swift),'build','--scratch-path',str(scratch),'-c','release','--show-bin-path'],cwd=ROOT,env=environment,text=True).strip())
prefix=ROOT/('.build/native-'+arguments.sanitizer+'-install/lib')
results=[]
for variant in (['client','server'] if arguments.sanitizer=='address' else ['both']):
    local=environment.copy();local['LD_DEBUG']='libs'
    libraries=['libwayland-'+name+'.so.0' for name in (['client','server'] if variant=='both' else [variant])]
    libraries+=['libwayland-cursor.so.0','libwayland-egl.so.1']
    if arguments.sanitizer=='address':local['LD_PRELOAD']=':'.join(str(prefix/name) for name in libraries)
    else:local['LD_LIBRARY_PATH']=str(prefix)
    result=subprocess.run([str(directory/'WaylandLifecycleSoak'),str(arguments.iterations)],cwd=ROOT,env=local,capture_output=True,text=True)
    (output/(variant+'.log')).write_text(result.stdout+result.stderr)
    if result.returncode:raise RuntimeError('Instrumented lifecycle failed: '+str(output/(variant+'.log')))
    sample=json.loads(result.stdout)
    if not sample['passed'] or sample['iterations']<10000:raise RuntimeError('Incomplete lifecycle acceptance.')
    if not all('calling init: '+str(prefix/name) in result.stderr for name in libraries):raise RuntimeError('Native loader did not confirm every instrumented library.')
    results.append({'variant':variant,'libraries':libraries,'sample':sample})
    print('PASS',arguments.sanitizer,variant,arguments.iterations,'cycles',flush=True)
if input_snapshot()!=initial_inputs:raise RuntimeError('Lifecycle inputs changed during validation.')
report={'passed':True,'sanitizer':arguments.sanitizer,'results':results,'inputs':initial_inputs}
(output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
