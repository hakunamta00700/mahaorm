# Schema snapshots and migrations

Migrations compare explicit, versioned JSON snapshots. This avoids runtime
model discovery and makes the reviewed schema input reproducible.

## Create a snapshot

Use a small Nim program whenever models change:

```nim
import nimorm

# Import the modules that declare User and Post first.
schemaSnapshot(User, Post).saveSnapshot("schema/current.json")
```

The format currently has `formatVersion = 1`. Managed, non-abstract models are
included. Commit snapshots and migration JSON files with the code that consumes
them.

## Generate and inspect a migration

For an initial migration, use `-` as the previous snapshot:

```shell
nimorm makemigrations - schema/current.json 0001_initial migrations/0001.json
nimorm sqlmigrate migrations/0001.json sqlite
```

For later migrations:

```shell
nimorm makemigrations schema/previous.json schema/current.json 0002_posts migrations/0002.json 0001_initial
```

Diffs cover table and column creation/removal/rename, altered columns, indexes,
foreign keys, and composite unique constraints. Rename detection uses stable
model and field identities with changed table/column names; removing one field
and adding another is intentionally treated as drop/add.

## Apply and audit

The CLI currently applies migrations to SQLite:

```shell
nimorm migrate app.sqlite3 migrations/0001.json
nimorm migrations app.sqlite3
```

Applied names are recorded in `nimorm_migrations`. Dependencies are checked,
already-applied migrations are idempotent, and each operation batch plus its
history row is committed atomically.

Destructive operations are refused unless explicitly allowed. Operations that
need a data or type-conversion decision have a separate review gate:

```shell
nimorm migrate app.sqlite3 migrations/0002.json --allow-destructive --allow-review
```

Read the emitted SQL and the operation `reason` before using either flag.

## SQLite limitation

SQLite cannot express several ALTER operations directly. `AlterColumn`,
foreign-key changes, and composite UNIQUE changes that require recreating the
table raise `MigrationError` with an explicit table-rebuild requirement. The
library does not guess copy/cast/backfill behavior. Create a reviewed custom
rebuild process or a replacement migration appropriate for the application.

`sqlmigrate ... postgres` emits PostgreSQL SQL, but the CLI's `migrate` command
does not open PostgreSQL in `0.1.0`; applications may load a migration and call
`applyMigration` on a PostgreSQL `Database` when built with the backend flag.
