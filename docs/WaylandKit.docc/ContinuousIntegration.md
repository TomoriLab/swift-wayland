# Reproduce validation

Run the pinned compiler, native, ownership, documentation, and lifecycle checks through one entry point.

## Runner contract

All workflows use GitHub-hosted `ubuntu-26.04` runners. The shared `.github/actions/setup-wayland` action installs Swift 6.4.2 through the Swiftly-based `swift-actions/setup-swift@v3` action (currently beta), installs native build prerequisites, and builds the checksum-pinned libwayland 1.26.0 source with its scanner into `.build/native-none-install`. Workspace-local include, library, loader, pkg-config, and executable paths select that build. No self-hosted runner is required. The validation workflow uses manual and main-branch push triggers. Hosted performance measurements remain subject to runner variability and do not waive the acceptance thresholds.

```sh
python3 Scripts/validate.py --native-sanitizers --soak --benchmark
```

The preflight rejects a different compiler/native baseline before later work. The validator checks deterministic generated sources and manifest coverage, positive/negative compiler fixtures, independent C peers, malformed XML, production wait-loop faults, debug/release tests, standalone public consumers, separate native ASan/TSan configurations, isolated SHM faults, 10,000 lifecycle iterations, DocC rendering, and an equivalent typed C/Swift benchmark. No host native library is replaced.

## WaylandKit test workflow

`.github/workflows/tests.yml` runs on every branch push, pull request, and manual dispatch. Independent debug and release jobs run `swift test --configuration <configuration> --disable-xctest -Xswiftc -warnings-as-errors` on x86_64 with the shared pinned toolchain setup. A failing configuration does not cancel the other configuration. Superseded runs for the same branch or pull request are canceled.

This workflow reports the Swift Testing suite separately from the full validation workflow, which also repeats debug and release tests as part of its aggregate evidence. The test workflow requires only read access to repository contents and does not deploy documentation or run performance acceptance benchmarks.

## Evidence and limitations

Each command writes a separate log under .build/validation and an aggregate report. Native instrumentation confirms loaded library paths. Address checks keep leak detection enabled and preserve ODR detection by loading instrumented client/server libraries in separate variants. Cursor/EGL instrumentation accompanies these variants; TSan loads the isolated native library set together. No sanitizer suppression is part of the configuration.

The lifecycle executable warms up before measuring FD counts. Every iteration closes client, server, descriptor, byte-array, and SHM sessions and asserts zero retained records. It includes lazy cursor buffers, EGL windows, subscriptions, globals, idle/timer sources, explicit native SHM refs, client destruction, descriptor duplication, and owned snapshots. Stable FD counts and ledgers are checked directly. RSS is not used as a substitute for leak instrumentation.

The benchmark preserves native and Swift samples, batch size, allocation-entry counts, compiler, CPU affinity, and source hashes. A successfully completed command can report a failed quantitative throughput gate. The aggregate report keeps command completion distinct from release acceptance. Human review and deferred aarch64 verification cannot be synthesized by CI. Check <doc:ImplementationProgress> for open conditions before treating a passing command matrix as a release approval.

## Local targeted checks

Use `python3 Scripts/verify-toolchain.py` for compiler/ABI experiments, `python3 Scripts/verify-runtime-ownership.py` and `verify-client-ownership.py` for actual package ownership rejection, and `python3 Scripts/verify-examples.py` for external public consumers. Use `python3 Scripts/verify-shm-faults.py` after the isolated address-instrumented native build exists. `python3 Scripts/build-documentation.py` converts each module with warnings as errors, checks documented symbol pages, and merges the archives. The final static archive is .build/documentation/WaylandKit.doccarchive.

## Bridge allocation failures

Run `python3 Scripts/verify-bridge-allocation-faults.py` to compile the actual production argument, destroy-watch, descriptor-arena, byte-array, and mutex bridge objects with isolated allocator substitution. Twenty-five selected failures exercise every allocation stage of those bridge factories and partial payload construction, plus native mutex initialization rollback. An independent pointer ledger rejects untracked or repeated free operations and requires zero outstanding allocations after each scenario. Successful native client/resource destruction checks watch retirement as a control. The fixture runs under ASan/UBSan with leak detection enabled. Native libwayland allocations and fatal Swift allocator termination are outside this targeted substitution.

Scripts/verify-imported-protocols.py builds a separate xdg-shell metadata consumer from the pinned fixture and core imports. It verifies native scanner equivalence, owned arena construction, and separate-package Debug/Release typed integration with an independent C server. The exercised interfaces include xdg_wm_base, xdg_positioner, xdg_surface, xdg_toplevel, and core wl_surface, including ping/pong and configure/ack. This selected integration coverage does not establish every xdg-shell message or compositor-state policy.

## Compiler-profile throughput diagnostic

Run `python3 Scripts/benchmark-build-profiles.py` to compare ordinary release compilation with `-cross-module-optimization -package-cmo` on the selected Swift toolchain. Each profile builds the same benchmark source into its own scratch directory with warnings treated as errors. After both builds finish, the harness pins one CPU and alternates profile order across three processes per workload. Each process retains the benchmark's nine alternating C/Swift pairs at batch sizes 1 and 64. Scalar delivery, zero-argument requests, and fixed-string requests remain separate workloads.

The report at `.build/build-profile-benchmark/report.json` records build commands, compiler, architecture, CPU affinity, source and binary hashes, raw samples, and per-process losses. Its initial incomplete marker prevents a failed run from leaving a successful report. This is a throughput diagnostic, not an allocation, sanitizer, latency, or release acceptance result. It does not change package compiler settings or replace `benchmark-typed.py` in the validation matrix.

## GitHub Pages publication

`.github/workflows/documentation.yml` builds and deploys the merged eight-module DocC site on pushes to `main` or a manual run on `main`. It uses the same hosted toolchain setup as validation but does not depend on the unfinished performance or native baseline leak gates. Successful documentation publication is not release acceptance.

Enable **Settings → Pages → Build and deployment → Source → GitHub Actions** in the repository before the first deployment. The `github-pages` environment must permit deployments from `main`. The build job reads the Pages base path through `actions/configure-pages`, transforms the merged archive for static hosting, and uploads only that archive. The separate deployment job receives `pages: write` and `id-token: write`; the build job has no deployment write permission. Deployments are serialized without canceling an active deployment.

For the repository's default Pages address, the site root is `https://tomorilab.github.io/swift-wayland/`. Its root redirects to `documentation/`; deep links and assets use the base path supplied by Pages, including an empty path for a custom domain. The URL is an expected destination, not evidence of a completed remote deployment.

Reproduce the static conversion locally after preparing the pinned toolchain and native libraries:

```sh
python3 Scripts/build-documentation.py --hosting-base-path /swift-wayland
```

The output is `.build/documentation/WaylandKit.doccarchive`. Serve its parent with the archive mounted at `/swift-wayland/` to verify repository-relative URLs. Omit `--hosting-base-path` for the ordinary unmodified archive build. See [GitHub's custom Pages workflow documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages) and [Swift-DocC hosting guidance](https://swiftlang.github.io/swift-docc-plugin/documentation/swiftdoccplugin/generating-documentation-for-hosting-online/).
