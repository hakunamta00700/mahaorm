# 5-minute quickstart

This page creates an in-memory SQLite database, writes two native Nim objects,
and reads one back through a typed query. No database server or configuration is
required.

## 1. Define a model

```nim
import nimorm

model QuickPost:
  title = stringField(maxLength = 200, minLength = 3)
  published = booleanField(default = false)

  meta:
    tableName = "quick_posts"
```

The macro generates a normal object with `id: int64`, `title: string`, and
`published: bool`. Invalid field options and incompatible query values fail at
compile time.

## 2. Open SQLite and insert rows

```nim
let db = openSqlite(":memory:")
db.createTables(QuickPost)

let first = db.insert(QuickPost(title: "Learning nimorm"))
discard db.insert(QuickPost(title: "Already published", published: true))
```

`insert` returns a copy containing the generated ID. `createTables` is useful
for examples and tests; use [migrations](migrations.md) when schema changes must
preserve data.

## 3. Run a typed query

```nim
let drafts = QuickPost.objects(db)
  .filter(it.published == false and it.title.contains("nimorm"))
  .orderBy(it.id.asc)
  .all()

echo first.id
echo drafts[0].title
db.close()
```

The query sends values as bound parameters. The title value never becomes part
of the SQL string.

## Run the complete example

The complete program is [`examples/quickstart.nim`](../examples/quickstart.nim):

```shell
nim c -r --path:src examples/quickstart.nim
```

Expected output:

```text
1
Learning nimorm
```

Next, [build a small blog](tutorial.md) to use validation, relations, updates,
and query logging.
