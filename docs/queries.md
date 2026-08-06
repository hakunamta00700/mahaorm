# CRUD and typed queries

## Record operations

```nim
var post = db.insert(Post(title: "Nim"))
post.title = "Nim ORM"
discard db.update(post)

let same = db.get(Post, post.id)
let optional = db.getOrNone(Post, 999'i64)
discard db.delete(same)
```

`insert` returns a copy with its generated primary key. `update` mutates the
passed variable when automatic timestamp fields are present and returns the
affected row count. Missing `get` calls raise `RecordNotFound`.

## Manager and QuerySet

`Model.objects(db)` returns a stateless `Manager[T]`. The manager creates a
fresh immutable `QuerySet[T]` for each operation, so filters and pagination do
not leak between calls.

```nim
let posts = Post.objects(db)
let saved = posts.create(Post(title: "Nim"))
let same = posts.get(saved.id)
let optional = posts.getOrNone(999)
```

The `it` symbol injected into `filter`, `exclude`, `orderBy`, and `update` exposes
compile-time typed field references. Comparing a numeric field with a string or
using an unknown field fails during compilation.

```nim
let query = Post.objects(db)
  .filter:
    (it.title.contains("Nim") and it.views >= 10) or
      it.published == true

let withoutDrafts = query.exclude(it.title.startsWith("Draft:"))

let posts = query
  .orderBy(it.views.desc)
  .limit(20)
  .offset(0)
  .all()
```

Model `meta.ordering` is applied whenever a manager creates a query set.
`reverse` flips that ordering, `distinct` emits `SELECT DISTINCT`, and `none`
returns an empty query set without a database special case in application code.

Supported predicates are `==`, `!=`, `<`, `<=`, `>`, `>=`, `between`,
`inList`, `contains`, `startsWith`, `endsWith`, `isNull`, and `isNotNull`.
Predicates combine with `and`, `or`, and `not`.

Terminal APIs are `all`, `first`, `firstOrNone`, `last`, `lastOrNone`, `get`,
`getOrNone`, `count`, `exists`, `contains`, `delete`, and `update`. Query `get`
requires exactly one result and raises `MultipleRecordsFound` when two or more
rows match. `get(primaryKey)` and `getOrNone(primaryKey)` add a typed
primary-key condition to the current query.

```nim
discard Post.objects(db)
  .filter(it.views == 0)
  .update([
    it.views.set(1),
    it.published.set(true)
  ])

discard Post.objects(db).filter(it.published == false).delete()
```

The manager intentionally has no direct `delete` method. Select the deletion
scope with `filter`; Nim's `all()` materializes a sequence and therefore cannot
be followed by `delete()`. Use `getQuerySet().delete()` only when deleting the
complete table is deliberate. Updating or deleting a sliced query raises
`ValueError`; silently ignoring `limit` or `offset` would widen the write.

Unlike Django's lazy iterable QuerySet, nimorm uses `all()` as the explicit
execution boundary returning `seq[T]`. Other modifiers remain lazy until a
terminal operation runs.

## SQL inspection and safety

`toSql` returns `CompiledQuery(sql, params)`. Values never appear inside its SQL
text; SQLite uses `?`, while PostgreSQL uses `$1`, `$2`, and so on.

```nim
let compiled = Post.objects(db)
  .filter(it.title.contains("100% Nim"))
  .toSql()
echo compiled.sql
echo compiled.params.len
```

LIKE metacharacters are escaped. Query logging receives SQL and parameters
separately. Fields whose names or column names contain `password`, `token`,
`secret`, or `apiKey` are automatically redacted. Raw calls can mark a value
with `sensitiveDbValue(dbValue(value))`.

Projection, arbitrary aggregation, eager loading, and relation traversal in a
filter are extension points, not supported APIs in `0.1.0`.
