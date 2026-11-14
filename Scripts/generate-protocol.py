#!/usr/bin/env python3
"""Validate the pinned Wayland XML and emit deterministic Swift schema metadata."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ElementTree

ROOT = Path(__file__).resolve().parent.parent
ATTRIBUTES = {
    "protocol": {"name"}, "copyright": set(), "description": {"summary"},
    "interface": {"name", "version", "frozen"},
    "request": {"name", "since", "type", "deprecated-since"},
    "event": {"name", "since", "type", "deprecated-since"},
    "arg": {"name", "type", "interface", "enum", "summary", "allow-null"},
    "enum": {"name", "since", "bitfield"},
    "entry": {"name", "value", "since", "deprecated-since", "summary"},
}
CHILDREN = {
    "protocol": {"copyright", "description", "interface"},
    "interface": {"description", "request", "event", "enum"},
    "request": {"description", "arg"}, "event": {"description", "arg"},
    "enum": {"description", "entry"}, "entry": {"description"},
    "arg": {"description"}, "description": set(), "copyright": set(),
}
KINDS = {"int": "signed", "uint": "unsigned", "fixed": "fixed", "string": "string",
         "object": "object", "new_id": "newIdentifier", "array": "array", "fd": "descriptor"}

def require(condition, message):
    if not condition:
        raise ValueError(message)

def identifier(value):
    require(value is not None and re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", value), "Invalid native identifier.")
    return value

def number(value, minimum=1, maximum=0xFFFFFFFF):
    result = int(value, 0)
    require(minimum <= result <= maximum, "Integer is outside its native range.")
    return result

def distinct(elements):
    names = [element.attrib["name"] for element in elements]
    require(len(names) == len(set(names)), "Duplicate source name.")

def xml_root(data):
    require(len(data) <= 4 * 1024 * 1024, "XML exceeds the scanner input quota.")
    text = data.decode("utf-8-sig")
    require("\x00" not in text, "Only UTF-8 XML input is supported.")
    declaration = re.match(r'\s*<\?xml\s+[^?]*\?>', text)
    if declaration:
        encoding = re.search(r"encoding\s*=\s*[\"']([^\"']+)[\"']", declaration.group(), re.I)
        require(encoding is None or encoding.group(1).lower().replace("_", "-") == "utf-8", "Only UTF-8 XML input is supported.")
    require("<!DOCTYPE" not in text.upper() and "<!ENTITY" not in text.upper(), "DTD and entities are prohibited.")
    root = ElementTree.fromstring(text)
    require(root.tag == "protocol", "Expected protocol root.")
    return root

def parse(data, external_interfaces=frozenset(), external_enumerations=frozenset()):
    root = xml_root(data)
    for element in root.iter():
        require(element.tag in ATTRIBUTES, "Unknown XML element: " + element.tag)
        require(set(element.attrib) <= ATTRIBUTES[element.tag], "Unknown semantic attribute: " + element.tag)
        require(all(child.tag in CHILDREN[element.tag] for child in element), "Invalid element nesting.")
        if element.tag not in ["copyright", "description"]:
            require("name" in element.attrib, "Missing native name.")
        if "name" in element.attrib:
            if element.tag == "entry":
                require(re.fullmatch(r"[a-zA-Z0-9_]+", element.attrib["name"]), "Invalid enum entry name.")
            else: identifier(element.attrib["name"])
    require(root.findall("interface"), "A protocol must define an interface.")
    interfaces = root.findall("interface")
    distinct(interfaces)
    interface_names = {element.attrib["name"] for element in interfaces} | set(external_interfaces)
    enumerations = {interface.attrib["name"] + "." + enumeration.attrib["name"]
                    for interface in interfaces for enumeration in interface.findall("enum")} | set(external_enumerations)
    result = {"protocol": root.attrib["name"], "sha256": hashlib.sha256(data).hexdigest(),
              "copyright": root.findtext("copyright", "").strip(), "interfaces": []}
    for interface in interfaces:
        version = number(interface.attrib["version"], maximum=0x7FFFFFFF)
        require(interface.get("frozen") in [None, "true", "false"], "Invalid frozen flag.")
        model = {"name": interface.attrib["name"], "version": version, "frozen": interface.get("frozen") == "true",
                 "description": interface.findtext("description", "").strip(), "requests": [], "events": [], "enumerations": []}
        for direction in ["request", "event"]:
            messages = interface.findall(direction)
            distinct(messages)
            previous_since = 1
            for opcode, message in enumerate(messages):
                since = number(message.get("since", "1"), maximum=version)
                require(since >= previous_since, "Message introduction versions must be monotonic.")
                previous_since = since
                require(message.get("type") in [None, "destructor"], "Unknown message effect.")
                arguments = message.findall("arg")
                distinct(arguments)
                require(sum(argument.get("type") == "new_id" for argument in arguments) <= 1,
                        "Multiple constructors are unsupported by native marshalling.")
                fields = []
                for argument in arguments:
                    kind = argument.attrib["type"]
                    require(kind in KINDS, "Unknown argument type.")
                    require(argument.get("allow-null") in [None, "true", "false"], "Invalid nullability.")
                    nullable = argument.get("allow-null") == "true"
                    require(not nullable or kind in ["object", "string", "array"], "Invalid nullable native type.")
                    target = argument.get("interface")
                    require(target is None or (kind in ["object", "new_id"] and target in interface_names), "Unknown interface.")
                    require(kind != "new_id" or target is not None or direction == "request",
                            "An event constructor requires a declared interface.")
                    enumeration = argument.get("enum")
                    if enumeration and "." not in enumeration:
                        enumeration = model["name"] + "." + enumeration
                    require(enumeration is None or (kind in ["int", "uint"] and enumeration in enumerations), "Unknown enum reference.")
                    fields.append({"name": argument.attrib["name"], "kind": kind, "nullable": nullable,
                                   "interface": target, "enumeration": enumeration})
                deprecated = message.get("deprecated-since")
                model[direction + "s"].append({"name": message.attrib["name"], "opcode": opcode, "since": since,
                    "deprecatedSince": number(deprecated, minimum=since, maximum=version) if deprecated else None,
                    "destructor": message.get("type") == "destructor", "arguments": fields,
                    "summary": message.find("description").get("summary", "") if message.find("description") is not None else "",
                    "description": message.findtext("description", "").strip()})
        enums = interface.findall("enum")
        distinct(enums)
        for enumeration in enums:
            entries = enumeration.findall("entry")
            distinct(entries)
            require(enumeration.get("bitfield") in [None, "true", "false"], "Invalid bitfield flag.")
            enum_since = number(enumeration.get("since", "1"), maximum=version)
            model["enumerations"].append({"name": enumeration.attrib["name"], "bitfield": enumeration.get("bitfield") == "true",
                "since": enum_since, "description": enumeration.findtext("description", "").strip(),
                "entries": [{"name": entry.attrib["name"], "summary": entry.get("summary", ""),
                             "deprecatedSince": number(entry.get("deprecated-since"), maximum=version) if entry.get("deprecated-since") else None, "value": number(entry.attrib["value"], minimum=-(1 << 31)) & 0xFFFFFFFF,
                             "since": number(entry.get("since", str(enum_since)), minimum=enum_since, maximum=version)} for entry in entries]})
        result["interfaces"].append(model)
    return result

def parse_bundle(documents):
    documents = list(documents)
    require(0 < len(documents) <= 64, "A protocol bundle requires between one and 64 XML inputs.")
    require(sum(len(data) for data in documents) <= 16 * 1024 * 1024, "Protocol bundle exceeds its aggregate input quota.")
    roots = [xml_root(data) for data in documents]
    interfaces = [interface for root in roots for interface in root.findall("interface")]
    require(len(interfaces) <= 4096, "Protocol bundle exceeds its interface quota.")
    names = [identifier(interface.get("name")) for interface in interfaces]
    require(len(names) == len(set(names)), "Duplicate imported interface definition.")
    protocols = [identifier(root.get("name")) for root in roots]
    require(len(protocols) == len(set(protocols)), "Duplicate imported protocol definition.")
    enumerations = {interface.get("name") + "." + identifier(enumeration.get("name"))
                    for interface in interfaces for enumeration in interface.findall("enum")}
    models = [parse(data, set(names), enumerations) for data in documents]
    digest = hashlib.sha256()
    for data in documents:
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
    return {"protocol": models[0]["protocol"], "sha256": digest.hexdigest(),
            "copyright": "\n\n".join(model["copyright"] for model in models if model["copyright"]),
            "inputs": [{"protocol": model["protocol"], "sha256": model["sha256"]} for model in models],
            "interfaces": [interface for model in models for interface in model["interfaces"]]}

def literal(value):
    if value is None: return "nil"
    if isinstance(value, bool): return "true" if value else "false"
    return json.dumps(value, ensure_ascii=False)

def swift(model, namespace="CoreProtocol", external=False):
    require(re.fullmatch(r"[A-Z][A-Za-z0-9]*", namespace), "Invalid generated Swift namespace.")
    names = {interface["name"]: "interface" + str(index) if external else interface["name"] for index, interface in enumerate(model["interfaces"])}
    lines = ["// Generated by Scripts/generate-protocol.py. Do not edit.", "// XML SHA-256: " + model["sha256"], *["// " + line if line else "//" for line in model["copyright"].splitlines()],
             *(["import WaylandProtocol"] if external else []),
             "", ("/// Provides complete source-order metadata for the pinned protocol inputs." if external else "/// Provides complete source-order metadata for the pinned core protocol."), "public enum " + namespace + " {",
             "    /// The exact SHA-256 of the source XML.", "    public static let sourceHash = " + literal(model["sha256"]),
             "    /// All native interfaces in source order.", "    public static let interfaces: [ProtocolInterfaceSchema] = [" + ", ".join(names[i["name"]] for i in model["interfaces"]) + "]"]
    for interface in model["interfaces"]:
        lines += ["", "    private static let " + names[interface["name"]] + " = ProtocolInterfaceSchema(",
                  "        name: " + literal(interface["name"]) + ", version: " + str(interface["version"]) + ","]
        for direction in ["requests", "events"]:
            lines.append("        " + direction + ": [")
            for message in interface[direction]:
                lines.append("            ProtocolMessageSchema(name: " + literal(message["name"]) + ", opcode: " + str(message["opcode"]) + ", since: " + str(message["since"]) + ", deprecatedSince: " + literal(message["deprecatedSince"]) + ", destructor: " + literal(message["destructor"]) + ", arguments: [")
                for argument in message["arguments"]:
                    lines.append("                ProtocolArgumentSchema(name: " + literal(argument["name"]) + ", kind: ." + KINDS[argument["kind"]] + ", nullable: " + literal(argument["nullable"]) + ", interface: " + literal(argument["interface"]) + ", enumeration: " + literal(argument["enumeration"]) + "),")
                lines.append("            ]),")
            lines.append("        ],")
        lines.append("        enumerations: [")
        for enumeration in interface["enumerations"]:
            lines.append("            ProtocolEnumSchema(name: " + literal(enumeration["name"]) + ", bitfield: " + literal(enumeration["bitfield"]) + ", entries: [")
            for entry in enumeration["entries"]:
                lines.append("                ProtocolEnumEntry(name: " + literal(entry["name"]) + ", value: " + str(entry["value"]) + ", since: " + str(entry["since"]) + "),")
            lines.append("            ]),")
        lines += ["        ]", "    )"]
    return "\n".join(lines + ["}", ""])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--xml", type=Path, help="Primary protocol XML; imports are supplied explicitly.")
    parser.add_argument("--import", dest="imports", type=Path, action="append", default=[])
    parser.add_argument("--output-directory", type=Path)
    parser.add_argument("--namespace", default="GeneratedProtocol")
    arguments = parser.parse_args()
    if arguments.xml:
        require(arguments.output_directory is not None, "External generation requires --output-directory.")
        model = parse_bundle([path.read_bytes() for path in [arguments.xml, *arguments.imports]])
        outputs = {arguments.output_directory / (arguments.namespace + ".swift"): swift(model, arguments.namespace, external=True),
                   arguments.output_directory / "protocol-manifest.json": json.dumps(model, indent=2, ensure_ascii=False) + "\n"}
    else:
        require(not arguments.imports and arguments.output_directory is None, "External generation requires --xml.")
        model = parse((ROOT / "Protocols/wayland.xml").read_bytes())
        outputs = {ROOT / "Sources/WaylandProtocol/CoreProtocol.swift": swift(model),
               ROOT / "docs/reference/core-protocol-manifest.json": json.dumps(model, indent=2, ensure_ascii=False) + "\n"}
    for path, text in outputs.items():
        if arguments.check:
            require(path.read_text() == text, "Generated output differs: " + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    print("Verified" if arguments.check else "Generated", len(model["interfaces"]), "interfaces and",
          sum(len(i["requests"]) + len(i["events"]) for i in model["interfaces"]), "messages.")

if __name__ == "__main__":
    main()
