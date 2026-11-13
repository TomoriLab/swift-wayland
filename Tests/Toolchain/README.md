# Swift 6.4.2 toolchain probes

These fixtures validate compiler behavior and selected native ABI/lifetime assumptions before the public library is implemented. They are not production bindings, a package API, or a proof of runtime memory safety.

From the repository root:

```sh
python3 Scripts/verify-toolchain.py
python3 Scripts/verify-toolchain.py --sanitize address
python3 Scripts/verify-toolchain.py --sanitize thread
```

The runner uses SWIFTC, a swiftc on PATH, or the installed Swiftly 6.4.2 compiler path. Use `--swiftc /absolute/path/to/swiftc` to select a compiler explicitly. It rejects any compiler version other than the exact Swift 6.4.2 release and executes host-native binaries only. Python's standard library, the matching toolchain's Clang, pkg-config, and libwayland development headers/libraries are required. No package dependency is downloaded.

Every fixture runs in Swift 6 mode with complete concurrency checking, strict memory safety, warnings as errors, and both `-Onone` and `-O`. Positive fixtures are compiled, linked, and executed. Negative fixtures are compiled to object code, not merely type-checked, because ownership diagnostics can occur after type checking. A rejection must have exit code 1 and the expected semantic diagnostics; unrelated failures, crashes, and unexpected successful compilation fail the probe. CustomLifetime is a feature-availability gate rather than a safety counterexample.

The manifest must list every Swift fixture exactly once. Input hashes are checked again at completion to reject a result produced while fixtures were changing. Logs, exact commands, diagnostics, outputs, versions, and input hashes are saved in `.build/toolchain-probes/<sanitizer>/report.json`. The output is ignored by Git. `--output` selects a different root and `--configuration debug|release` selects one configuration.

AddressSanitizer runs explicitly enable leak detection and halt on error. ThreadSanitizer runs separately with halt on error. Both instrument the fixture's C bridge and Swift executable; system libwayland is not rebuilt with instrumentation. A clean run applies to the exercised fixtures, not to the whole future library or all internal accesses in libwayland.

The native fixture imports client, server, cursor, and EGL headers, compares C/Swift layouts, and uses a real server display destroy listener. It tests 1,000 iterations of successful construction plus three failure stages, including a destroy callback during constructor rollback. Context retain/release balance is checked using weak references, and open descriptors must return to their warmed baseline. A compositor or GPU is not required. The C fixture borrows Swift userdata; Swift owns its retain until native construction failure or complete destruction returns.

OwnershipGraph is a single-threaded reference experiment covering root authority, strong cleanup records, invalid references, and outer-frame teardown. It must not be copied into production as a thread-safe implementation. SpanAcrossAwait intentionally succeeds: nonescapability does not universally forbid suspension when backing storage is valid. Native callback and SHM thread/suspension restrictions require additional API and runtime design.

See [toolchain validation](../../docs/WaylandKit.docc/ToolchainValidation.md) for results, audit boundaries, and remaining gates.
