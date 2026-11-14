#!/usr/bin/env python3
"""Generate typed core markers, open enum values, client requests, and owned events."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
specification = importlib.util.spec_from_file_location('schema_generator', ROOT / 'Scripts/generate-protocol.py')
schema_generator = importlib.util.module_from_spec(specification)
specification.loader.exec_module(schema_generator)

OWNERSHIP = json.loads((ROOT/'Protocols/ownership-effects.json').read_text())
def effect(interface, message):
    return next((entry for entry in OWNERSHIP['effects'] if entry['interface'] == interface['name'] and entry['request'] == message['name']), None)

def camel(name): return ''.join(part[:1].upper() + part[1:] for part in name.split('_'))
def member(name):
    name = {'id': 'identifier', 'fd': 'descriptor'}.get(name, name)
    parts = name.split('_')
    value = parts[0] + ''.join(part[:1].upper() + part[1:] for part in parts[1:])
    schema_generator.require(bool(value) and value != '_', 'Native identifier has no usable Swift spelling.')
    return '`' + ('value' + value if value[0].isdigit() else value) + '`'
def enum_type(argument):
    return ''.join(camel(part) for part in argument['enumeration'].split('.')) if argument['enumeration'] else None

def argument_type(argument, incoming=False):
    kind = argument['kind']
    result = enum_type(argument) or {'int':'Int32', 'uint':'UInt32', 'fixed':'ProtocolFixed', 'string':'String',
                                   'array':'[UInt8]', 'fd':'OwnedFileDescriptor' if incoming else 'BorrowedFileDescriptor'}.get(kind)
    if kind == 'object': result = 'ClientObjectReference<' + camel(argument['interface']) + '>' if argument['interface'] else 'AnyClientObjectReference'
    if kind == 'new_id': result = 'ClientObject<' + camel(argument['interface']) + '>'
    return result + ('?' if argument['nullable'] else '')

def wire(argument):
    value = member(argument['name']); kind = argument['kind']
    if enum_type(argument): value = ('Int32(bitPattern: ' + value + '.rawValue)') if kind == 'int' else value + '.rawValue'
    if kind in ['int','uint','fixed','string','array','fd']:
        return '.' + {'int':'signed','uint':'unsigned','fixed':'fixed','string':'string','array':'bytes','fd':'descriptor'}[kind] + '(' + value + ')'
    if kind == 'object': return '.object(' + value + ('?.endpoint' if argument['nullable'] else '.endpoint') + ')'
    return '.constructor'

def decode(argument, index, client=False):
    kind = argument['kind']; number = str(index)
    if kind == 'new_id': result = 'try reader.constructor(' + number + ', as: ' + camel(argument['interface']) + '.self)'
    elif kind == 'object':
        method = ('object' if argument['nullable'] else 'requiredObject') if argument['interface'] else ('anyObject' if argument['nullable'] else 'requiredAnyObject')
        result = 'try reader.' + method + '(' + number + (', as: ' + camel(argument['interface']) + '.self' if argument['interface'] else '') + ')'
    elif client and kind == 'uint': result = 'try unsafe reader.generatedUnsigned(' + number + ')'
    else:
        method = {'int':'signed','uint':'unsigned','fixed':'fixed','string':'string' if argument['nullable'] else 'requiredString','array':'bytes','fd':'descriptor'}[kind]
        result = 'try reader.' + method + '(' + number + ')'
    if enum_type(argument): result = enum_type(argument) + '(rawValue: ' + ('UInt32(bitPattern: '+result+')' if kind == 'int' else result) + ')'
    return result

def decode_scalar(argument, index):
    kind = argument['kind']
    field = {'int': 'i', 'uint': 'u', 'fixed': 'f'}[kind]
    result = 'unsafe arguments[' + str(index) + '].' + field
    if kind == 'fixed': result = 'ProtocolFixed(rawValue: ' + result + ')'
    if enum_type(argument): result = enum_type(argument) + '(rawValue: ' + ('UInt32(bitPattern: ' + result + ')' if kind == 'int' else result) + ')'
    return result

def server_type(argument, incoming=False):
    if argument['kind'] == 'new_id':
        return ('ServerNewIdentifier<' + camel(argument['interface']) + '>' if argument['interface'] else 'ServerDynamicIdentifier') if incoming else 'ServerObjectReference<' + camel(argument['interface']) + '>'
    return argument_type(argument, incoming).replace('ClientObjectReference', 'ServerObjectReference').replace('AnyClientObjectReference', 'AnyServerObjectReference')

def documentation(value, indentation='    '):
    description = value.get('description', '')
    if not description:
        return []
    return [indentation + '///'] + [indentation + '///' + (' ' + line.rstrip() if line.strip() else '') for line in description.splitlines()]

def generate_server(model, banner):
    output = [banner, 'import WaylandProtocol\nimport WaylandRuntime\n']
    for interface in model['interfaces']:
        name = camel(interface['name'])
        output += ['/// Owns incoming request obligations for native ' + interface['name'] + '.', 'public enum ' + name + 'Request: ~Copyable {']
        for message in interface['requests']:
            ownership = effect(interface, message)
            arguments = ', '.join(member(a['name']) + ': ' + ('ServerResourceSnapshot' if ownership and a['name'] == ownership['argument'] else server_type(a, True)) for a in message['arguments'])
            output += ['    /// Request opcode ' + str(message['opcode']) + ', since ' + str(message['since']) + '; constructor capabilities must be accepted or rejected.',
                       *documentation(message), '    case ' + member(message['name']) + ('(' + arguments + ')' if arguments else '')]
        output += ['}', '/// Supplies typed server request decoding for this core interface.', 'extension ' + name + ': ServerInterface {', '    /// The generated ownership-bearing request type.',
                   '    public typealias Request = ' + name + 'Request', '    /// Decodes fields in wire order with automatic rollback of initialized owned values.',
                   '    public static func decodeRequest(_ reader: inout ServerMessageReader) throws -> Request {', '        switch reader.opcode {']
        for message in interface['requests']:
            arguments=[]; index=0
            ownership = effect(interface, message)
            for argument in message['arguments']:
                if ownership and argument['name'] == ownership['argument']:
                    expression='try reader.destroyRegistry(' + str(index) + ')'
                elif argument['kind']=='new_id' and argument['interface'] is None:
                    index+=2; expression='try reader.dynamicConstructor(' + str(index) + ')'
                else: expression=decode(argument,index)
                arguments.append(member(argument['name']).strip('`') + ': ' + expression)
                index+=1
            output += ['        case ' + str(message['opcode']) + ': return .' + member(message['name']) + ('(' + ', '.join(arguments) + ')' if arguments else '')]
        output += ['        default: throw ServerProtocolError.invalidMessage', '        }', '    }', '}']
        for message in interface['events']:
            parent='ServerObject' if message['destructor'] else 'ServerObjectReference'
            output += ['extension ' + parent + ' where Interface == ' + name + ' {',
                       '    /// Sends native ' + interface['name'] + '.' + message['name'] + ' (opcode ' + str(message['opcode']) + ', since ' + str(message['since']) + ').',
                       '    ///', '    /// Object and descriptor leases span marshalling; terminal events consume resource authority.',
                       *documentation(message), '    public ' + ('consuming ' if message['destructor'] else '') + 'func ' + member(message['name']) + '(' + ', '.join(member(a['name']) + ': ' + server_type(a) for a in message['arguments']) + ') throws {']
            values=[('.object(' + member(a['name']) + '.endpoint)') if a['kind']=='new_id' else wire(a) for a in message['arguments']]
            output += ['        try ' + ('terminalEvent' if message['destructor'] else 'send') + '(opcode: ' + str(message['opcode']) + ', arguments: [' + ', '.join(values) + '])', '    }', '}']
    return '\n'.join(output)+'\n'

def validate_names(model):
    def unique(names, scope):
        schema_generator.require(len(names) == len(set(names)), 'Colliding Swift identifiers in ' + scope + '.')
    interfaces = model['interfaces']
    types = [camel(interface['name']) for interface in interfaces]
    types += [camel(interface['name']) + camel(enumeration['name']) for interface in interfaces for enumeration in interface['enumerations']]
    unique(types, 'protocol type namespace')
    unique(types + [camel(interface['name']) + suffix for interface in interfaces for suffix in ['Event', 'Request']], 'generated type namespace')
    for interface in interfaces:
        for direction in ['requests', 'events']:
            messages = interface[direction]
            unique([member(message['name']) for message in messages], interface['name'] + '.' + direction)
            for message in messages:
                unique([member(argument['name']) for argument in message['arguments']], interface['name'] + '.' + message['name'])
        for enumeration in interface['enumerations']:
            unique([member(entry['name']) for entry in enumeration['entries']], interface['name'] + '.' + enumeration['name'])

def generate(model):
    validate_names(model)
    banner = '// Generated by Scripts/generate-typed-protocol.py. Do not edit.\n// XML SHA-256: ' + model['sha256'] + '\n' + '\n'.join(('// ' + line.rstrip() if line.strip() else '//') for line in model['copyright'].splitlines()) + '\n'
    markers = [banner]
    client = [banner, 'import CWaylandClient\nimport WaylandProtocol\nimport WaylandRuntime\n']
    for interface in model['interfaces']:
        name = camel(interface['name'])
        scalar_messages = [message for message in interface['events'] if message['opcode'] < 64 and all(argument['kind'] in ('int', 'uint', 'fixed') for argument in message['arguments'])]
        scalar_mask = sum(1 << message['opcode'] for message in scalar_messages)
        client += ['extension ClientObject where Interface == ' + name + ' {',
                   '    /// Installs typed delivery with a statically specialized core decoder.',
                   '    /// Cancellation preserves permanent native attachment and mandatory ownership cleanup.',
                   '    public borrowing func onEvent(_ body: @escaping (consuming ' + name + 'Event) throws -> Void) throws -> CallbackSubscription {',
                   ('        unsafe try subscribe(body, scalarEventMask: ' + str(scalar_mask) + ', scalarHandler: { opcode, arguments in\n'
                    '            let event = unsafe try ' + name + '.decodeScalarEvent(opcode, arguments)\n'
                    '            try body(consume event)\n'
                    '        })' if scalar_messages else '        unsafe try subscribe(body)'), '    }', '}']
        markers += ['/// Identifies native ' + interface['name'] + ' metadata.', *documentation(interface, ''), 'public enum ' + name + ': CoreInterface {',
                    '    /// The exact immutable native interface name.', '    public static let interfaceName = ' + json.dumps(interface['name']), '}']
        for enumeration in interface['enumerations']:
            type_name = name + camel(enumeration['name'])
            markers += ['/// Preserves all native bits, including unknown future ' + enumeration['name'] + ' values.', *documentation(enumeration, ''),
                        'public struct ' + type_name + ': RawRepresentable, Equatable, Hashable, Sendable' + (', OptionSet' if enumeration['bitfield'] else '') + ' {',
                        '    /// The exact native value bits.', '    public let rawValue: UInt32',
                        '    /// Creates a value without rejecting unknown native bits.', '    public init(rawValue: UInt32) { self.rawValue = rawValue }',
                        '    /// Hashes the exact native bits, including unknown values.',
                        '    public var hashValue: Int { rawValue.hashValue }',
                        '    /// Combines the exact native bits into the caller hasher.',
                        '    public func hash(into hasher: inout Hasher) { rawValue.hash(into: &hasher) }']
            for entry in enumeration['entries']:
                markers += ['    /// Native ' + interface['name'] + '.' + enumeration['name'] + '.' + entry['name'] + '.',
                            '    /// ' + entry.get('summary', 'The exact native enumeration bits.'),
                            '    public static let ' + member(entry['name']) + ' = ' + ('Self([])' if enumeration['bitfield'] and entry['value'] == 0 else 'Self(rawValue: ' + str(entry['value']) + ')')]
            markers += ['}']
        event_name = name + 'Event'
        client += ['/// Owns the decoded event obligations of native ' + interface['name'] + '.', 'public enum ' + event_name + ': ~Copyable {']
        for message in interface['events']:
            arguments = ', '.join(member(a['name']) + ': ' + argument_type(a, True) for a in message['arguments'])
            client += ['    /// Event opcode ' + str(message['opcode']) + ', since ' + str(message['since']) + '; owned fields move into the handler.',
                       *documentation(message), '    case ' + member(message['name']) + ('(' + arguments + ')' if arguments else '')]
        client += ['}', '/// Supplies typed client event decoding for this core interface.', 'extension ' + name + ': ClientInterface {', '    /// The generated ownership-bearing event type.',
                   '    public typealias Event = ' + event_name, '    /// Decodes initialized fields in source order; partial failures destroy prior owned fields.',
                   '    public static func decodeEvent(_ reader: inout ClientMessageReader) throws -> Event {', '        switch reader.opcode {']
        for message in interface['events']:
            arguments = ', '.join(member(a['name']).strip('`') + ': ' + decode(a,index,client=True) for index,a in enumerate(message['arguments']))
            client += ['        case ' + str(message['opcode']) + ': return .' + member(message['name']) + ('(' + arguments + ')' if arguments else '')]
        client += ['        default: throw TypedProtocolError.invalidMessage', '        }', '    }', '}']
        if scalar_messages:
            scalar_lines = ['    /// Decodes fixed-size fields from the signature validated at attachment.',
                            '    @unsafe static func decodeScalarEvent(_ opcode: UInt32, _ arguments: UnsafeMutablePointer<wl_argument>?) throws -> Event {',
                            '        switch opcode {']
            for message in scalar_messages:
                if message['arguments']:
                    scalar_lines += ['        case ' + str(message['opcode']) + ':',
                                     '            guard let arguments = unsafe arguments else { throw TypedProtocolError.invalidMessage }']
                else: scalar_lines += ['        case ' + str(message['opcode']) + ':']
                fields = ', '.join(member(argument['name']).strip('`') + ': ' + decode_scalar(argument, index) for index, argument in enumerate(message['arguments']))
                scalar_lines += ['            return .' + member(message['name']) + ('(' + fields + ')' if fields else '')]
            scalar_lines += ['        default: throw TypedProtocolError.invalidMessage', '        }', '    }']
            client[-1:-1] = scalar_lines
        for message in interface['requests']:
            ownership = effect(interface, message)
            if ownership:
                schema_generator.require(len(message['arguments']) == 1 and message['arguments'][0]['kind'] == 'object' and message['arguments'][0]['interface'] == ownership['targetInterface'], 'Argument destruction rule no longer matches its pinned schema.')
            schema_generator.require(sum(a['kind']=='new_id' for a in message['arguments']) <= 1, 'Multiple constructors require an atomic publication transaction.')
            constructor = next((a for a in message['arguments'] if a['kind']=='new_id'),None)
            generic = constructor is not None and constructor['interface'] is None
            parent = 'ClientObject' if message['destructor'] else 'ClientObjectReference'
            client += ['extension ' + parent + ' where Interface == ' + name + ' {',
                       '    /// Sends native ' + interface['name'] + '.' + message['name'] + ' (opcode ' + str(message['opcode']) + ', since ' + str(message['since']) + ').',
                       '    ///', '    /// The shared encoder checks version, interface, connection, and payload lifetime.',
                       ('    /// The registry argument is consumed on every outcome; other owners retain their authority.' if ownership else '    /// Failure before publication leaves existing owners unchanged; acquired constructor obligations roll back.'),
                       '    /// Logical close rejects new operations immediately; physical release waits for native quiescence.',
                       *documentation(message)]
            arguments = [member(a['name']) + ': ' + ('consuming ClientObject<WlRegistry>' if ownership and a['name'] == ownership['argument'] else argument_type(a)) for a in message['arguments'] if a['kind']!='new_id']
            if generic: arguments += ['as interface: Target.Type', 'version: UInt32', 'advertisedVersion: UInt32']
            result = (' -> ClientObject<' + ('Target' if generic else camel(constructor['interface'])) + '>') if constructor else ''
            client += ['    public ' + ('consuming ' if message['destructor'] else '') + 'func ' + member(message['name']) + ('<Target: ClientInterface>' if generic else '') + '(' + ', '.join(arguments) + ') throws' + result + ' {']
            if generic: client += ['        let target = try CoreProtocol.requireSchema(for: Target.self)']
            values=[]
            for argument in message['arguments']:
                if generic and argument['kind']=='new_id': values += ['.string(target.name)', '.unsigned(version)', '.constructor']
                else: values.append(wire(argument))
            if ownership:
                body = 'try destroyRegistryObject(' + member(ownership['argument']) + ')'
            elif message['destructor']:
                schema_generator.require(not message['arguments'], 'Deferred destructors currently require zero arguments.')
                body = 'try destroy(opcode: ' + str(message['opcode']) + ')'
            elif constructor:
                body = 'return try construct(opcode: ' + str(message['opcode']) + ', arguments: [' + ', '.join(values) + '], as: ' + ('Target' if generic else camel(constructor['interface'])) + '.self' + (', version: version, advertisedVersion: advertisedVersion' if generic else '') + ')'
            elif len(message['arguments']) == 1 and message['arguments'][0]['kind'] == 'string':
                body = 'try sendString(opcode: ' + str(message['opcode']) + ', value: ' + member(message['arguments'][0]['name']) + ')'
            else: body = 'try send(opcode: ' + str(message['opcode']) + ', arguments: [' + ', '.join(values) + '])'
            client += ['        ' + body, '    }', '}']
    markers += ['extension CoreProtocol {',
                '    private static let admittedSchemas: [ObjectIdentifier: ProtocolInterfaceSchema] = [']
    markers += ['        ObjectIdentifier(' + camel(interface['name']) + '.self): interfaces[' + str(index) + '],' for index, interface in enumerate(model['interfaces'])]
    markers += ['    ]',
                '    /// Returns canonical metadata only for an exact generated core marker type.',
                '    /// External conformances cannot authorize native descriptors or execute a name getter here.',
                '    /// - Throws: CoreInterfaceError.unsupportedMarker for an external marker type.',
                '    public static func requireSchema<Interface: CoreInterface>(for type: Interface.Type) throws -> ProtocolInterfaceSchema {',
                '        guard let schema = admittedSchemas[ObjectIdentifier(type)] else { throw CoreInterfaceError.unsupportedMarker }',
                '        return schema', '    }', '}']
    outputs = {'Sources/WaylandServer/CoreBindings.swift': generate_server(model, banner), 'Sources/WaylandProtocol/CoreInterfaces.swift':'\n'.join(markers)+'\n', 'Sources/WaylandClient/CoreBindings.swift':'\n'.join(client)+'\n'}
    for target, side in [('CWaylandClient','client'),('CWaylandServer','server')]:
        outputs['Sources/'+target+'/CoreInterfaces.c'] = '#include "'+target+'.h"\n#include <string.h>\n\nconst struct wl_interface *wayland_kit_'+side+'_core_interface(const char *name)\n{\n'+''.join('    if (strcmp(name, "'+i['name']+'") == 0) return &'+i['name']+'_interface;\n' for i in model['interfaces'])+'    return NULL;\n}\n'
    outputs['docs/reference/typed-core-bindings.json'] = json.dumps({
        'protocolHash': model['sha256'],
        'ownershipEffects': OWNERSHIP,
        'interfaces': len(model['interfaces']),
        'requests': sum(len(i['requests']) for i in model['interfaces']),
        'events': sum(len(i['events']) for i in model['interfaces']),
        'nativeReserved': ['wl_display native error and ID management', 'wl_registry native server bind implementation'],
        'coverage': 'Generated in both directions. All ordinary core messages have independent C-peer wire tests; native-reserved display/registry messages retain native implementations and integration tests.',
        'messages': [{
            'interface': i['name'], 'direction': direction, 'name': m['name'], 'opcode': m['opcode'],
            'since': m['since'], 'destructor': m['destructor'],
            'ownedIncoming': [{'argument': a['name'], 'kind': a['kind']} for a in m['arguments'] if a['kind'] in ['fd','new_id']],
            'clientBinding': 'Sources/WaylandClient/CoreBindings.swift',
            'serverBinding': 'Sources/WaylandServer/CoreBindings.swift',
            'documentation': 'docs/WaylandKit.docc/TypedProtocol.md'
        } for i in model['interfaces'] for direction in ['requests','events'] for m in i[direction]]
    }, indent=2) + '\n'
    return outputs

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');arguments=parser.parse_args()
    model=schema_generator.parse((ROOT/'Protocols/wayland.xml').read_bytes())
    for name, content in generate(model).items():
        path=ROOT/name
        if arguments.check: schema_generator.require(path.read_text()==content,'Typed generated output differs: '+name)
        else: path.write_text(content)
    print('Verified' if arguments.check else 'Generated','typed core bindings for',len(model['interfaces']),'interfaces.')
if __name__=='__main__': main()
