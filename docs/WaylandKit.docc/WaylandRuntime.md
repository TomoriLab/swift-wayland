# ``WaylandRuntime``

Manage native lifetime obligations with checked handles and dependency-ordered deferred release.

## Overview

This package-access module is the internal ownership foundation for future WaylandKit client and server targets. It is implemented and tested on x86_64 Linux with Swift 6.4.2. Native adoption and native destruction notification require audited adapter contracts; the module does not expose a complete Wayland client or compositor API.

Read <doc:OwnershipRuntime> for the implemented state model, unsafe boundaries, native-frame semantics, tests, and limitations. The broader project design starts at <doc:WaylandKit>.

## Topics

### Authority and checked references

- ``OwnershipSession``
- ``OwnedHandle``
- ``ObjectHandle``

### Identity and accounting

- ``HandleIdentity``
- ``HandleKind``
- ``OwnershipSnapshot``

### Closure and failure

- ``CloseProgress``
- ``OwnershipError``

### Design and verification

- <doc:OwnershipRuntime>
- <doc:WaylandKit>
