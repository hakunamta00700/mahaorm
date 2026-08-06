# Changelog

This file records user-visible changes. The project follows semantic versioning
once releases are tagged; until then, unreleased behavior may still change.

## Unreleased

### Added

- Compile-time `model` DSL that generates native Nim objects, metadata,
  serialization, typed field references, and validation code.
- SQLite CRUD, nested transactions, structured constraint errors, and bound
  parameters for text, numbers, NULL, and binary values.
- Typed filters, ordering, pagination, cardinality operations, bulk updates,
  deletes, and inspectable SQL plus parameters.
- Foreign-key and one-to-one declarations with explicit forward and reverse
  relation fetches.
- Optional PostgreSQL execution behind `-d:nimormPostgres`.
- Versioned schema snapshots, migration diffs, review/destructive safety gates,
  history tracking, and a migration CLI.
- Automatic query-log redaction for common sensitive field names.
- Executable quickstart and blog examples, user guides, reference pages,
  troubleshooting, FAQ, and performance baselines.

### Known boundaries

- The API is synchronous.
- SQLite ALTER operations that require a table rebuild must be implemented and
  reviewed by the application.
- Eager loading, projection, arbitrary aggregation, relation traversal inside
  filters, and automatic model discovery are not implemented.
