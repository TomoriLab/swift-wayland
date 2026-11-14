#!/usr/bin/env python3
"""Generate checked typed extension facades over managed protocol objects."""
import argparse
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
specification = importlib.util.spec_from_file_location('schema_generator', ROOT / 'Scripts/generate-protocol.py')
schema_generator = importlib.util.module_from_spec(specification)
specification.loader.exec_module(schema_generator)


def camel(value):
    return ''.join(part[:1].upper() + part[1:] for part in value.split('_'))


def member(value):
    if value == 'fd': value = 'descriptor'
    if value == 'id': value = 'identifier'
    parts = value.split('_')
    return '`' + parts[0] + ''.join(part[:1].upper() + part[1:] for part in parts[1:]) + '`'


def symbol(namespace, interface, suffix):
    return namespace + camel(interface) + suffix


def enumeration_type(argument, namespace):
    reference = argument['enumeration']
    if reference is None: return None
    interface, enumeration = reference.split('.', 1)
    return symbol(namespace, interface, camel(enumeration))


def field_type(argument, side, incoming, namespace, primary):
    kind = argument['kind']
    enumeration = enumeration_type(argument, namespace)
    if enumeration: return enumeration
    primitive = {'int': 'Int32', 'uint': 'UInt32', 'fixed': 'ProtocolFixed', 'string': 'String',
                 'array': '[UInt8]', 'fd': 'OwnedFileDescriptor' if incoming else 'BorrowedFileDescriptor'}
    if kind in primitive:
        result = primitive[kind]
    elif kind == 'object':
        result = 'AnyClientObjectReference' if side == 'client' else 'AnyServerObjectReference'
    elif kind == 'new_id':
        if side == 'server':
            result = 'ServerDynamicIdentifier' if incoming else 'AnyServerObjectReference'
        elif incoming:
            target = argument['interface']
            result = symbol(namespace, target, 'Client') if target in primary else 'ClientProtocolObject'
        else:
            result = 'ClientProtocolObject'
    else:
        raise ValueError('Unsupported protocol field kind: ' + kind)
    return result + ('?' if argument['nullable'] else '')


def value_expression(argument, side):
    name = member(argument['name'])
    kind = argument['kind']
    if argument['enumeration']:
        return '.signed(Int32(bitPattern: ' + name + '.rawValue))' if kind == 'int' else '.unsigned(' + name + '.rawValue)'
    if kind == 'new_id': return '.constructor' if side == 'client' else '.object(' + name + ')'
    code = {'int': 'signed', 'uint': 'unsigned', 'fixed': 'fixed', 'string': 'string',
            'array': 'bytes', 'fd': 'descriptor', 'object': 'object'}[kind]
    return '.' + code + '(' + name + ')'


def decode_expression(argument, index, side, namespace, primary):
    kind = argument['kind']
    if kind == 'new_id':
        if side == 'server': return 'try reader.' + ('protocolConstructor' if argument['interface'] else 'dynamicConstructor') + '(' + str(index) + ')'
        target = argument['interface']
        constructor = 'try reader.protocolConstructor(' + str(index) + ')'
        return ('try ' + symbol(namespace, target, 'Client') + '(' + constructor + ')') if target in primary else constructor
    if kind == 'object':
        return 'try reader.' + ('anyObject' if argument['nullable'] else 'requiredAnyObject') + '(' + str(index) + ')'
    method = {'int': 'signed', 'uint': 'unsigned', 'fixed': 'fixed', 'string': 'string' if argument['nullable'] else 'requiredString',
              'array': 'bytes', 'fd': 'descriptor'}[kind]
    expression = 'try reader.' + method + '(' + str(index) + ')'
    enumeration = enumeration_type(argument, namespace)
    if enumeration:
        return enumeration + '(rawValue: ' + ('UInt32(bitPattern: ' + expression + ')' if kind == 'int' else expression) + ')'
    return expression


