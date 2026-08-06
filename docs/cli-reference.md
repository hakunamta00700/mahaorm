# Migration CLI reference

The `nimorm` executable manages JSON schema diffs and migration history. Run
`nimorm --help` to print the installed command summary.

When working directly from this repository, commands can be run as:

```shell
nim c -r --path:src src/nimorm/cli/main.nim -- --help
```

## `makemigrations`

```text
nimorm makemigrations <previous.json|-> <current.json> <name> <output.json> [dependency]
```

Compares two schema snapshots and writes a reviewable migration file. Use `-`
for an empty previous schema.

```shell
nimorm makemigrations - schema/current.json 0001_initial migrations/0001.json
nimorm makemigrations schema/v1.json schema/v2.json 0002_posts migrations/0002.json 0001_initial
```

The optional dependency is another migration name, not a file path.

## `sqlmigrate`

```text
nimorm sqlmigrate <migration.json> <sqlite|postgres>
```

Prints the dialect-specific SQL without applying it:

```shell
nimorm sqlmigrate migrations/0002.json sqlite
```

Review this output before using migration safety overrides. Some SQLite changes
will report that a table rebuild is required instead of emitting unsafe SQL.

## `migrate`

```text
nimorm migrate <sqlite.db> <migration.json> [--allow-destructive] [--allow-review]
```

Applies one migration to SQLite and records its name in
`nimorm_migrations`. Re-running an applied migration prints `already applied`
and succeeds without executing its operations again.

- `--allow-destructive` permits operations classified as data removing or
  narrowing.
- `--allow-review` permits operations that need an explicit data/type plan.

The flags are independent. Read the migration's `reason` values and generated
SQL before enabling either one.

## `migrations`

```text
nimorm migrations <sqlite.db>
```

Prints applied migration names in application order.

## Exit behavior

- Success and help return exit code `0`.
- Invalid arguments, unknown commands, database failures, and migration errors
  print `nimorm: <message>` to stderr and return exit code `1`.

The CLI's `migrate` command opens SQLite only in `0.1.0`. PostgreSQL SQL can be
inspected with `sqlmigrate`; a PostgreSQL application may load and apply the
migration through the library API.
