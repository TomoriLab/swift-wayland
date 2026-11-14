# Protocol generation and coverage

Make the native API and XML protocol inventory the acceptance boundary for complete mapping.

## Baseline and manifest

The inspected libwayland 1.26.0 headers yield 452 header-local function declarations/inline definitions across 11 headers, verified with Clang AST declaration locations. The installed wayland.xml contains 23 interfaces and 134 requests/events. These are baseline counts, not implemented coverage. Named type and macro contracts are also recorded. See the adjacent `docs/reference` inventories for every extracted function and message.

Coverage generation uses Clang AST declarations, preprocessing records, shared-library exports, and XML parsing together. Each source item gets a stable ID, source version/hash, category, safety classification, target symbol, documentation page, ownership contract, test IDs, and implementation status. A header forward declaration is not another implemented function. Static inline helpers and function-like macros are not visible in a shared-library export list and must not be omitted.

```text
publicItems = functions ∪ dataSymbols ∪ types ∪ fields ∪ enumMembers ∪ macros ∪ protocolMessages
classifiedItems = safeMappings ∪ unsafeMappings ∪ semanticAliases
coverage = classifiedItems / publicItems
release requires: publicItems − classifiedItems = empty
```

The division above denotes count ratio after identity-based deduplication. Classification alone is not implementation. Track separate ratios for classified, implemented, documented, and tested items; full mapping requires all four sets to cover the baseline. An unsafe mapping must have a justification and caller obligations. A semantic alias records equivalence tests rather than silently excluding a deprecated C API.

## Header families

| Family | Complete mapping obligations |
|---|---|
| Client core | Connection, fd access, flush/error, timeout and single dispatch, queues, prepared reads, proxy wrappers, version/class/tag/userdata, listeners/dispatchers, all marshal variants, limits and logs |
| Server core | Displays, sockets/removal, clients/credentials/security/limits/iteration, globals/offers/withdrawal/filter, serials, resources/destructors/dispatch, SHM and SIGBUS types, event loops and all source kinds, signals/listeners, logger and fixes helper |
| Utilities | wl_list operations and iterator macros, wl_array, fixed conversions, message/interface/object/argument layouts, callback typedefs, visibility/deprecation/version metadata |
| Core protocol headers | All client convenience functions, listener records, server implementation records and senders, enums, opcodes and since-version constants |
| Cursor | Theme load/destroy/lookup, image buffer, animation frame and frame-duration, exposed cursor/image fields |
| EGL | Window create/destroy/resize/attached size, platform marker and opaque identity |
| Deprecated server header | Every legacy helper retained in an explicitly deprecated unsafe namespace |

Opaque native record layouts are not reconstructed in Swift. Public nonopaque fields get safe values or scoped views where meaningful, with raw compatibility available. Compiler visibility/printf/deprecation macros map to bridge attributes or documented compiler metadata rather than meaningless runtime functions.

## XML intermediate representation

Parse protocol, interface, request, event, argument, enum, entry, description, copyright, deprecation, and since metadata into a deterministic intermediate representation. Validate duplicate names, interface references, nullable types, argument signatures, destructor count, integer ranges, enum references, and opcode order. Reject unknown semantic attributes rather than silently generating incorrect code; descriptive metadata may be preserved without interpretation.

For each request, generate a client method and a server request handler. For each event, generate a server sender and client handler. Use explicit Int32/UInt32 storage, Fixed, optional typed objects where nullable, scoped strings/arrays, and descriptor ownership types. Generic new_id expands into the required interface and version metadata. A constructor validates both advertised and requested versions before native allocation.

Runtime negotiated version is not encoded as an infinite collection of Swift types. Validate `since <= objectVersion` before sending a request or event. Enums preserve unknown numeric values; bitfield enums use OptionSet-compatible semantics when appropriate. An unknown value must not trap simply because a newer peer added an enum entry. Protocol object errors and fatal wire errors remain distinct from local argument errors.

