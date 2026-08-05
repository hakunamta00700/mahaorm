# Getting started

## Requirements

- Nim 2.0 or newer (the repository is tested with Nim 2.2.4)
- Nimble
- SQLite through the `db_connector` package
- optionally, PostgreSQL client libraries for the opt-in backend

From this repository, install dependencies and run the complete suite:

```shell
nimble install -d
nimble test
nimble example
```

While developing a separate consumer project, use `nimble develop` in the
nimorm checkout or add the appropriate package source to the consumer's Nimble
file.

## First database

```nim
import nimorm

model Note:
  subject = stringField(maxLength = 120)
  text = textField()

let db = openSqlite("notes.sqlite3")
db.createTables(Note)

var note = Note(subject: "First note", text: "Hello from Nim")
let problems = note.validate()
if problems.len == 0:
  note = db.insert(note)

echo db.get(Note, note.id).subject
db.close()
```

`createTables` is convenient for tests and initial prototypes. Once data must
survive schema changes, use versioned snapshots and migrations instead.

## Core conventions

- An `id: int64` auto-incrementing primary key is generated unless disabled or
  replaced explicitly.
- A nullable field is `Option[T]`; use `some(value)` and `none(T)`.
- Model validation is explicit: call `validate(value)` before persistence when
  application input needs validation. Database constraints remain the final
  integrity boundary.
- SQL values are always bound parameters. Identifiers come from compile-time
  model metadata and are quoted for both supported dialects.
- A `Database` connection is synchronous and should be closed with `defer`.

Continue with [models](models.md), [queries](queries.md), and
[migrations](migrations.md). The complete executable flow is
[`examples/blog.nim`](../examples/blog.nim).
