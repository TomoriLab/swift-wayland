# ``WaylandClient``

Coordinate synchronous client reads and permanent proxy observation through checked native lifetimes.

## Overview

This package-access slice targets Swift 6.4.2 and x86_64 Linux. Read <doc:ClientAndServer> for connection, queue, reservation, cancellation, and shutdown contracts. Read <doc:ProxyDispatcher> before raw native proxy adoption. Typed core bindings and owned event decoding are described in <doc:TypedProtocol>. Full native API coverage remains incomplete; see <doc:ImplementationProgress>.

## Topics

### Connection and read coordination

- ``ClientConnection``
- ``ClientEventQueue``
- ``ClientReadReservation``
- ``ClientCoordinationError``
- ``ClientError``

### Permanent event observation

- ``ClientProxyDispatcher``
- ``ClientEvent``
- ``ClientEventArgument``

### Typed core protocol

- ``ClientInterface``
- ``ClientObject``
- ``ClientObjectReference``
- ``ClientMessageReader``
- ``TypedProtocolError``

### Contracts and verification

- <doc:ClientAndServer>
- <doc:ProxyDispatcher>
- <doc:TypedProtocol>
- <doc:ImplementationProgress>
