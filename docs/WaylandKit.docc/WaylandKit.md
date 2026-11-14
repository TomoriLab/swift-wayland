# ``WaylandKit``

Use Swift bindings for libwayland with explicit ownership and checked resource lifetimes.

## Overview

This catalog documents the implemented x86_64 ownership runtime, typed core bindings, client/server adapters, and advanced APIs alongside their design invariants and remaining acceptance gates. Checked entry points validate resource generations and native lifetimes. Raw compatibility remains explicitly unsafe. See ImplementationProgress for measured evidence and deferred requirements.

## Topics

### Usage

- <doc:GettingStarted>
- <doc:ContinuousIntegration>

### Architecture and safety

- <doc:Architecture>
- <doc:OwnershipAndFFI>
- <doc:OwnershipRuntime>
- <doc:ProxyDispatcher>
- <doc:ClientAndServer>
- <doc:MathematicalModel>
- <doc:SafetyReview>

### Execution and protocol mapping

- <doc:DispatchAndConcurrency>
- <doc:ProtocolGeneration>
- <doc:AdvancedAPIs>
- <doc:NativeCompatibility>

### Documentation and acceptance

- <doc:Documentation>
- <doc:Validation>
- <doc:TypedProtocol>
- <doc:ImplementationProgress>
- <doc:DispatcherBenchmark>
- <doc:ToolchainValidation>

## Imported protocol metadata

- <doc:OwnedProtocolMetadata>
