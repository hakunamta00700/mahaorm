# Public API reference

Import `nimorm` to use the supported public surface. The entry point re-exports
models, fields, metadata, CRUD, queries, relations, transactions, schemas,
migrations, validation, and backend-neutral value types.

This page is a task-oriented index, not generated source documentation. Exact
signatures remain authoritative in [`src/nimorm.nim`](../src/nimorm.nim) and
its exported modules.

## Model declaration and metadata

| API | Result |
| --- | --- |
| `model Name: ...` | Generates the native object and supporting ORM code |
| `getModelMeta(Model)` | Immutable `ModelMeta` generated for a model |
| `getFieldMeta(Model, name)` | `FieldMeta`, or `ValueError` for an unknown field |
| `tableName(Model)` | Physical table name |
| `primaryKeyField(Model)` | `Option[FieldMeta]` |
| `schemaSql(Model, backend)` | Dialect-specific CREATE TABLE statements |

See [models](models.md) and [fields](fields.md) for the complete declaration
vocabulary.

## Connections and raw execution

```nim
proc openSqlite(path: string): Database
proc openPostgres(host: string; port: int;
                  database, user, password: string): Database
proc close(db: Database)
proc execute(db: Database; sqlText: string;
             params: openArray[DbValue] = []): int
proc queryRows(db: Database; sqlText: string;
               params: openArray[DbValue] = []): seq[DbRow]
macro createTables(db: typed; modelTypes: varargs[typed])
```

`openPostgres` requires `-d:nimormPostgres`. `execute` returns the affected-row
count. Each `DbRow` is a sequence of `DbValue` variants: NULL, integer, float,
text, or blob.

Construct parameters with `dbNull()` and `dbValue(value)`. Wrap a raw secret as
`sensitiveDbValue(dbValue(secret))` before query logging is enabled.

## CRUD

```nim
proc insert[T](db: Database; value: T): T
proc get[T](db: Database; modelType: typedesc[T]; primaryKey): T
proc getOrNone[T](db: Database; modelType: typedesc[T]; primaryKey): Option[T]
proc update[T](db: Database; value: var T): int
proc delete[T](db: Database; value: T): int
```

`insert` returns the stored copy with a generated integer ID. `get` accepts a
`DbValue`, `int`, `int64`, or `string` key. `update` needs a variable because
`autoNow` may modify it.

## QuerySet

Create a query with `Model.objects(db)`. Query modifiers return another
`QuerySet[T]`:

| Modifier | Purpose |
| --- | --- |
| `filter(expression)` | Add a typed predicate |
| `orderBy(field.asc)` / `orderBy(field.desc)` | Add ordering |
| `limit(n)` | Limit returned rows |
| `offset(n)` | Skip rows |
| `toSql()` | Return `CompiledQuery(sql, params)` without executing |

Terminal operations are `all`, `first`, `firstOrNone`, `get`, `count`,
`exists`, `update`, and `delete`.

Predicates include comparison operators, `between`, `inList`, `contains`,
`startsWith`, `endsWith`, `isNull`, and `isNotNull`. Combine them with `and`,
`or`, and `not`. Assign values with `it.field.set(value)`.

## Relations

```nim
relations(Model)
db.fetchRelated(source, relation)
db.fetchRelatedOrNone(source, relation)
db.related(target, relation)
db.relatedOneOrNone(target, relation)
```

Forward fetches return the target model or `Option[target]`. Reverse `related`
returns a normal `QuerySet[source]`.

## Transactions

```nim
db.transaction:
  discard db.insert(first)
  discard db.insert(second)
```

The outer block uses a transaction. Nested blocks use savepoints. A
`CatchableError` rolls back the current level and is re-raised. Low-level
`beginTransaction`, `commitTransaction`, and `rollbackTransaction` are also
public.

## Validation

```nim
proc validate[T](value: T): seq[ValidationIssue]
```

Each issue contains `field`, `code`, and `message`. Validation is explicit and
does not persist data.

## Schema snapshots and migrations

```nim
schemaSnapshot(ModelA, ModelB)
snapshot.saveSnapshot(path)
loadSnapshot(path)
diffSchemas(previous, current, migrationName, dependency = "")
migration.saveMigration(path)
loadMigration(path)
db.applyMigration(migration,
  allowDestructive = false,
  allowReview = false)
migration.sqlMigration(backend)
```

See [migrations](migrations.md) and the [CLI reference](cli-reference.md) before
enabling either safety override.

## Query logging

```nim
db.enableQueryLogging(proc(sql: string; params: seq[DbValue]) =
  echo sql, " parameters=", params.len
)
db.disableQueryLogging()
```

The callback receives redacted copies of sensitive parameters. It must not
mutate connection state recursively or expose ordinary parameters that may
still contain application data.

## Exception hierarchy

| Exception | Meaning |
| --- | --- |
| `OrmError` | Base for library runtime failures |
| `ConnectionError` | Backend unavailable, closed, or not enabled |
| `SqlExecutionError` | SQL execution failed |
| `ConstraintViolation` | Database constraint failed |
| `UniqueViolation` | UNIQUE or primary-key conflict |
| `ForeignKeyViolation` | Referenced row missing or protected |
| `NotNullViolation` | Required column received NULL |
| `RecordNotFound` | Required single row was absent |
| `MultipleRecordsFound` | Query expected one row but found more |
| `SerializationError` | Native value and database value disagree |
| `TransactionError` | Invalid transaction state |
| `MigrationError` | Migration dependency, safety, or dialect failure |
