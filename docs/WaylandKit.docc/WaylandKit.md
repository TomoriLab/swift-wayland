# WaylandKit

Design a complete Swift binding for libwayland with explicit ownership and verifiable resource lifetimes.

## Overview

This catalog specifies the proposed architecture. It does not describe an implemented module. Safe entry points will prevent pointer escape, double destruction, and access through invalidated handles. Raw compatibility operations will remain explicitly unsafe and outside that guarantee.

## Topics

### Architecture and safety

- <doc:Architecture>
- <doc:OwnershipAndFFI>
- <doc:MathematicalModel>
- <doc:SafetyReview>

### Execution and protocol mapping

- <doc:DispatchAndConcurrency>
- <doc:ProtocolGeneration>

### Documentation and acceptance

- <doc:Documentation>
- <doc:Validation>
