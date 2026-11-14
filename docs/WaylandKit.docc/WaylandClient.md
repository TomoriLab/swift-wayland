# ``WaylandClient``

Coordinate synchronous client reads and permanent proxy observation through checked native lifetimes.

## Overview

This package-access slice targets Swift 6.4.2 and x86_64 Linux. Read [ClientAndServer](https://tomorilab.github.io/swift-wayland/documentation/project/clientandserver) for connection, queue, reservation, cancellation, and shutdown contracts. Read [ProxyDispatcher](https://tomorilab.github.io/swift-wayland/documentation/project/proxydispatcher) before raw native proxy adoption. Typed core bindings and owned event decoding are described in [TypedProtocol](https://tomorilab.github.io/swift-wayland/documentation/project/typedprotocol). Full native API coverage remains incomplete; see [ImplementationProgress](https://tomorilab.github.io/swift-wayland/documentation/project/implementationprogress).

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
