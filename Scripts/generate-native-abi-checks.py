#!/usr/bin/env python3
"""Generate native ABI layout and constant checks for every explicit compatibility mapping."""
import importlib.util
import argparse
import json
import re
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');arguments=parser.parse_args()
def write_output(path, content):
    if arguments.check:
        if path.read_text()!=content: raise RuntimeError('Generated output differs: '+str(path))
    else: path.write_text(content)
specification = importlib.util.spec_from_file_location('interop_generator', ROOT/'Scripts/generate-native-interop.py')
generator=importlib.util.module_from_spec(specification); specification.loader.exec_module(generator)
manifest=json.loads((ROOT/'docs/reference/native-interop-manifest.json').read_text())
inventory=json.loads((ROOT/'docs/reference/native-api-coverage.json').read_text())
items={item['id']:item for item in inventory['items']}
module_by_target={target:module for family,module,target in generator.FAMILIES}
nodes_by_module={module:generator.ast(module) for module in module_by_target.values()}
cpp=[]; assertions=[]; field_functions=[]; imported={}
# The compiler decides which imported nominal types require unsafe acknowledgement.
# C callback-table records and scalar records are not classified by pointer spelling.
probe_directory=ROOT/'.build/native-interop'
(probe_directory/'module.modulemap').write_text('\n'.join('module '+module+' { header '+json.dumps(str(ROOT/'Sources'/module/'include'/(module+'.h')))+' export * }' for module in module_by_target.values())+'\n')
probe_lines=['import '+module for module in module_by_target.values()]+['private func probe() {']
probe_rows={}
for mapping in manifest['mappings']:
    item=items[mapping['id']]
    if item['category'] not in ['record','enum','type']: continue
    module=module_by_target[mapping['target']]
    node=nodes_by_module[module][(generator.KINDS[item['category']],item['name'])]
    opaque=item['category']=='record' and not node.get('completeDefinition')
    native_type='OpaquePointer' if opaque else module+'.'+item['name']
    probe_rows[len(probe_lines)+1]=item['id']
    probe_lines.append('    _ = MemoryLayout<'+native_type+'>.size')
probe_lines.append('}')
probe=probe_directory/'TypeSafetyProbe.swift';probe.write_text('\n'.join(probe_lines)+'\n')
toolchain_specification = importlib.util.spec_from_file_location('toolchain', ROOT/'Scripts/verify-toolchain.py')
toolchain = importlib.util.module_from_spec(toolchain_specification)
toolchain_specification.loader.exec_module(toolchain)
compiler = toolchain.compiler_path(None)
result=subprocess.run([str(compiler),'-swift-version','6','-strict-memory-safety','-warnings-as-errors','-parse-as-library',
                       '-I',str(probe_directory),'-Xcc','-I'+str(ROOT/'Sources/CWaylandRuntime/include'),'-emit-module','-module-name','NativeTypeSafetyProbe',str(probe),
                       '-o',str(probe_directory/'NativeTypeSafetyProbe.swiftmodule')],capture_output=True,text=True)
if result.returncode not in [0, 1] or (result.returncode and ": error:" not in result.stderr):
    raise RuntimeError("Native type probe failed without expected compiler diagnostics: " + result.stderr)
unsafe_types=set()
for line in result.stderr.splitlines():
    if ': error:' not in line: continue
    match=re.search(r'TypeSafetyProbe.swift:(\d+):\d+: error:',line)
    if not match:
        if line.startswith('error: emit-module command failed'): continue
        raise RuntimeError(result.stderr)
    if "not marked with 'unsafe'" not in line: raise RuntimeError(result.stderr)
    unsafe_types.add(probe_rows[int(match.group(1))])
(probe_directory/'type-safety-report.json').write_text(json.dumps({'compiler':str(compiler),'unsafeTypes':sorted(unsafe_types),'diagnostics':result.stderr},indent=2)+'\n')


def add(c_expression, swift_expression, label):
    index=len(cpp)
    cpp.append('    case '+str(index)+': return (uint64_t)('+c_expression+');')
    assertions.append('        #expect('+swift_expression+' == runtime_native_abi_value('+str(index)+'), "'+label+'")')

