#!/usr/bin/env python3
"""Generate pinned xdg-shell imports and consume the sealed metadata from a separate Swift package."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import shutil

ROOT = Path(__file__).resolve().parent.parent
specification = importlib.util.spec_from_file_location('toolchain', ROOT/'Scripts/verify-toolchain.py')
toolchain = importlib.util.module_from_spec(specification)
specification.loader.exec_module(toolchain)
swift = Path(toolchain.compiler_path(None)).with_name('swift')
directory = ROOT/'.build/imported-protocol-consumer'
sources = directory/'Sources/ImportedProtocolProbe'
sources.mkdir(parents=True, exist_ok=True)
inputs = [ROOT/'Protocols/Fixtures/xdg-shell.xml', ROOT/'Protocols/wayland.xml', Path(__file__), ROOT/'Scripts/generate-protocol.py',
          ROOT/'Scripts/generate-extension-bindings.py',
          ROOT/'Tests/ImportedProtocolPeer/ImportedProtocolPeer.c', ROOT/'Tests/ImportedProtocolPeer/include/ImportedProtocolPeer.h',
          ROOT/'Package.swift', *[path for path in (ROOT/'Sources').rglob('*') if path.is_file()]]
hashes = {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
command = ['python3', str(ROOT/'Scripts/generate-protocol.py'), '--xml', str(inputs[0]), '--import', str(inputs[1]),
           '--output-directory', str(sources), '--namespace', 'XdgShellProtocol']
subprocess.run(command, check=True)
subprocess.run(command+['--check'], check=True)
binding_command = ['python3', str(ROOT/'Scripts/generate-extension-bindings.py'), '--xml', str(inputs[0]), '--import', str(inputs[1]),
                   '--output-directory', str(sources), '--namespace', 'XdgShellProtocol']
subprocess.run(binding_command, check=True)
subprocess.run(binding_command+['--check'], check=True)
model = json.loads((sources/'protocol-manifest.json').read_text())
count = 0
for source, protocol in zip(inputs[:2], model['inputs'], strict=True):
    output = directory/(source.stem+'.c')
    subprocess.run(['wayland-scanner', 'private-code', str(source), str(output)], check=True)
    native = output.read_text()
    # Source names select only the corresponding document's tables; the IR preserves their opcode order.
    generator_specification = importlib.util.spec_from_file_location('schema_generator', ROOT/'Scripts/generate-protocol.py')
    generator = importlib.util.module_from_spec(generator_specification);generator_specification.loader.exec_module(generator)
    local = generator.parse(source.read_bytes(), {interface['name'] for interface in model['interfaces']},
                            {interface['name']+'.'+enum['name'] for interface in model['interfaces'] for enum in interface['enumerations']})
    for interface in local['interfaces']:
        for direction in ['requests','events']:
            if not interface[direction]:continue
            table = re.search(r'static const struct wl_message '+interface['name']+'_'+direction+r'\[\] = \{(.*?)\n\};', native, re.S)
            if not table:raise RuntimeError('Missing independent native message table.')
            expected = []
            for message in interface[direction]:
                signature = str(message['since']) if message['since']>1 else ''
                for argument in message['arguments']:
                    if argument['kind']=='new_id' and argument['interface'] is None:signature+='su'
                    signature+=('?' if argument['nullable'] else '')+{'int':'i','uint':'u','fixed':'f','string':'s','object':'o','new_id':'n','array':'a','fd':'h'}[argument['kind']]
                expected.append((message['name'],signature))
            if re.findall(r'\{ "([^"]+)", "([^"]*)",',table[1])!=expected:raise RuntimeError('Imported message signature mismatch.')
            count+=len(expected)
(directory/'Package.swift').write_text('''// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "ImportedProtocolProbe", dependencies: [.package(path: '''+json.dumps(str(ROOT))+''')],
    targets: [.systemLibrary(name: "ImportedWaylandServer", pkgConfig: "wayland-server"),
              .target(name: "ImportedProtocolPeer", dependencies: ["ImportedWaylandServer"], linkerSettings: [.linkedLibrary("wayland-server")]),
              .executableTarget(name: "ImportedProtocolProbe", dependencies: ["ImportedProtocolPeer", .product(name: "WaylandProtocol", package: "swift-wayland"),
                                                                        .product(name: "WaylandClient", package: "swift-wayland"),
                                                                        .product(name: "WaylandServer", package: "swift-wayland"),
                                                                        .product(name: "WaylandRuntime", package: "swift-wayland")],
                               exclude: ["protocol-manifest.json"], swiftSettings: [.strictMemorySafety()])], swiftLanguageModes: [.v6])
''')
peer_sources = directory/'Sources/ImportedProtocolPeer'
(peer_sources/'include').mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT/'Tests/ImportedProtocolPeer/ImportedProtocolPeer.c', peer_sources/'ImportedProtocolPeer.c')
shutil.copyfile(ROOT/'Tests/ImportedProtocolPeer/include/ImportedProtocolPeer.h', peer_sources/'include/ImportedProtocolPeer.h')
subprocess.run(['wayland-scanner', 'private-code', str(inputs[0]), str(peer_sources/'XdgShell.c')], check=True)
native_system = directory/'Sources/ImportedWaylandServer'
native_system.mkdir(parents=True, exist_ok=True)
(native_system/'shim.h').write_text('#include <wayland-server.h>\n')
(native_system/'module.modulemap').write_text('module ImportedWaylandServer [system] { header "shim.h" link "wayland-server" export * }\n')
(sources/'Main.swift').write_text('''import WaylandProtocol
import WaylandClient
import ImportedProtocolPeer
private final class PingState {
    var serial: UInt32?
    var configureSerial: UInt32?
    var toplevelSize: (Int32, Int32)?
}
@main struct ImportedProtocolProbe {
static func main() throws {
let bundle = try ProtocolDescriptorBundle(interfaces: XdgShellProtocol.interfaces)
precondition(bundle.interfaceNames.count == 28)
let desktop = try bundle.interface(named: "xdg_wm_base")
let surface = try bundle.interface(named: "wl_surface")
precondition(desktop.schema.version == 7)
precondition(surface.schema.version > 0)
precondition(bundle.allocatedBytes > 0 && bundle.allocatedBytes <= 16 * 1024 * 1024)
var descriptor: Int32 = -1
guard let peer = unsafe imported_protocol_peer_create(&descriptor) else { fatalError("Peer creation failed.") }
defer { unsafe imported_protocol_peer_destroy(peer) }
let connection = unsafe try ClientConnection(receiving: descriptor)
let registry = try connection.protocolDisplay().getRegistry()
let desktopObject = try registry.reference.bindXdgWmBase(name: unsafe imported_protocol_peer_global(peer),
    descriptor: desktop, version: 7, advertisedVersion: 7)
let state = PingState()
let subscription = try desktopObject.onEvent { event in
    switch consume event {
    case .ping(let serial): state.serial = serial
    }
}
try connection.flush()
precondition(unsafe imported_protocol_peer_dispatch(peer) == 0)
try connection.withPreparedRead { try $0.read() }
_ = try connection.dispatchPending()
precondition(state.serial == 0x12345678)
try desktopObject.reference.pong(serial: 0x12345678)
try connection.flush()
precondition(unsafe imported_protocol_peer_dispatch(peer) == 0)
precondition(unsafe imported_protocol_peer_pongs(peer) == 1)
let positioner = try desktopObject.reference.createPositioner()
try positioner.reference.setSize(width: 100, height: 200)
try connection.flush()
precondition(unsafe imported_protocol_peer_dispatch(peer) == 0)
precondition(unsafe imported_protocol_peer_resources(peer) == 2)
precondition(unsafe imported_protocol_peer_positioner_sizes(peer) == 1)
try positioner.destroy()
try connection.flush()
precondition(unsafe imported_protocol_peer_dispatch(peer) == 0)
precondition(unsafe imported_protocol_peer_resources(peer) == 1)
let compositor = try registry.reference.bind(name: unsafe imported_protocol_peer_compositor_global(peer),
    as: WlCompositor.self, version: 1, advertisedVersion: 1)
let coreSurface = try compositor.reference.createSurface()
let shellSurface = try desktopObject.reference.getXdgSurface(surface: coreSurface.reference.erased)
let shellSubscription = try shellSurface.onEvent { event in
    switch consume event {
    case .configure(let serial): state.configureSerial = serial
    }
}
let toplevel = try shellSurface.reference.getToplevel()
let toplevelSubscription = try toplevel.onEvent { event in
    switch consume event {
    case .configure(let width, let height, _): state.toplevelSize = (width, height)
    default: break
    }
}
try connection.flush()
precondition(unsafe imported_protocol_peer_dispatch(peer) == 0)
try connection.withPreparedRead { try $0.read() }
_ = try connection.dispatchPending()
precondition(state.configureSerial == 0xabcdef12)
precondition(state.toplevelSize?.0 == 800 && state.toplevelSize?.1 == 600)
try shellSurface.reference.ackConfigure(serial: 0xabcdef12)
try connection.flush()
precondition(unsafe imported_protocol_peer_dispatch(peer) == 0)
precondition(unsafe imported_protocol_peer_configure_acks(peer) == 1)
try toplevel.destroy()
try shellSurface.destroy()
try coreSurface.destroy()
try connection.flush()
precondition(unsafe imported_protocol_peer_dispatch(peer) == 0)
precondition(unsafe imported_protocol_peer_resources(peer) == 2)
try desktopObject.destroy()
try connection.flush()
precondition(unsafe imported_protocol_peer_dispatch(peer) == 0)
precondition(unsafe imported_protocol_peer_resources(peer) == 1)
withExtendedLifetime(subscription) {}
withExtendedLifetime(shellSubscription) {}
withExtendedLifetime(toplevelSubscription) {}
connection.requestClose()
let snapshot = try connection.snapshot()
precondition(snapshot.retainedRecords == 0)
print("{\\"interfaces\\":28,\\"bytes\\":\\(bundle.allocatedBytes),\\"pongs\\":1,\\"positionerSizes\\":1,\\"configureAcks\\":1}")
}
}
''')
environment = os.environ.copy()
for name in ['LD_PRELOAD','CC','CXX','CPP','LD','AR','NM','RANLIB','STRIP']:environment.pop(name,None)
subprocess.run([str(swift),'build','--package-path',str(directory),'-Xswiftc','-warnings-as-errors'],env=environment,check=True)
binary_directory = Path(subprocess.check_output([str(swift),'build','--package-path',str(directory),'--show-bin-path'],env=environment,text=True).strip())
result = json.loads(subprocess.check_output([str(binary_directory/'ImportedProtocolProbe')],env=environment,text=True))
subprocess.run([str(swift),'build','--package-path',str(directory),'-c','release','-Xswiftc','-warnings-as-errors'],env=environment,check=True)
release_directory = Path(subprocess.check_output([str(swift),'build','--package-path',str(directory),'-c','release','--show-bin-path'],env=environment,text=True).strip())
release_result = json.loads(subprocess.check_output([str(release_directory/'ImportedProtocolProbe')],env=environment,text=True))
if result != release_result:raise RuntimeError('Debug and release imported protocol consumers disagree.')
if hashes!={str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}:raise RuntimeError('Imported protocol inputs changed during verification.')
report = {'passed':True,'inputs':hashes,'messageSignatures':count,'consumer':result,'releaseConsumer':release_result,'scope':'External value and typed binding generation, native scanner equivalence, sealed arena construction, separate-package Debug and Release execution, and xdg_wm_base, xdg_positioner, xdg_surface, xdg_toplevel, and core wl_surface requests/events with an independent C server.'}
(directory/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({key:report[key] for key in ['passed','messageSignatures','consumer']},indent=2))
