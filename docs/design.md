# Architecture and design

## Goals

nimorm keeps application-facing values idiomatic Nim while moving model
structure and type mistakes to compilation. Runtime layers consume immutable
metadata and typed values; they do not inspect arbitrary objects or keep a
second mutable field graph.

## Compile-time boundary

`model_macro.nim` parses the `model` block, validates its AST, and emits:

- an exported native object type;
- an immutable `ModelMeta` constant and typedesc accessor;
- encode/decode and insert/update preparation procs;
- typed `FieldRef` and `RelationRef` sets;
- field-specific validation code.

Nullable values are `Option[T]`. Relations store IDs. This keeps normal object
construction, assignment, generics, and compiler type checking available to
application code.

The macro is deliberately strict about accepted literal syntax. Clear
model/field/option diagnostics are preferable to accepting arbitrary
expressions that later fail during code generation.

## Runtime layers

```text
native model object
  -> generated serialization / validation / field references
  -> stateless Manager and immutable QuerySet APIs
  -> CRUD, relation, and migration APIs
  -> backend-neutral metadata, AST, and DbValue parameters
  -> SQLite or optional PostgreSQL execution
```

`DbValue` is the execution boundary for NULL, integers, floats, text, and
binary data. Sensitive marking is metadata on a parameter; backends redact a
copy for logging and bind the original value.

`Model.objects(db)` is a stateless model-level Manager. Each manager call starts
from a fresh QuerySet with the model's default ordering; QuerySet modifiers copy
query state and remain independently reusable.

The query builder stores an AST until a terminal operation. Compilation quotes
metadata-derived identifiers, escapes LIKE patterns, and emits placeholders
plus a separate parameter sequence. It never interpolates runtime values.

## Schema and migrations

The same `ModelMeta` drives SQLite/PostgreSQL DDL and versioned schema
snapshots. Migration diffs are data: operations carry safety classifications,
reasons, dependencies, and backend-independent field/model snapshots.

Execution preflights every safety gate, checks history/dependencies, compiles
for the selected dialect, then applies statements and the history row inside a
transaction. SQLite rebuild-required operations fail explicitly because data
copying and casting need application decisions.

## Backend boundary

SQLite is linked through `db_connector/sqlite3`. PostgreSQL is behind
`-d:nimormPostgres` and uses libpq parameter execution. The public database
contract is synchronous; introducing async behavior would require different
connection ownership and result lifetimes, so it is not mixed into this API.

## Compatibility and extension points

The largest compatibility risk is a future Nim parser changing AST shapes used
by the DSL. Compile-failure fixtures and generated-code tests make that boundary
visible. The clean extension points are new field mappings, query AST nodes,
additional backend implementations, eager-loading planners, and a reviewed
SQLite table-rebuild operation.

Current non-goals are runtime model discovery, hidden lazy relation queries,
implicit validation on persistence, asynchronous wrappers around blocking
calls, and automatic destructive migrations.
