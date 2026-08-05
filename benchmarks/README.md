# Benchmarks

Run the SQLite in-memory benchmark with release optimizations:

```shell
nimble benchmark
```

The benchmark covers native object construction, repeated single inserts,
transactional inserts, primary-key lookup, typed query compilation, ORM row
mapping, and the equivalent raw row-fetch path. It is a local microbenchmark,
not a database-server capacity test. Compare results only on the same machine,
Nim version, compiler mode, and dependency versions.

Measured output for a particular environment belongs in `results.md` and is
regenerated whenever a change is expected to affect these paths.
