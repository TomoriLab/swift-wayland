# ``WaylandProtocol``

Describe the pinned core protocol with deterministic, version-checked Swift schema metadata.

## Overview

The generated metadata preserves all 23 core interfaces and 134 requests/events. The host generator validates the XML and compares message names, opcode order, and expanded signatures against wayland-scanner. This module contains schemas rather than executable typed bindings. Read <doc:ImplementationProgress> for the remaining constructor, destructor, and ownership-decoding gates.

## Topics

### Core schema

- ``CoreProtocol``
- ``ProtocolInterfaceSchema``
- ``ProtocolMessageSchema``
- ``ProtocolArgumentSchema``
- ``ProtocolArgumentKind``

### Enums and validation

- ``ProtocolEnumSchema``
- ``ProtocolEnumEntry``
- ``ProtocolSchemaError``

### Generation and coverage

- <doc:ProtocolGeneration>
- <doc:ImplementationProgress>
