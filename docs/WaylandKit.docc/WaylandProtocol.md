# ``WaylandProtocol``

Describe the pinned core protocol with deterministic, version-checked Swift schema metadata.

## Overview

The generated metadata preserves all 23 core interfaces and 134 requests/events. The host generator validates the XML and compares message names, opcode order, and expanded signatures against wayland-scanner. This module contains shared schemas, interface markers, exact fixed-point values, and open enum wrappers. Executable typed methods and ownership decoders live in WaylandClient and WaylandServer; see <doc:TypedProtocol>.

## Topics

### Core schema

- ``CoreProtocol``
- ``CoreInterface``
- ``ProtocolFixed``
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
- <doc:TypedProtocol>
- <doc:ImplementationProgress>
