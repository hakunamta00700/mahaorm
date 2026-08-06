# Frequently asked questions

## Is nimorm stable?

Version `0.1.0` is an early release. The implemented paths have automated tests,
but API compatibility is not promised until a later stability milestone. Pin a
tag or commit in production code.

## Does it support async database calls?

No. The public API is synchronous. Wrapping blocking calls in async syntax would
still block an event loop, so a future async backend needs a separate connection
and execution contract.

## Which databases are supported?

SQLite is available by default. PostgreSQL is opt-in with
`-d:nimormPostgres` and requires libpq. Other databases are not implemented.

## Are model fields wrapper objects?

No. The model macro emits native Nim fields such as `string`, `int64`, `bool`,
and `Option[T]`. Field declarations exist only while the macro generates code.

## Does `insert` validate automatically?

No. Call `validate(value)` explicitly for application input. Database
constraints independently protect NOT NULL, UNIQUE, and foreign-key integrity.

## Does `createTables` replace migrations?

No. It is convenient for tests and new databases. Use snapshots and migrations
once schema changes must preserve existing data.

## Are queries protected from SQL injection?

ORM query values and CRUD values use bound parameters. Identifiers come from
compile-time model metadata and are quoted. Raw SQL and `dbDefault` remain
trusted-code APIs; do not concatenate user input into them.

## Does it lazy-load relations?

No. Models store relation IDs. Call `fetchRelated`, `fetchRelatedOrNone`, or
`related` explicitly. Eager-loading helpers and multi-hop filters are not in
`0.1.0`.

## Can migrations alter every SQLite schema safely?

No. Changes that require rebuilding a SQLite table fail explicitly. The
application must decide how existing rows are copied, cast, and backfilled.

## Is it thread-safe?

Database handles are mutable synchronous connections. Do not share one
connection concurrently across threads. Give each worker ownership of its own
connection and follow the backend client's threading rules.

## How should I report a bug?

Open a repository issue with a minimal reproduction, Nim version, backend,
nimorm version or commit, command, and full error text. Never include passwords,
tokens, production rows, or connection strings.
