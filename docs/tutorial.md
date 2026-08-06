# Tutorial: build a small blog

This tutorial extends the quickstart into two related models. The final program
is [`examples/blog.nim`](../examples/blog.nim) and is executed by
`nimble example`.

## 1. Define the author

```nim
model Author:
  username = stringField(maxLength = 80, unique = true)
  apiToken = stringField(maxLength = 120)

  meta:
    tableName = "authors"
```

`apiToken` is treated as sensitive because its name contains `token`. Its real
value is bound to the database, while query log callbacks receive `***`.

## 2. Define a related post

```nim
model BlogPost:
  title = stringField(maxLength = 200, minLength = 3)
  body = textField(nullable = true)
  published = booleanField(default = false)
  author = foreignKey(Author, onDelete = Cascade, relatedName = "posts")
  createdAt = dateTimeField(autoNowAdd = true)

  meta:
    tableName = "blog_posts"
```

The generated `BlogPost` stores `authorId: int64`. There is no hidden lazy
object or implicit database query.

## 3. Create and validate values

```nim
let db = openSqlite(":memory:")
db.createTables(Author, BlogPost)

let author = db.insert(Author(
  username: "nim-user",
  apiToken: "kept-out-of-query-logs"))

var draft = BlogPost(
  title: "Compile-time ORM",
  body: some("Native Nim types, parameterized SQL."),
  authorId: author.id)

let issues = draft.validate()
if issues.len > 0:
  raise newException(ValueError, issues[0].message)
draft = db.insert(draft)
```

Validation is explicit. Database constraints still enforce NOT NULL, UNIQUE,
and foreign-key integrity if validation is skipped.

## 4. Update and query

```nim
discard BlogPost.objects(db)
  .filter(it.id == draft.id)
  .update(it.published.set(true))

let published = BlogPost.objects(db)
  .filter(it.published == true and it.title.contains("ORM"))
  .orderBy(it.createdAt.desc)
  .all()
```

Field references carry their native Nim types. `it.published == "yes"` does not
compile.

## 5. Fetch the relation

```nim
let owner = db.fetchRelated(published[0], relations(BlogPost).author)
echo owner.username, " wrote ", published[0].title
db.close()
```

The relation read is explicit, so code review can see where the database query
happens. Continue with the focused [query](queries.md),
[relation](relations.md), and [migration](migrations.md) guides.