Generated destructors invalidate the local owner according to native marshal flags and protocol metadata. Event destructors and server-side destruction use the same handle transition machinery. Interface types cannot each invent bespoke cleanup.

## Safe and unsafe boundaries

Typed generation is the preferred path. Arbitrary wl_argument unions, raw listener vtables, untyped user data, intrusive pointer arithmetic, manually constructed interfaces, and unsafe object adoption remain available in WaylandUnsafe. A safe dynamic protocol API can exist only if it validates descriptor lifetime and the entire argument schema; an unchecked integer opcode overload is not safe.

All varargs marshal forms map to equivalent array-form calls or audited C adapters, with checks for version and destructor flags. Server printf error variants map to fixed-format adapters. No unchecked va_list escapes to Swift user code. C macro behavior that depends on arbitrary caller structs can only be mirrored in an unsafe compatibility operation; a separate safe list container preserves intended iteration without accepting arbitrary field offsets.

## Reproducibility and maintenance

Generate from a pinned XML input and compiler-independent intermediate representation. Sort only unordered metadata; never sort requests/events because source order determines opcodes. Output records input hash, generator version, and baseline version. Regeneration must be byte-identical and have a reviewable semantic diff. Preserve upstream copyright/license notices for copied descriptions or generated artifacts.

The scanner is a host tool and must work during Linux cross-compilation without executing target binaries. Generated source is checked into the repository initially to simplify review and dependency control; plugin-based generation is optional later. Select the XML parser after evaluating system availability, correctness, and dependency policy. No parser is installed or added now.

Verify generated output against wayland-scanner C output and wire traces in both directions. Round-trip tests alone are insufficient because identical bugs in client and server can agree. Include an independently generated C peer and a protocol-capable compositor fixture. Extension protocols use the same IR and runtime, with their own versioned inventory and test fixtures.

## Generated ownership and dispatch obligations

The IR must classify incoming descriptors, typed/generic new IDs, native object references, and destructor effects separately from plain scalar values. Generated decode paths create cleanup scopes before optional delivery and attach cleanup records before publishing constructor results. Ignored events still close descriptors and release new objects according to protocol policy. Outgoing constructor ownership is committed only after native creation succeeds, with rollback for listener/record publication failure.

Use one stable dispatcher/vtable per native object lifetime. Handler subscription changes update a Swift delivery table and never reinstall or free the C attachment. Generate lifetime dependencies and backing-storage guards for borrowed strings/arrays; generate owned copies if the compiler cannot express the required safe lifetime. Destructor entry points invoke the centralized record arbiter and cannot bypass deferred outer-frame teardown. Treat custom descriptor metadata as an owned arena, including cycles between interface definitions.

## Current generator evidence

The checked-in core XML, deterministic Swift schema, and JSON IR are generated by Scripts/generate-protocol.py. Scripts/verify-protocol.py runs 15 generator tests covering malformed/encoded XML and generated-source compilation and compares all 134 source-order message signatures against native wayland-scanner output. Scripts/verify-api-coverage.py combines Clang AST, macros, exports, header hashes, and XML into a 1,535-item baseline manifest. All 1,535 baseline items now have explicit classification. The compatibility manifest contains 1,401 native mappings and C-only preprocessing controls; 964 C layout/constant comparisons and 181 field compilation checks validate ABI projections. Independent C peers exercise ordinary core messages in both directions. Typed binding metadata alone is not used as runtime acceptance. External XML bundles and owned native arenas now have separate scanner, external-consumer, cyclic native-peer, and allocation-failure tests; managed dynamic extension client/server-resource bindings now have independent C-peer tests; generated typed extension facades compile in a separate consumer and pass lifecycle round trips; comprehensive extension runtime coverage remains gated. See <doc:OwnedProtocolMetadata>. See <doc:ImplementationProgress>.
