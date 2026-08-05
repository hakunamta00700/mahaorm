# Database backends

Both backends implement the same synchronous `Database`, `DbValue`, CRUD,
query, schema, transaction, and migration contracts. SQL dialect differences
remain inside schema/query compilers and backend execution modules.

## SQLite

SQLite is always available:

```nim
let db = openSqlite("app.sqlite3")
defer: db.close()
```

Connections enable `PRAGMA foreign_keys = ON`. Nested `transaction` blocks use
savepoints. In-memory databases are ideal for unit tests.

## PostgreSQL

PostgreSQL is opt-in so SQLite-only binaries do not load `libpq`:

```shell
nim c -d:nimormPostgres --path:src app.nim
```

```nim
let db = openPostgres(
  host = "localhost",
  port = 5432,
  database = "app",
  user = "app",
  password = getEnv("APP_DATABASE_PASSWORD"))
defer: db.close()
```

The machine running the binary must provide a compatible libpq shared library
on its runtime search path. PostgreSQL uses `$n` parameters, `RETURNING` for
generated IDs, identity columns, JSONB, UUID, BYTEA, and TIMESTAMPTZ mappings.

Compile the integration test only when a disposable database is configured:

```shell
nim c -r -d:nimormPostgres -d:nimormPostgresIntegration --path:src tests/test_postgres_backend.nim
```

It reads `NIMORM_PG_HOST`, `NIMORM_PG_PORT`, `NIMORM_PG_DATABASE`,
`NIMORM_PG_USER`, and `NIMORM_PG_PASSWORD`, and recreates `pg_records`.

## Parameters, logging, and errors

Raw execution is available when ORM operations are insufficient:

```nim
discard db.execute("UPDATE posts SET title = ? WHERE id = ?", [
  dbValue("New title"), dbValue(10)
])
let rows = db.queryRows("SELECT id, title FROM posts")
```

Use the correct placeholder style for the active backend. ORM-generated SQL
chooses it automatically.

```nim
db.enableQueryLogging(proc(sql: string; params: seq[DbValue]) =
  echo sql, " parameter-count=", params.len
)
```

Logging is opt-in. Sensitive model fields are redacted before the callback,
while the original values are still bound to the database. Never concatenate
untrusted values into raw SQL or `dbDefault`.

Database failures are classified as `ConnectionError`, `SqlExecutionError`,
`SerializationError`, `ConstraintViolation`, `UniqueViolation`,
`ForeignKeyViolation`, and `NotNullViolation`. Transaction and migration
failures have their own error types.

The API is intentionally synchronous. Use connection-per-worker ownership and
keep blocking database work away from an async event loop; a future async
backend should expose a separate contract.
