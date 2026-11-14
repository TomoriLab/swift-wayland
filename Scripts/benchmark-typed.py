#!/usr/bin/env python3
"""Measure equivalent typed scalar throughput, separate allocation counts, CPU time, and batch latency."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
ROOT=Path(__file__).resolve().parent.parent
def hashes():
    paths=[Path(__file__),ROOT/'Package.swift',*(ROOT/'Protocols').rglob('*'),
           *(ROOT/'Sources').rglob('*'),*(ROOT/'Benchmarks/Typed').rglob('*'),
           *(ROOT/'Tests/RuntimeNativeTestSupport').rglob('*'),*(ROOT/'Tests/AllocationProbe').rglob('*')]
    return {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths if path.is_file()}
inputs=hashes()
specification=importlib.util.spec_from_file_location('toolchain',ROOT/'Scripts/verify-toolchain.py')
toolchain=importlib.util.module_from_spec(specification);specification.loader.exec_module(toolchain)
swift=Path(toolchain.compiler_path(None)).with_name('swift')
environment=os.environ.copy()
for name in ['LD_PRELOAD','LD_LIBRARY_PATH','CC','CXX','CPP','LD','AR','NM','RANLIB','STRIP']:environment.pop(name,None)
with (ROOT/'.build/phase7-benchmark-build.log').open('w') as output:
    subprocess.run([str(swift),'build','-c','release','--product','WaylandTypedBenchmarks','-Xswiftc','-warnings-as-errors'],
                   cwd=ROOT,env=environment,stdout=output,stderr=subprocess.STDOUT,check=True)
directory=Path(subprocess.check_output([str(swift),'build','-c','release','--show-bin-path'],cwd=ROOT,env=environment,text=True).strip())
probe=ROOT/'.build/typed-allocation-counter.so'
subprocess.run(['cc','-shared','-fPIC','-O2',str(ROOT/'Tests/AllocationProbe/AllocationCounter.c'),'-o',str(probe)],check=True)
allowed=os.sched_getaffinity(0);selected=min(allowed)
try:
    os.sched_setaffinity(0,{selected})
    throughput_reports=[json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks')],cwd=ROOT,env=environment,text=True)) for _ in range(3)]
    process_losses=[[sample['throughputLoss'] for sample in item['samples']] for item in throughput_reports]
    report=throughput_reports[0]
    for additional in throughput_reports[1:]:
        for sample, extra in zip(report['samples'],additional['samples'],strict=True):
            for key,value in extra.items():
                if isinstance(value,list):sample[key].extend(value)
    for index,sample in enumerate(report['samples']):
        sample['throughputLoss']=1-statistics.median(sample['nativeSeconds'])/statistics.median(sample['swiftSeconds'])
        sample['processThroughputLosses']=[losses[index] for losses in process_losses]
    instrumented=environment.copy();instrumented['LD_PRELOAD']=str(probe)
    allocations=json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks')],cwd=ROOT,env=instrumented,text=True))
    latency=json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks'),'10000','--latency'],cwd=ROOT,env=environment,text=True))
    phases=json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks'),'20000','--phases'],cwd=ROOT,env=environment,text=True))
    callback_isolation=json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks'),'200000','--callback-isolation'],cwd=ROOT,env=environment,text=True))
    read_isolation=json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks'),'200000','--read-isolation'],cwd=ROOT,env=environment,text=True))
    ownership_isolation=json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks'),'20000','--ownership-isolation'],cwd=ROOT,env=environment,text=True))
    request_reports=[json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks'),'--requests'],cwd=ROOT,env=environment,text=True)) for _ in range(3)]
    request_allocations=json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks'),'--requests'],cwd=ROOT,env=instrumented,text=True))
    request_latency=json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks'),'--request-latency'],cwd=ROOT,env=environment,text=True))
    string_reports=[json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks'),'--string-requests'],cwd=ROOT,env=environment,text=True)) for _ in range(3)]
    string_latency=json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks'),'--string-request-latency'],cwd=ROOT,env=environment,text=True))
    string_allocations=json.loads(subprocess.check_output([str(directory/'WaylandTypedBenchmarks'),'--string-requests'],cwd=ROOT,env=instrumented,text=True))
finally:os.sched_setaffinity(0,allowed)
randomizer=random.Random(0x5741594c)
def percentile(values,fraction):
    ordered=sorted(values)
    return ordered[min(len(ordered)-1,int((len(ordered)-1)*fraction))]
def add_paired_interval(sample):
    paired=list(zip(sample['nativeSeconds'],sample['swiftSeconds'],strict=True));bootstrap=[]
    for _ in range(2000):
        values=randomizer.choices(paired,k=len(paired))
        bootstrap.append(1-statistics.median(item[0] for item in values)/statistics.median(item[1] for item in values))
    sample['pairedBootstrapThroughputLossCI95']=[percentile(bootstrap,.025),percentile(bootstrap,.975)]
for sample,allocation,timings,phase in zip(report['samples'],allocations['samples'],latency['samples'],phases['samples'],strict=True):
    sample.pop('nativeAllocations');sample.pop('swiftAllocations')
    sample.pop('nativeBatchLatenciesNanoseconds');sample.pop('swiftBatchLatenciesNanoseconds')
    sample.pop('nativePhaseNanoseconds');sample.pop('swiftPhaseNanoseconds')
    sample['diagnosticPhaseNanoseconds']={'native':dict(zip(['send','prepareAndRead','dispatch'],phase['nativePhaseNanoseconds'],strict=True)),
                                          'swift':dict(zip(['send','prepareAndRead','dispatch'],phase['swiftPhaseNanoseconds'],strict=True))}
    sample['allocationProbe']={key:allocation[key] for key in ['nativeAllocations','swiftAllocations']}
    sample['additionalAllocationEntriesPerEvent']=(statistics.median(allocation['swiftAllocations'])-statistics.median(allocation['nativeAllocations']))/sample['iterations']
    add_paired_interval(sample)
    sample['batchLatencyNanoseconds']={side:{'count':len(timings[side+'BatchLatenciesNanoseconds']),
            'p50':percentile(timings[side+'BatchLatenciesNanoseconds'],.50),
            'p95':percentile(timings[side+'BatchLatenciesNanoseconds'],.95),
            'p99':percentile(timings[side+'BatchLatenciesNanoseconds'],.99)} for side in ['native','swift']}
report['architecture']=platform.machine();report['cpuAffinity']=[selected]
report['throughputProcessRuns']=3
report['callbackIsolation']=callback_isolation
report['rawSwiftReadIsolation']=read_isolation
report['ownershipIsolation']=ownership_isolation
report['cpuModel']=next(line.split(':',1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name'))
report['compiler']=subprocess.check_output([str(swift),'--version'],text=True).strip()
report['nativeVersions']={name:subprocess.check_output(['pkg-config','--modversion',name],text=True).strip() for name in ['wayland-client','wayland-server']}
report['inputs']=inputs
def aggregate_requests(reports):
    samples=[]
    for index in range(2):
        process_samples=[item['samples'][index] for item in reports]
        native=[value for item in process_samples for value in item['nativeSeconds']]
        swift_samples=[value for item in process_samples for value in item['swiftSeconds']]
        samples.append({'batch':process_samples[0]['batch'], 'iterations':process_samples[0]['iterations'],
                                'nativeSeconds':native, 'swiftSeconds':swift_samples,
                                'processThroughputLosses':[item['throughputLoss'] for item in process_samples],
                                'throughputLoss':1-statistics.median(native)/statistics.median(swift_samples)})
    return samples
request_samples=aggregate_requests(request_reports)
string_samples=aggregate_requests(string_reports)
report['requestSamples']=request_samples
for sample, timing in zip(request_samples, request_latency['samples'], strict=True):
    add_paired_interval(sample)
    sample['batchLatencyNanoseconds']={side:{'count':len(timing[side]),
        'p50':percentile(timing[side],.50), 'p95':percentile(timing[side],.95),
        'p99':percentile(timing[side],.99)} for side in ['native','swift']}
report['requestLatencyMeasurement']='Separate clock-instrumented 20000-request pass per batch size. Quantiles cover batch marshal, flush, and peer dispatch; they are not per-request or compositor presentation latency. The final batch may be partial.'
report['requestAllocationMeasurement']='Separate LD_PRELOAD glibc allocation-entry pass after one-request warmup. Both peers include client marshal, flush, and server dispatch. Equal counts establish no additional observed entries for this zero-argument request, not absence of native allocations or universal Swift allocator coverage.'
for sample, allocation in zip(request_samples, request_allocations['samples'], strict=True):
    if not allocation['allocationCounterAvailable']:
        raise RuntimeError('Request allocation probe was not loaded.')
    sample['allocationProbe']={key:allocation[key] for key in ['nativeAllocations','swiftAllocations']}
    sample['additionalAllocationEntriesPerRequest']=(statistics.median(allocation['swiftAllocations'])-statistics.median(allocation['nativeAllocations']))/sample['iterations']
report['stringRequestSamples']=string_samples
for sample, allocation, timing in zip(string_samples, string_allocations['samples'], string_latency['samples'], strict=True):
    sample['batchLatencyNanoseconds']={side:{'count':len(timing[side]),
        'p50':percentile(timing[side],.50), 'p95':percentile(timing[side],.95),
        'p99':percentile(timing[side],.99)} for side in ['native','swift']}
    add_paired_interval(sample)
    if not allocation['allocationCounterAvailable']: raise RuntimeError('String allocation probe was not loaded.')
    sample['allocationProbe']={key:allocation[key] for key in ['nativeAllocations','swiftAllocations']}
    sample['additionalAllocationEntriesPerRequest']=(statistics.median(allocation['swiftAllocations'])-statistics.median(allocation['nativeAllocations']))/sample['iterations']
report['stringRequestMeasurement']='Three pinned-CPU processes with nine alternating pairs send wl_data_source.offer with the same 15-byte string plus its terminating NUL. Both peers verify string contents and request count. Setup, one-request warmup, and teardown are excluded. Allocation entries are measured in a separate intercepted pass. A separate clock-instrumented 20000-request pass records batch marshal, flush, and peer dispatch p50/p95/p99; the final batch may be partial. This does not cover arbitrary string sizes, arrays, or compositor presentation latency.'
report['requestMeasurement']='Three pinned-CPU processes each run nine alternating C/Swift pairs of wl_surface.commit requests. Both peers flush and dispatch after each batch and verify the exact request count. Setup, one-request warmup, and teardown are excluded. This covers a zero-argument request, not payload, FD, or constructor costs.'
report['scalarThroughputGatePassed']=all(sample['throughputLoss']<=.10 and all(loss<=.10 for loss in sample['processThroughputLosses']) for sample in report['samples'])
report['requestThroughputGatePassed']=all(sample['throughputLoss']<=.10 and all(loss<=.10 for loss in sample['processThroughputLosses']) for sample in request_samples)
report['stringThroughputGatePassed']=all(sample['throughputLoss']<=.10 and all(loss<=.10 for loss in sample['processThroughputLosses']) for sample in string_samples)
report['throughputGatePassed']=report['scalarThroughputGatePassed'] and report['requestThroughputGatePassed'] and report['stringThroughputGatePassed']
report['allocationGatePassed']=all(sample['additionalAllocationEntriesPerEvent']==0 for sample in report['samples'])
report['allocationMeasurement']='Separate thread-local glibc allocation-entry pass after warmup. Native counts are explicit; equal counts are evidence of no additional allocation entries, not a universal proof of Swift allocator coverage.'
report['latencyMeasurement']='Separate clock-instrumented pass, one sample of 10000 events per batch size. Quantiles describe send/read/dispatch batch duration through the combined Swift call, not compositor presentation latency.'
report['diagnosticPhaseMeasurement']='Separate clock-instrumented pass through the legacy separate read and dispatch Swift calls. Phase totals localize overhead but do not describe the combined throughput path.'
report['callbackIsolationMeasurement']='Nine alternating pairs compare the same native C socketpair, setup, event, read, and dispatch work with C and raw Swift callbacks. This omits WaylandKit ownership and typed decoding; it isolates the language callback boundary and does not replace the typed throughput gate.'
report['rawSwiftReadIsolationMeasurement']='Nine alternating pairs compare C read/dispatch calls with a raw Swift C-ABI function that invokes the same native read/dispatch operations. Both use the same raw Swift scalar callback and native setup. This omits WaylandKit ownership and measures the additional Swift-to-C call path, but adds one C-to-Swift entry per batch.'
report['ownershipIsolationMeasurement']='Nine alternating pairs compare the C baseline with a WaylandKit proxy whose delivery subscription is canceled after warmup. Mandatory callback admission and protocol-owned argument disposal remain active; generated typed decoding and user delivery do not run. The canceled path performs different handler work and is diagnostic only.'
report['confidenceInterval']='Empirical paired bootstrap of twenty-seven alternating throughput samples across three processes. Within-process samples are correlated; report each process loss separately before interpreting this interval.'
report['teardownMeasurement']='C destroys proxies/display/server. Swift times root native closure and server destruction while invalidated Swift value handles may remain in scope; residual ARC destruction is not included.'
report['copiedPayloadBytesPerScalarEvent']=0
if inputs!=hashes():raise RuntimeError('Benchmark inputs changed during measurement.')
(ROOT/'.build/typed-benchmark.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'samples':report['samples'],'throughputGatePassed':report['throughputGatePassed'],'allocationGatePassed':report['allocationGatePassed']},indent=2))
