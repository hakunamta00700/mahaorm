# Roadmap

This roadmap describes direction, not release promises. Items move only after
their API, correctness, migration, and performance costs are understood.

## Current foundation

- Native compile-time models and metadata
- SQLite CRUD and typed queries
- Explicit relations and nested transactions
- Optional PostgreSQL execution
- Schema snapshots, migration diffs, safety gates, and CLI
- Validation, sensitive log redaction, examples, tests, and benchmarks

## Candidate next milestones

### Query ergonomics

- projections with typed result shapes;
- aggregates beyond `count` and `exists`;
- explicit eager-loading helpers that avoid hidden N+1 queries;
- relation-aware filters without string paths.

### Migration completeness

- a reviewed SQLite table-rebuild operation with explicit copy/backfill rules;
- PostgreSQL migration CLI connection support;
- richer rename declarations where heuristics are ambiguous;
- release-tested migration compatibility guarantees.

### Runtime and operations

- connection-pool integration guidance;
- query duration hooks and structured logging contracts;
- PostgreSQL server integration in CI;
- a separate async backend contract, if it can avoid blocking execution.

### Release maturity

- tagged `0.1.0` release and Nimble package-directory publication;
- generated API documentation hosted beside the guides;
- compatibility policy and deprecation window;
- expanded backend/platform test matrix.

## Non-goals

nimorm will not hide database access behind implicit lazy model properties,
interpolate runtime values into SQL, silently approve destructive migrations,
or replace native Nim fields with runtime wrapper objects.

Open an issue before implementing a roadmap item. A small, typed, testable API
is more valuable than checking off a feature name.
