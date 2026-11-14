#!/usr/bin/env python3
"""Run the pinned x86_64 validation matrix and preserve each command's separate evidence."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
ROOT=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--native-sanitizers',action='store_true')
parser.add_argument('--soak',action='store_true')
parser.add_argument('--benchmark',action='store_true')
arguments=parser.parse_args()
specification=importlib.util.spec_from_file_location('toolchain',ROOT/'Scripts/verify-toolchain.py')
toolchain=importlib.util.module_from_spec(specification);specification.loader.exec_module(toolchain)
swift=Path(toolchain.compiler_path(None)).with_name('swift')
output=ROOT/'.build/validation';output.mkdir(parents=True,exist_ok=True)
report={'architecture':'x86_64','deferred':['aarch64','Human review'],'checks':[],'passed':False}
def input_snapshot():
    paths=[path for folder in ['Sources','Scripts','Tests','Examples','docs','Protocols','Patches']
           for path in (ROOT/folder).rglob('*') if path.is_file() and '.build' not in path.parts and '__pycache__' not in path.parts]
    paths += [ROOT/'Package.swift',ROOT/'AGENTS.md']
    return {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
initial_inputs=input_snapshot()
def write_report(): (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
def run(name,command):
    started=time.monotonic()
    with (output/(name+'.log')).open('w') as log:
        result=subprocess.run([str(value) for value in command],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    report['checks'].append({'name':name,'command':[str(value) for value in command], 'returncode':result.returncode,
                             'seconds':time.monotonic()-started,'log':str((output/(name+'.log')).relative_to(ROOT))})
    write_report()
    if result.returncode:
        print((output/(name+'.log')).read_text(errors='replace'), flush=True)
        raise RuntimeError(name+' failed; inspect '+str(output/(name+'.log')))
    print('PASS',name,flush=True)
run('toolchain-paths',['python3','Tests/Toolchain/test_compiler_path.py'])
run('toolchain',['python3','Scripts/verify-toolchain.py'])
for name in ['generate-protocol','generate-typed-protocol','generate-extension-fixtures','generate-native-interop','generate-native-abi-checks','generate-facade','generate-core-peer-tests','generate-core-server-tests','verify-api-coverage']:
    run(name,['python3','Scripts/'+name+'.py','--check'])
for name in ['verify-protocol','verify-imported-protocols','fuzz-protocol','verify-runtime-ownership','verify-client-ownership','verify-wait-faults','verify-bridge-allocation-faults']:
    run(name,['python3','Scripts/'+name+'.py'])
run('debug',[swift,'test','--disable-xctest','-Xswiftc','-warnings-as-errors'])
run('release',[swift,'test','-c','release','--disable-xctest','-Xswiftc','-warnings-as-errors'])
run('examples',['python3','Scripts/verify-examples.py'])
if arguments.native_sanitizers:
    for sanitizer in ['address','thread']:
        run('native-'+sanitizer,['python3','Scripts/verify-instrumented-runtime.py','--sanitizer',sanitizer])
    run('native-pending-constructors',['python3','Scripts/verify-native-pending-constructors.py'])
    pending=json.loads((ROOT/'.build/native-pending/report.json').read_text())
    report['nativeBaselineLeakFree']=pending['nativeBaselineLeakFree']
    report['nativePendingCandidateLeakFree']=pending['candidateLeakFree']
    run('shm-faults',['python3','Scripts/verify-shm-faults.py'])
if arguments.soak:
    run('soak-build',[swift,'build','-c','release','--product','WaylandLifecycleSoak','-Xswiftc','-warnings-as-errors'])
    directory=Path(subprocess.check_output([str(swift),'build','-c','release','--show-bin-path'],cwd=ROOT,text=True).strip())
    run('soak-10000',[directory/'WaylandLifecycleSoak','10000'])
    if arguments.native_sanitizers: run('soak-address-10000',['python3','Scripts/verify-lifecycle-soak.py','--sanitizer','address'])
run('documentation',['python3','Scripts/build-documentation.py'])
if arguments.benchmark:
    run('typed-benchmark',['python3','Scripts/benchmark-typed.py'])
    benchmark=json.loads((ROOT/'.build/typed-benchmark.json').read_text())
    report['throughputGatePassed']=benchmark['throughputGatePassed']
    report['allocationGatePassed']=benchmark['allocationGatePassed']
    report['performanceCoverage'] = {
        'measured': ['typed scalar socketpair delivery', 'zero-argument typed request throughput, allocation entries, and batch latency', 'fixed-size string request throughput, allocation entries, and batch latency'],
        'missing': ['string payload-size scaling', 'arrays', 'FD passing',
                    'queue coordination', 'SHM access', 'representative compositor performance'],
        'complete': False,
    }
report['commandMatrixPassed']=True
report['passed']=report.get('throughputGatePassed',True) and report.get('allocationGatePassed',True) and report.get('nativeBaselineLeakFree',True) and report.get('performanceCoverage', {}).get('complete', True)
report['releaseGatePassed']=False
report['note']='Validation command completion is distinct from quantitative performance acceptance, deferred architecture verification, and human review.'
if input_snapshot()!=initial_inputs: raise RuntimeError('Validation inputs changed during the matrix; rerun against stable sources.')
report['inputs']=initial_inputs
write_report()
print(json.dumps({'passed':report['passed'],'releaseGatePassed':report['releaseGatePassed'],'checks':len(report['checks'])},indent=2))
if not report['passed']: raise SystemExit('A validation gate failed or required performance coverage is missing; command logs are preserved.')
