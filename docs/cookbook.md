# Cookbook

Short patterns for common application work. Each example assumes a model and an
open `db: Database`.

## Use a transaction

```nim
db.transaction:
  let user = db.insert(User(username: "ada"))
  discard db.insert(Profile(userId: user.id, bio: "compiler pioneer"))
```

Any `CatchableError` rolls the block back. Nested `transaction` blocks use
savepoints, so an inner failure can be handled without corrupting transaction
depth.

## Paginate deterministically

```nim
let pageSize = 25
let pageNumber = 3
let posts = Post.objects(db)
  .orderBy(it.id.asc)
  .limit(pageSize)
  .offset((pageNumber - 1) * pageSize)
  .all()
```

Always specify ordering. Offset pagination without a stable order can return
different rows as data changes.

## Distinguish missing and duplicate rows

```nim
let maybeUser = User.objects(db)
  .filter(it.username == "ada")
  .firstOrNone()

let exactlyOne = User.objects(db)
  .filter(it.username == "ada")
  .get()
```

`firstOrNone` accepts zero or more matches and reads at most one. Query `get`
raises `RecordNotFound` for zero and `MultipleRecordsFound` for more than one.

## Bulk update or delete a selection

```nim
discard Post.objects(db)
  .filter(it.views < 10)
  .update([
    it.published.set(false),
    it.views.set(0)
  ])

discard Post.objects(db)
  .filter(it.title == "temporary")
  .delete()
```

Both operations return the affected-row count.

## Inspect generated SQL

```nim
let compiled = Post.objects(db)
  .filter(it.title.contains("Nim"))
  .toSql()

echo compiled.sql
echo compiled.params.len
```

Use this when debugging or explaining a query plan. Runtime values stay in
`compiled.params`.

## Log without exposing secrets

```nim
db.enableQueryLogging(proc(sql: string; params: seq[DbValue]) =
  echo sql, " values=", params.len
)

discard db.execute(
  "SELECT ?",
  [sensitiveDbValue(dbValue("manual-secret"))])
```

Model fields containing `password`, `token`, `secret`, or `apiKey` are marked
automatically. The callback still receives non-sensitive parameter values, so
avoid dumping the full sequence in production.

## Test against an isolated database

```nim
let db = openSqlite(":memory:")
defer: db.close()
db.createTables(User, Post)
```

Each in-memory connection owns a separate database. Keep the same connection
open for the duration of a test.

## Fetch a nullable relation

```nim
let reviewer = db.fetchRelatedOrNone(post, relations(Post).reviewer)
if reviewer.isSome:
  echo reviewer.get.username
```

Use `fetchRelated` only when an absent relation should be a runtime error.

## Generate a snapshot programmatically

```nim
let current = schemaSnapshot(User, Post)
current.saveSnapshot("schema/current.json")
```

Import every model module explicitly. Version `0.1.0` does not discover models
from the filesystem or runtime type registry.