def parameters(message, side, incoming, namespace, primary):
    return ', '.join(member(argument['name']) + ': ' + field_type(argument, side, incoming, namespace, primary)
                     for argument in message['arguments'] if incoming or side == 'server' or argument['kind'] != 'new_id')


def validate_names(model, primary_names, namespace):
    types = []
    for interface in model['interfaces']:
        for enumeration in interface['enumerations']:
            types.append(symbol(namespace, interface['name'], camel(enumeration['name'])))
    for name in primary_names:
        for suffix in ('Client', 'ClientReference', 'ClientEvent', 'Server', 'ServerReference',
                       'ServerRequest', 'ServerIdentifier'):
            types.append(symbol(namespace, name, suffix))
    schema_generator.require(len(types) == len(set(types)), 'Generated extension type names collide.')
    primary = set(primary_names)
    for interface in model['interfaces']:
        if interface['name'] not in primary: continue
        for direction in ('requests', 'events'):
            messages = interface[direction]
            spellings = [member(message['name']) for message in messages]
            schema_generator.require(len(spellings) == len(set(spellings)), 'Generated extension method names collide.')
            for message in messages:
                labels = [member(argument['name']) for argument in message['arguments']]
                schema_generator.require(len(labels) == len(set(labels)), 'Generated extension argument labels collide.')


