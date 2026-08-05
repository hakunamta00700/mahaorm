# Benchmark results

Recorded on 2026-08-06 with Nim 2.2.4 on Windows, using a release build and an
in-memory SQLite database. Each `us/op` denominator is shown by the benchmark:
for result-set tests, one operation means one mapped/fetched row.

```text
nimorm SQLite in-memory benchmark
Nim 2.2.4; release build; rows=1000
native object creation               14.588 ms       0.146 us/op
ORM single INSERT                     1.856 ms       9.281 us/op
ORM transaction INSERT                5.748 ms       5.748 us/op
ORM primary-key SELECT                1.264 ms       6.322 us/op
typed query compilation             126.019 ms       6.301 us/op
ORM fetch + row mapping              58.230 ms       0.582 us/op
raw SQLite row fetch                 45.465 ms       0.455 us/op
checksum=4789285
```

The raw-fetch comparison still uses nimorm's typed SQLite execution layer, but
does not construct model objects. The difference therefore approximates model
row-mapping overhead, not the complete overhead versus calling SQLite's C API
directly. These numbers are a regression baseline rather than a cross-machine
performance claim.
