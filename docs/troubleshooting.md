# Troubleshooting

Start with the exact compiler or exception message. nimorm reports model and
field context for DSL failures and uses structured runtime exceptions.

## `cannot open file: nimorm`

The package is not visible to the current Nim environment.

From a nimorm checkout:

```shell
nimble install -d
nimble develop
```

For a one-off repository example, compile with the source path:

```shell
nim c -r --path:src examples/quickstart.nim
```

## `stringField maxLength must be at least 1`

Every `stringField` requires a positive compile-time length:

```nim
title = stringField(maxLength = 200)
```

Use `textField()` for unrestricted text.

## `onDelete = SetNull requires nullable = true`

The database cannot set a required relation to NULL. Declare both parts:

```nim
reviewer = foreignKey(User, onDelete = SetNull, nullable = true)
```

The generated storage becomes `Option[int64]`.

## PostgreSQL says the backend flag is required

Recompile the final application and every test binary that opens PostgreSQL:

```shell
nim c -d:nimormPostgres app.nim
```

## PostgreSQL cannot load libpq

Install the PostgreSQL client libraries and put their shared-library directory
on the runtime search path. On Windows this usually means the PostgreSQL `bin`
directory must be on `PATH`. The compile-time flag does not install libpq.

## `RecordNotFound` or `MultipleRecordsFound`

- `db.get(Model, id)` and query `first` require a row.
- query `get` requires exactly one row.
- use `getOrNone` or `firstOrNone` when absence is expected.
- add a UNIQUE constraint when application logic assumes uniqueness.

## A migration requires `allowDestructive`

The diff contains an operation that can remove data or narrow accepted values.
Run `sqlmigrate`, inspect the migration JSON and SQL, back up the database, then
pass `--allow-destructive` only if the change is intentional.

## A migration requires `allowReview`

The operation needs a data or type-conversion decision, such as adding a
required column without a default. Prepare the backfill or conversion first,
then enable `--allow-review`.

## SQLite says a table rebuild is required

SQLite cannot directly express the requested ALTER operation. Version `0.1.0`
does not guess how to copy, cast, or backfill rows. Write and review an explicit
table-rebuild migration for the application's data instead of bypassing the
error.

## Query logging still contains application values

Only fields whose names/columns contain `password`, `token`, `secret`, or
`apiKey` are marked automatically. Mark other raw values explicitly:

```nim
sensitiveDbValue(dbValue(value))
```

The safest production logger records SQL, duration outside nimorm, and
parameter count rather than full ordinary parameters.

## Raw SQL fails on one backend

SQLite placeholders are `?`; PostgreSQL placeholders are `$1`, `$2`, and so
on. ORM-generated queries choose automatically, but raw SQL is the caller's
responsibility.

## Still stuck?

Include the Nim version, nimorm commit/tag, backend, smallest model declaration,
exact command, and complete error message in a bug report. Remove credentials
and database contents first.