def render(model, primary_names, namespace):
    schema_generator.require(namespace.isidentifier() and namespace[0].isupper(), 'Namespace must be an uppercase Swift identifier.')
    validate_names(model, primary_names, namespace)
    primary = set(primary_names)
    interfaces = [interface for interface in model['interfaces'] if interface['name'] in primary]
    schema_generator.require(len(interfaces) == len(primary), 'Primary interfaces are missing from the complete XML bundle.')
    lines = ['// Generated by Scripts/generate-extension-bindings.py. Do not edit.',
             '// XML SHA-256: ' + model['sha256']]
    lines.extend('// ' + line for line in model['copyright'].splitlines())
    lines.extend(['', 'import WaylandClient', 'import WaylandServer', 'import WaylandProtocol', 'import WaylandRuntime', ''])
    for interface in model['interfaces']:
        for enumeration in interface['enumerations']:
            type_name = symbol(namespace, interface['name'], camel(enumeration['name']))
            lines.extend(['/// Preserves native ' + interface['name'] + '.' + enumeration['name'] + ' bits, including unknown values.',
                          'public struct ' + type_name + ': RawRepresentable, Hashable, Sendable' + (', OptionSet' if enumeration['bitfield'] else '') + ' {',
                          '    /// The exact 32-bit native representation.',
                          '    public let rawValue: UInt32',
                          '    /// Creates an open value without rejecting future native bits.',
                          '    public init(rawValue: UInt32) { self.rawValue = rawValue }'])
            for entry in enumeration['entries']:
                lines.extend(['    /// Native ' + interface['name'] + '.' + enumeration['name'] + '.' + entry['name'] + '.',
                              '    public static let ' + member(entry['name']) + ' = ' +
                              ('Self([])' if enumeration['bitfield'] and entry['value'] == 0 else 'Self(rawValue: ' + str(entry['value']) + ')')])
            lines.append('}')
    for interface in interfaces:
        name = interface['name']
        client = symbol(namespace, name, 'Client')
        client_reference = symbol(namespace, name, 'ClientReference')
        client_event = symbol(namespace, name, 'ClientEvent')
        server = symbol(namespace, name, 'Server')
        server_reference = symbol(namespace, name, 'ServerReference')
        server_request = symbol(namespace, name, 'ServerRequest')
        lines.extend([
            '/// Owns native ' + name + ' with the generated schema and the managed client runtime.',
            'public struct ' + client + ': ~Copyable {',
            '    private let object: ClientProtocolObject',
            '    /// Admits only a complete descriptor graph matching the generated definitions.',
            '    public init(_ object: consuming ClientProtocolObject) throws {',
            '        guard object.reference.schema.name == "' + name + '" else { throw TypedProtocolError.wrongInterface }',
            '        try object.reference.requireEquivalent(to: ' + namespace + '.interfaces)',
            '        self.object = object',
            '    }',
            '    /// Produces a checked reference without destruction authority.',
            '    public var reference: ' + client_reference + ' { borrowing get { ' + client_reference + '(object.reference) } }',
            '    /// Reports runtime validity without granting an unchecked native borrow.',
            '    public var isValid: Bool { borrowing get { object.reference.isValid } }',
            *(['    /// Delivers decoded values while retaining native cleanup for canceled delivery.',
               '    public borrowing func onEvent(_ body: @escaping (consuming ' + client_event + ') throws -> Void) throws -> CallbackSubscription {',
               '        try object.onEvent { reader in try body(' + client_event + '.decode(&reader)) }',
               '    }'] if interface['events'] else []),
            '    /// Consumes local proxy destruction authority.',
            '    @discardableResult public consuming func close() -> CloseProgress { object.close() }',
            '}',
            '/// Provides schema-checked native requests for ' + name + '.',
            'public struct ' + client_reference + ' {',
            '    private let object: ClientProtocolReference',
            '    init(_ object: ClientProtocolReference) { self.object = object }',
            '    /// Erases interface typing for a same-connection object argument.',
            '    public var erased: AnyClientObjectReference { object.erased }',
            '    /// Reports logical validity at the observation point.',
            '    public var isValid: Bool { object.isValid }',
            '}',
            '/// Owns decoded event fields of native ' + name + '.',
            'public enum ' + client_event + ': ~Copyable {'])
        for message in interface['events']:
            fields = parameters(message, 'client', True, namespace, primary)
            lines.append('    /// Native event opcode ' + str(message['opcode']) + ', since ' + str(message['since']) + '.')
            lines.append('    case ' + member(message['name']) + ('(' + fields + ')' if fields else ''))
        lines.extend(['    /// Decodes fields in wire order; partial owned values roll back on failure.',
                      '    public static func decode(_ reader: inout ClientMessageReader) throws -> Self {',
                      '        switch reader.opcode {'])
        for message in interface['events']:
            fields = ', '.join(member(argument['name']).strip('`') + ': ' + decode_expression(argument, index, 'client', namespace, primary)
                               for index, argument in enumerate(message['arguments']))
            lines.append('        case ' + str(message['opcode']) + ': return .' + member(message['name']) + ('(' + fields + ')' if fields else ''))
        lines.extend(['        default: throw TypedProtocolError.invalidMessage', '        }', '    }', '}'])
        for message in interface['requests']:
            method = member(message['name'])
            constructor = next((argument for argument in message['arguments'] if argument['kind'] == 'new_id'), None)
            generic = constructor is not None and constructor['interface'] is None
            owner = message['destructor']
            target = constructor['interface'] if constructor else None
            result = (symbol(namespace, target, 'Client') if target in primary else 'ClientProtocolObject') if constructor else None
            if generic: result = 'ClientProtocolObject'
            arguments = parameters(message, 'client', False, namespace, primary)
            if generic:
                arguments += (', ' if arguments else '') + 'descriptor: ProtocolDescriptor, version: UInt32, advertisedVersion: UInt32'
            values = ', '.join(value_expression(argument, 'client') for argument in message['arguments'])
            receiver = client if owner else client_reference
            lines.extend(['extension ' + receiver + ' {',
                          '    /// Sends native ' + name + '.' + message['name'] + ' after schema and lifetime validation.',
                          '    public ' + ('consuming ' if owner else '') + 'func ' + method + '(' + arguments + ') throws' + (' -> ' + result if result else '') + ' {'])
            operation = ('object.replace' if owner else 'object.construct') if constructor else ('object.destroy' if owner else 'object.request')
            call = (operation + '(opcode: ' + str(message['opcode']) + ', arguments: [' + values + ']' +
                    (', descriptor: descriptor, version: version, advertisedVersion: advertisedVersion' if generic else '') + ')')
            if constructor:
                lines.append('        let created = try ' + call)
                lines.append('        return ' + ('try ' + result + '(created)' if target in primary and not generic else 'created'))
            else:
                lines.append('        try ' + call)
            lines.extend(['    }', '}'])
        lines.extend([
            '/// Owns native ' + name + ' with the generated schema and managed server runtime.',
            'public struct ' + server + ': ~Copyable {',
            '    private let object: ServerProtocolObject',
            '    /// Admits only a complete descriptor graph matching the generated definitions.',
            '    public init(_ object: consuming ServerProtocolObject) throws {',
            '        guard object.reference.schema.name == "' + name + '" else { throw ServerProtocolError.invalidMessage }',
            '        try object.reference.requireEquivalent(to: ' + namespace + '.interfaces)',
            '        self.object = object',
            '    }',
            '    /// Produces a checked reference without destruction authority.',
            '    public var reference: ' + server_reference + ' { borrowing get { ' + server_reference + '(object.reference) } }',
            '    /// Reports runtime validity without granting an unchecked native borrow.',
            '    public var isValid: Bool { borrowing get { object.reference.isValid } }',
            *(['    /// Delivers decoded requests with single-use constructor and FD obligations.',
               '    public borrowing func onRequest(_ body: @escaping (consuming ' + server_request + ') throws -> Void) throws -> ServerRequestSubscription {',
               '        try object.onRequest { reader in try body(' + server_request + '.decode(&reader)) }',
               '    }'] if interface['requests'] else []),
            '    /// Consumes local resource destruction authority.',
            '    @discardableResult public consuming func close() -> CloseProgress { object.close() }',
            '}',
            '/// Provides schema-checked native events for ' + name + '.',
            'public struct ' + server_reference + ' {',
            '    private let object: ServerProtocolReference',
            '    init(_ object: ServerProtocolReference) { self.object = object }',
            '    /// Erases interface typing for a same-client object argument.',
            '    public var erased: AnyServerObjectReference { object.erased }',
            '    /// Reports logical validity at the observation point.',
            '    public var isValid: Bool { object.isValid }',
            '}',
            '/// Owns decoded request fields of native ' + name + '.',
            'public enum ' + server_request + ': ~Copyable {'])
        for message in interface['requests']:
            fields = parameters(message, 'server', True, namespace, primary)
            lines.append('    /// Native request opcode ' + str(message['opcode']) + ', since ' + str(message['since']) + '.')
            lines.append('    case ' + member(message['name']) + ('(' + fields + ')' if fields else ''))
        lines.extend(['    /// Decodes fields in wire order; partial owned values roll back on failure.',
                      '    public static func decode(_ reader: inout ServerMessageReader) throws -> Self {',
                      '        switch reader.opcode {'])
        for message in interface['requests']:
            index = 0
            fields = []
            for argument in message['arguments']:
                if argument['kind'] == 'new_id' and argument['interface'] is None: index += 2
                fields.append(member(argument['name']).strip('`') + ': ' + decode_expression(argument, index, 'server', namespace, primary))
                index += 1
            lines.append('        case ' + str(message['opcode']) + ': return .' + member(message['name']) +
                         ('(' + ', '.join(fields) + ')' if fields else ''))
        lines.extend(['        default: throw ServerProtocolError.invalidMessage', '        }', '    }', '}'])
        for message in interface['events']:
            method = member(message['name'])
            arguments = parameters(message, 'server', False, namespace, primary)
            values = ', '.join(value_expression(argument, 'server') for argument in message['arguments'])
            owner = message['destructor']
            lines.extend(['extension ' + (server if owner else server_reference) + ' {',
                          '    /// Sends native ' + name + '.' + message['name'] + ' after schema and lifetime validation.',
                          '    public ' + ('consuming ' if owner else '') + 'func ' + method + '(' + arguments + ') throws {',
                          '        try object.reference.send(opcode: ' + str(message['opcode']) + ', arguments: [' + values + '])' if owner else
                          '        try object.send(opcode: ' + str(message['opcode']) + ', arguments: [' + values + '])'])
            if owner: lines.append('        object.close()')
            lines.extend(['    }', '}'])
        lines.extend([
            '/// Owns a pending global bind for native ' + name + '.',
            'public struct ' + symbol(namespace, name, 'ServerIdentifier') + ': ~Copyable {',
            '    private let pending: ServerDynamicIdentifier',
            '    private let descriptor: ProtocolDescriptor',
            '    init(_ pending: consuming ServerDynamicIdentifier, descriptor: ProtocolDescriptor) {',
            '        self.pending = pending; self.descriptor = descriptor',
            '    }',
            '    /// Publishes one managed resource or rejects the unresolved bind on drop.',
            '    public consuming func accept() throws -> ' + server + ' {',
            '        try ' + server + '(pending.accept(descriptor: descriptor))',
            '    }',
            '}',
            'extension ClientObjectReference where Interface == WlRegistry {',
            '    /// Binds advertised ' + name + ' only after complete generated-schema admission.',
            '    public func ' + member('bind_' + name) + '(name: UInt32, descriptor: ProtocolDescriptor,',
            '        version: UInt32, advertisedVersion: UInt32) throws -> ' + client + ' {',
            '        guard descriptor.schema.name == "' + name + '" else { throw TypedProtocolError.wrongInterface }',
            '        try descriptor.requireEquivalent(to: ' + namespace + '.interfaces)',
            '        return try ' + client + '(bind(name: name, descriptor: descriptor, version: version, advertisedVersion: advertisedVersion))',
            '    }',
            '}',
            'extension ServerClient {',
            '    /// Creates a server-selected ' + name + ' resource with imported metadata.',
            '    public borrowing func ' + member('create_' + name) + '(descriptor: ProtocolDescriptor, version: UInt32) throws -> ' + server + ' {',
            '        guard descriptor.schema.name == "' + name + '" else { throw ServerProtocolError.invalidMessage }',
            '        try descriptor.requireEquivalent(to: ' + namespace + '.interfaces)',
            '        return try ' + server + '(createProtocolObject(descriptor: descriptor, version: version))',
            '    }',
            '}',
            'extension ServerDisplay {',
            '    /// Advertises ' + name + ' with a single-use typed bind identifier.',
            '    public borrowing func ' + member('add_' + name + '_global') + '(descriptor: ProtocolDescriptor, version: UInt32,',
            '        handler: @escaping (consuming ' + symbol(namespace, name, 'ServerIdentifier') + ') throws -> Void) throws -> ServerProtocolGlobal {',
            '        guard descriptor.schema.name == "' + name + '" else { throw ServerProtocolError.invalidMessage }',
            '        try descriptor.requireEquivalent(to: ' + namespace + '.interfaces)',
            '        return try addProtocolGlobal(descriptor: descriptor, version: version) { pending in',
            '            try handler(' + symbol(namespace, name, 'ServerIdentifier') + '(pending, descriptor: descriptor))',
            '        }',
            '    }',
            '}',
        ])
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xml', type=Path, required=True)
    parser.add_argument('--import', dest='imports', type=Path, action='append', default=[])
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--namespace', required=True)
    parser.add_argument('--check', action='store_true')
    arguments = parser.parse_args()
    model = schema_generator.parse_bundle([path.read_bytes() for path in [arguments.xml, *arguments.imports]])
    primary = schema_generator.parse(arguments.xml.read_bytes(),
        {interface['name'] for interface in model['interfaces']},
        {interface['name'] + '.' + enumeration['name'] for interface in model['interfaces']
         for enumeration in interface['enumerations']})
    content = render(model, [interface['name'] for interface in primary['interfaces']], arguments.namespace)
    output = arguments.output_directory / (arguments.namespace + 'Bindings.swift')
    if arguments.check:
        schema_generator.require(output.read_text() == content, 'Generated extension bindings differ from XML.')
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(content)
    print('Verified' if arguments.check else 'Generated', len(primary['interfaces']), 'typed extension interfaces.')


if __name__ == '__main__':
    main()
