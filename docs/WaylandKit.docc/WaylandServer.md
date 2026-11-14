# ``WaylandServer``

Track server display, client, resource, and idle-source lifetimes through one native execution domain.

## Overview

The initial package-access slice uses native destroy watches and authoritative cleanup records. Client disconnect invalidates tracked resources before native cascading destruction completes. Native callbacks retain storage through outer event-loop frame quiescence. Full compositor APIs and complete native coverage are not yet implemented. Read <doc:ClientAndServer> and <doc:ImplementationProgress> for exact boundaries.

## Topics

### Server ownership

- ``ServerDisplay``
- ``ServerClient``
- ``ServerResource``
- ``ServerError``

### One-shot sources

- ``ServerIdleSource``

### Typed core protocol

- ``ServerInterface``
- ``ServerObject``
- ``ServerObjectReference``
- ``ServerMessageReader``
- ``ServerNewIdentifier``
- ``ServerDynamicIdentifier``
- ``ServerRequestSubscription``
- ``ServerProtocolError``

### Contracts and verification

- <doc:ClientAndServer>
- <doc:TypedProtocol>
- <doc:ImplementationProgress>
