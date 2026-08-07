# Changelog

This file records user-visible changes. The project follows semantic versioning
once releases are tagged; until then, unreleased behavior may still change.

## 0.1.0 (unreleased)

### Added

- Compile-time `model` DSL that generates native Nim objects, metadata,
  serialization, typed field references, and validation code.
- SQLite CRUD, nested transactions, structured constraint errors, and bound
  parameters for text, numbers, NULL, and binary values.
- Typed filters, ordering, pagination, cardinality operations, bulk updates,
  deletes, and inspectable SQL plus parameters.
- Stateless model managers with standard QuerySet operations including
  `create`, `exclude`, `reverse`, `distinct`, `none`, primary-key lookup,
  optional lookup, last-row retrieval, and membership checks.
- Foreign-key and one-to-one declarations with explicit forward and reverse
  relation fetches.
- Optional PostgreSQL execution behind `-d:nimormPostgres`.
- Versioned schema snapshots, migration diffs, review/destructive safety gates,
  history tracking, and a migration CLI.
- Automatic query-log redaction for common sensitive field names.
- Executable quickstart and blog examples, user guides, reference pages,
  troubleshooting, FAQ, and performance baselines.

### Fixed

- Preserve explicit non-generated primary keys during inserts and reject
  relation target shapes that the current `int64 id` storage cannot represent.
- Generate valid PostgreSQL offset-only queries and stable names for generated
  foreign-key and composite-unique constraints.
- Dependency-order table migrations, include constraints for newly added
  relation fields, and reject unsupported constraint alterations explicitly.
- Keep transaction depth recoverable when commit/release fails, configure
  PostgreSQL bytea reads consistently, and isolate temporary test artifacts for
  parallel runs.

### Known boundaries

- The API is synchronous.
- SQLite ALTER operations that require a table rebuild must be implemented and
  reviewed by the application.
- Eager loading, projection, arbitrary aggregation, relation traversal inside
  filters, and automatic model discovery are not implemented.
