# Optional benchmarks

The resource-hardening campaign adds an optional benchmark smoke executable under `benchmarks/`. It is not part of the default AUnit suite and should not be used as a correctness gate with fixed timing thresholds.

Build with:

```sh
alr exec -- gprbuild -P benchmarks/http_client_benchmarks.gpr
```

Run with:

```sh
benchmarks/bin/benchmark_runner
```

The benchmark runner uses synthetic local data only. It currently reports elapsed time for URI parsing, header lookup, and HTTP/3 QUIC varint decoding, followed by a resource-counter snapshot. Future benchmarks should follow the same rules: no public internet, bounded iteration counts, deterministic input, no exact timing requirements, and no changes to public protocol semantics.
