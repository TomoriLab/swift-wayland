# Scalar dispatcher exploration

Measure a native socketpair event workload before treating a generic observation adapter as a generated hot path.

## Recorded configuration

The recorded host is Intel(R) Core(TM) i9-14900K on x86_64, kernel 7.3.1-arare-workstation-bore-llvm-v1. The process is pinned to logical CPU 0. Swift is 6.4.2 in release mode with warnings treated as errors; native client/server libraries are 1.26.0. Source hashes, compiler output, raw samples, and the comparison scope are preserved in docs/reference/dispatcher-benchmark.json. No affinity, power, or thermal claim beyond the recorded CPU binding is made.

Scripts/benchmark-dispatcher.py builds the executable in its own scratch directory, warms each implementation with 1,000 events, and takes nine counterbalanced samples of 10,000 events each. Both use the same C server/resource fixture and native client socketpair pipeline. Setup, registration, destruction, and disconnect are excluded from the timed loops.

## Results and interpretation

| Measurement | Recorded result |
|---|---|
| C counter dispatcher median throughput | 962,666 events/second |
| Swift observation dispatcher median throughput | 646,416 events/second |
| Exploratory Swift throughput reduction | 32.85% |
| Paired bootstrap 95% interval for that reduction | 31.19%–33.66% |

The bootstrap uses 10,000 resamples with fixed seed 0 over only nine paired samples. It is exploratory evidence, not a universal performance interval.

The Swift path constructs dynamic event snapshots and validates arguments through the ownership runtime. The C reference counts scalar callbacks. The experiment does not isolate allocations or individual checks, and the workloads are not the equivalent generated typed-path comparison required by the 10% engineering budget. It therefore does not establish performance parity or satisfy phase 7. Safety checks were preserved.

Per-event allocations, copied-byte counts, median/p95/p99 event latency, separate CPU time, generated typed dispatch, strings/arrays/descriptors, queue coordination, SHM, teardown timing, and a representative compositor remain unmeasured. See <doc:ImplementationProgress> for open acceptance gates.

## Reproduction

```sh
source ~/.zshrc
python3 Scripts/benchmark-dispatcher.py
```

The table records the checked-in report; update it alongside a newly recorded JSON report before publication. The script records new host-specific results. Compare source hashes and compiler/native versions before comparing measurements across changes.