for mapping in manifest['mappings']:
    item=items[mapping['id']];category=item['category'];name=item['name']
    if mapping['status']!='unsafeABI':continue
    target=mapping['target'];module=module_by_target[target];symbol=mapping['symbol']
    if category in ['record','enum','type']:
        node=nodes_by_module[module][(generator.KINDS[category],name)]
        opaque=category=='record' and not node.get('completeDefinition')
        c_type=('union ' if node.get('tagUsed')=='union' else 'struct ')+name if category=='record' else ('enum '+name if category=='enum' else name)
        if opaque:c_type+=' *'
        marker = 'unsafe ' if item['id'] in unsafe_types else ''
        add('sizeof('+c_type+')', marker+'UInt64(MemoryLayout<'+symbol+'>.size)',name+' size')
        add('_Alignof('+c_type+')', marker+'UInt64(MemoryLayout<'+symbol+'>.alignment)',name+' alignment')
    elif category=='field':
        record,field=name.split('.',1)
        parent=next(m for m in manifest['mappings'] if m['id']=='c.record.'+record)
        node=nodes_by_module[module][('RecordDecl',record)]
        c_type=('union ' if node.get('tagUsed')=='union' else 'struct ')+record
        field_node = next(child for child in node.get('inner',[]) if child.get('kind') == 'FieldDecl' and child.get('name') == field)
        field_unsafe = 'c.record.'+record in unsafe_types or any('*' in spelling for spelling in field_node.get('type',{}).values())
        if record!='wl_argument':
            add('offsetof('+c_type+', '+field+')', ('unsafe ' if field_unsafe else '')+'MemoryLayout<'+parent['symbol']+'>.offset(of: \\.'+field+').map(UInt64.init)', name+' offset')
        imported.setdefault((module,parent['symbol']),[]).append(field)
    elif category=='enumMember':
        node = nodes_by_module[module][('EnumConstantDecl',name)]
        add('(uint32_t)'+name,'unsafe UInt64('+symbol+('.rawValue' if node.get('parentEnumeration') else '')+')',name)
    elif category=='macro' and not name.startswith('wl_'):
        if name=='WAYLAND_VERSION':continue
        add(name, 'unsafe UInt64('+symbol+')',name)
    elif category=='data':
        add('(uintptr_t)&'+name, 'unsafe UInt64(UInt(bitPattern: '+symbol+'))',name+' identity')

for (module,symbol),fields in imported.items():
    function='check_'+symbol.replace('.','_')
    field_functions += ['@unsafe private func '+function+'(_ pointer: UnsafePointer<'+symbol+'>) {']
    field_functions += ['    _ = unsafe pointer.pointee.'+field for field in fields]
    field_functions += ['}']

c_source='''/* Generated by Scripts/generate-native-abi-checks.py. */
#include <stddef.h>
#include <stdint.h>
#include <wayland-client.h>
#include <wayland-server.h>
#include <wayland-cursor.h>
#include <wayland-egl.h>
#include <wayland-version.h>
uint64_t runtime_native_abi_value(unsigned index)
{
    switch (index) {
'''+ '\n'.join(cpp)+'''
    default: return UINT64_MAX;
    }
}
'''
test_functions=[]
for start in range(0,len(assertions),64):
    test_functions += ['    @Test func explicitNativeCompatibilityMatchesCGroup' + str(start//64) + '() {',
                       *assertions[start:start+64], '    }']
swift_source="""// Generated by Scripts/generate-native-abi-checks.py. Do not edit.
import Testing
import RuntimeNativeTestSupport
import WaylandClient
import WaylandServer
import WaylandUtilities
import WaylandCursor
import WaylandEGL

extension DescriptorAndCallbackTests {
"""+ '\n'.join(test_functions)+"""
    @Test func explicitNativeCompatibilityPreservesVersionString() {
        #expect(unsafe UtilitiesInterop.WAYLAND_VERSION == "1.26.0")
    }
}

"""+ '\n'.join(field_functions)+'\n'
outputs={'Tests/RuntimeNativeTestSupport/NativeABI.c':c_source,'Tests/WaylandRuntimeTests/NativeCompatibilityTests.swift':swift_source}
for name,content in outputs.items():write_output(ROOT/name, content)
(ROOT/'.build/native-interop/abi-count.json').write_text(json.dumps({'comparisons':len(cpp),'fieldChecks':sum(map(len,imported.values()))})+'\n')
print('Verified' if arguments.check else 'Generated',len(cpp),'native layout/constant comparisons and',sum(map(len,imported.values())),'field compiler checks.')
