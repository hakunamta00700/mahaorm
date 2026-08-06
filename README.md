# nimorm

`nimorm` is a compile-time model DSL and synchronous ORM for Nim 2.x. Models
become ordinary exported Nim objects; field declarations are consumed by the
macro and do not survive as runtime wrappers.

The current `0.1.0` implementation includes:

- native model types and immutable metadata with compile-time diagnostics;
- SQLite CRUD, nested transactions, typed parameters, and structured errors;
- a typed query AST with filtering, ordering, limits, counts, updates, deletes,
  and inspectable parameterized SQL;
- foreign-key and one-to-one relations;
- an opt-in PostgreSQL backend;
- versioned schema snapshots, migration diffs, safety gates, and a CLI;
- generated model validation and query-log redaction for sensitive fields.

## Quick start

Install or develop the package with Nimble, then import its single public entry
point:

```shell
nimble install
```

```nim
import nimorm

model Post:
  title = stringField(maxLength = 200, minLength = 3)
  body = textField(nullable = true)
  views = integerField(default = 0)

  meta:
    tableName = "posts"

let db = openSqlite(":memory:")
db.createTables(Post)

let saved = db.insert(Post(title: "Nim ORM"))
let posts = Post.objects(db)
  .filter(it.title.contains("Nim") and it.views >= 0)
  .orderBy(it.id.desc)
  .all()

echo saved.id
echo posts[0].title
db.close()
```

Run the repository checks and examples with:

```shell
nimble test
nimble example
nimble benchmark
```

## Documentation

- [Documentation home](docs/index.md)
- [Installation](docs/installation.md)
- [5-minute quickstart](docs/quickstart.md)
- [Build a small blog](docs/tutorial.md)
- [Models and metadata](docs/models.md)
- [Fields and validation](docs/fields.md)
- [Typed queries and CRUD](docs/queries.md)
- [Relations](docs/relations.md)
- [Migrations](docs/migrations.md)
- [SQLite and PostgreSQL](docs/backends.md)
- [Cookbook](docs/cookbook.md)
- [API reference](docs/api-reference.md)
- [Migration CLI reference](docs/cli-reference.md)
- [Troubleshooting](docs/troubleshooting.md)
- [FAQ](docs/faq.md)
- [Architecture and design](docs/design.md)
- [Benchmark method and results](benchmarks/README.md)

## Deliberate boundaries

The API is synchronous. Async execution should be a separate backend contract
instead of hiding blocking calls behind async syntax. Query projection,
aggregates beyond `count`, eager-loading helpers, relation traversal inside a
filter, and automatic model discovery are not implemented in `0.1.0`. SQLite
schema changes that require rebuilding a table are reported explicitly instead
of being applied through a lossy implicit rewrite.

PostgreSQL is compiled only with `-d:nimormPostgres` and requires the libpq
runtime. See [the backend guide](docs/backends.md) before enabling it.
