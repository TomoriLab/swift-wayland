#!/usr/bin/env python3
"""Inventory native declarations, macros, and exports without claiming unmapped APIs are implemented."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
HEADERS = ['wayland-client.h', 'wayland-server.h', 'wayland-cursor.h', 'wayland-egl.h', 'wayland-version.h']
KINDS = {'FunctionDecl': 'function', 'TypedefDecl': 'type', 'RecordDecl': 'record',
         'EnumDecl': 'enum', 'EnumConstantDecl': 'enumMember', 'VarDecl': 'data'}
MAPPINGS = {
    'wl_proxy_marshal_array_flags': ('ClientObjectReference', 'TypedProtocol', 'TypedProtocolTests'),
    'wl_resource_set_dispatcher': ('ServerObject.onRequest', 'TypedProtocol', 'TypedServerTests'),
    'wl_resource_post_event_array': ('ServerObjectReference', 'TypedProtocol', 'TypedServerTests'),
    'wl_client_post_implementation_error': ('ServerNewIdentifier', 'TypedProtocol', 'TypedServerTests'),
    'wl_proxy_add_dispatcher': ('ClientProxyDispatcher', 'ProxyDispatcher', 'ProxyDispatcherTests'),
    'wl_proxy_destroy': ('ProxyDispatcherOwner', 'ProxyDispatcher', 'ProxyDispatcherTests'),
    'wl_display_connect': ('ClientConnection', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_connect_to_fd': ('ClientConnection', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_disconnect': ('ClientConnection.requestClose', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_get_registry': ('ClientConnection.registry', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_sync': ('ClientConnection.sync', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_create_queue': ('ClientConnection.createQueue', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_event_queue_destroy': ('ClientEventQueue.close', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_proxy_create_wrapper': ('ClientConnection.sync(on:context:handler:)', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_proxy_wrapper_destroy': ('ClientConnection.sync(on:context:handler:)', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_flush': ('ClientConnection.flush', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_prepare_read': ('ClientConnection.withPreparedRead', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_prepare_read_queue': ('ClientConnection.withPreparedRead(on:_:)', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_read_events': ('ClientReadReservation.read', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_cancel_read': ('ClientReadReservation.cancel', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_dispatch_pending': ('ClientConnection.dispatchPending', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_dispatch_queue_pending': ('ClientConnection.dispatchPending(on:)', 'ClientAndServer', 'ClientConnectionTests'),
    'wl_display_create': ('ServerDisplay', 'ClientAndServer', 'ServerDisplayTests'),
    'wl_display_destroy': ('ServerDisplay.requestClose', 'ClientAndServer', 'ServerDisplayTests'),
    'wl_display_destroy_clients': ('ServerDisplay.requestClose', 'ClientAndServer', 'ServerDisplayTests'),
    'wl_client_create': ('ServerDisplay.createClient', 'ClientAndServer', 'ServerDisplayTests'),
    'wl_client_destroy': ('ServerClient.close', 'ClientAndServer', 'ServerDisplayTests'),
    'wl_resource_create': ('ServerDisplay.createResource', 'ClientAndServer', 'ServerDisplayTests'),
    'wl_resource_destroy': ('ServerResource.close', 'ClientAndServer', 'ServerDisplayTests'),
    'wl_client_add_destroy_listener': ('NativeDestructionObserver', 'ClientAndServer', 'ServerDisplayTests'),
    'wl_resource_add_destroy_listener': ('NativeDestructionObserver', 'ClientAndServer', 'ServerDisplayTests'),
    'wl_event_loop_add_idle': ('ServerDisplay.addIdle', 'ClientAndServer', 'ServerDisplayTests'),
    'wl_event_source_remove': ('ServerIdleSource.close', 'ClientAndServer', 'ServerDisplayTests'),
    'wl_event_loop_dispatch': ('ServerDisplay.dispatch', 'ClientAndServer', 'ServerDisplayTests'),
}

def run(arguments):
    return subprocess.check_output(arguments, text=True)

def protocol_tests(interface, direction, message):
    interface_name = interface['name']
    if interface_name in ['wl_display', 'wl_registry']:
        paths = ['Tests/WaylandRuntimeTests/ClientConnectionTests.swift',
                 'Tests/WaylandRuntimeTests/TypedProtocolTests.swift',
                 'Tests/WaylandRuntimeTests/ServerGlobalTests.swift']
        return {'boundary': 'Native-reserved implementation; independent C peer integration.', 'tests': paths}
    name = ''.join(part[:1].upper() + part[1:] for part in (interface_name + '_' + message['name']).split('_'))
    kind = 'Request' if direction == 'requests' else 'Event'
    tests = []
    for side in ['', 'Server']:
        path = 'Tests/WaylandRuntimeTests/Core' + side + kind + 'WireTests.swift'
        symbol = name + side + kind + 'Wire'
        if 'func ' + symbol + '(' not in (ROOT / path).read_text():
            raise RuntimeError('Missing generated message behavior test: ' + symbol)
        tests.append({'file': path, 'test': symbol})
    return {'boundary': 'Independent native C metadata, arguments, and ownership in both directions.', 'tests': tests}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    arguments = parser.parse_args()
    directory = ROOT / '.build/native-inventory'
    directory.mkdir(parents=True, exist_ok=True)
    source = directory / 'headers.c'
    source.write_text(''.join('#include <' + header + '>\n' for header in HEADERS))
    flags = run(['pkg-config', '--cflags', 'wayland-client', 'wayland-server', 'wayland-cursor', 'wayland-egl']).split()
    tree = json.loads(run(['clang', *flags, '-Xclang', '-ast-dump=json', '-fsyntax-only', str(source)]))
    items = {}
    def visit(node, record=None):
        name = node.get('name', '')
        kind = node.get('kind')
        if kind == 'RecordDecl' and name.startswith('wl_'): record = name
        if name.startswith(('wl_', 'WL_', 'WAYLAND_')) and kind in KINDS:
            category = KINDS[kind]
            identity = 'c.' + category + '.' + name
            items[identity] = {'id': identity, 'category': category, 'name': name}
        elif kind == 'FieldDecl' and record:
            identity = 'c.field.' + record + '.' + name
            items[identity] = {'id': identity, 'category': 'field', 'name': record + '.' + name}
        for child in node.get('inner', []): visit(child, record)
    visit(tree)
    macros = run(['clang', *flags, '-dM', '-E', str(source)])
    for name, definition in re.findall(r'^#define ((?:wl_|WL_|WAYLAND_)\w+)(.*)$', macros, re.M):
        identity = 'c.macro.' + name
        items[identity] = {'id': identity, 'category': 'macro', 'name': name, 'definition': definition.strip()}
    exports = {}
    for library in ['wayland-client', 'wayland-server', 'wayland-cursor', 'wayland-egl']:
        location = Path(run(['pkg-config', '--variable=libdir', library]).strip()) / ('lib' + library + '.so')
        names = re.findall(r'\b(wl_\w+)$', run(['nm', '-D', '--defined-only', str(location)]), re.M)
        exports[library] = sorted(names)
        for name in names:
            if not any(item['name'] == name for item in items.values()):
                raise RuntimeError('Export absent from the public declaration inventory: ' + name)
    for item in items.values():
        mapping = MAPPINGS.get(item['name']) if item['category'] == 'function' else None
        item['status'] = 'implemented' if mapping else 'unmapped'
        if mapping:
            item['target'], article, test = mapping
            item['documentation'] = 'docs/WaylandKit.docc/' + article + '.md'
            item['tests'] = 'Tests/WaylandRuntimeTests/' + test + '.swift'
    native_manifest = ROOT / 'docs/reference/native-interop-manifest.json'
    compatibility = {mapping['id']: mapping for mapping in json.loads(native_manifest.read_text())['mappings']} if native_manifest.exists() else {}
    for identity, item in items.items():
        if identity not in compatibility:
            continue
        mapping = compatibility[identity]
        item['compatibility'] = mapping
        if item['status'] == 'unmapped':
            item['status'] = mapping['status']
            if mapping['status'] == 'unsafeABI':
                item['documentation'] = mapping['documentation']
                item['verification'] = ['Scripts/generate-native-interop.py --check',
                                        'Scripts/generate-native-abi-checks.py --check',
                                        'Tests/WaylandRuntimeTests/NativeCompatibilityTests.swift',
                                        'Tests/WaylandRuntimeTests/NativeAdapterTests.swift']
    model = json.loads((ROOT / 'docs/reference/core-protocol-manifest.json').read_text())
    for interface in model['interfaces']:
        for direction in ['requests', 'events']:
            for message in interface[direction]:
                identity = 'protocol.' + interface['name'] + '.' + direction + '.' + message['name']
                items[identity] = {'id': identity, 'category': 'protocolMessage', 'name': identity,
                                   'schemaGenerated': True, 'status': 'implemented',
                                   'typedBindingGenerated': True,
                                   'typedManifest': 'docs/reference/typed-core-bindings.json',
                                   'typedDocumentation': 'docs/WaylandKit.docc/TypedProtocol.md',
                                   'typedRuntimeCoverage': protocol_tests(interface, direction, message)}
    ordered = [items[key] for key in sorted(items)]
    counts = {category: sum(item['category'] == category for item in ordered) for category in sorted({item['category'] for item in ordered})}
    implemented = sum(item['status'] == 'implemented' for item in ordered)
    classified = sum(item['status'] != 'unmapped' for item in ordered)
    include_directory = Path(run(['pkg-config', '--variable=includedir', 'wayland-client']).strip())
    header_names = re.findall(r'^## ([a-z-]+\.h)$', (ROOT / 'docs/reference/api-inventory.md').read_text(), re.M)
    header_hashes = {name: hashlib.sha256((include_directory / name).read_bytes()).hexdigest() for name in header_names}
    notices = {name: [comment for comment in re.findall(r'/\*.*?\*/', (include_directory / name).read_text(), re.S)
                      if 'Copyright' in comment and 'Permission' in comment] for name in header_names}
    report = {'licenseNotices': {name: comments for name, comments in notices.items() if comments}, 'headers': header_hashes, 'baseline': {library: run(['pkg-config', '--modversion', library]).strip() for library in exports},
              'protocolHash': model['sha256'], 'categories': counts, 'total': len(ordered), 'implemented': implemented,
              'classified': classified, 'coverageGatePassed': classified == len(ordered),
              'releaseGatePassed': False,
              'remainingReleaseGates': ['Complete automated acceptance matrix', 'Equivalent typed workload performance', 'Rendered documentation review', 'Human review', 'Deferred aarch64 validation'], 'exports': exports, 'items': ordered}
    output = ROOT / 'docs/reference/native-api-coverage.json'
    content = json.dumps(report, indent=2) + '\n'
    if arguments.check:
        if output.read_text() != content: raise RuntimeError('Native coverage output differs.')
    else: output.write_text(content)
    print(json.dumps({key: report[key] for key in ['categories', 'total', 'implemented', 'classified', 'coverageGatePassed', 'releaseGatePassed']}, indent=2))

if __name__ == '__main__':
    main()
