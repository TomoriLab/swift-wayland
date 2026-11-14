# ``WaylandRuntime``

Manage native lifetime obligations with checked handles and dependency-ordered deferred release.

## Overview

This package-access module is the internal ownership foundation shared by the staged WaylandKit client and server targets. It is implemented and tested on x86_64 Linux with Swift 6.4.2. Native adoption and native destruction notification require audited adapter contracts; the module does not expose a complete Wayland client or compositor API.

Read [OwnershipRuntime](https://tomorilab.github.io/swift-wayland/documentation/project/ownershipruntime) for the implemented state model, unsafe boundaries, native-frame semantics, tests, and limitations. The broader project design starts at [Architecture](https://tomorilab.github.io/swift-wayland/documentation/project/architecture).

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

### Native proxy lifetime and cancellation

- ``ProxyDispatcherOwner``
- ``ProxyDispatcherError``
- ``NativeDestructionObserver``
- ``ReadCancellation``

### Descriptors and callbacks

- ``OwnedFileDescriptor``
- ``BorrowedFileDescriptor``
- ``ReceivedFileDescriptor``
- ``FileDescriptorError``
- ``FileDescriptorCloseResult``
- ``FileDescriptorSnapshot``
- ``CallbackAttachment``
- ``CallbackSubscription``
- ``CallbackCancellation``
- ``CallbackContextError``
- ``CallbackInstallResult``
- ``CallbackDeliveryResult``
