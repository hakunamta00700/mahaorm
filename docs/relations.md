# Relations

`foreignKey` and `oneToOneField` take a target model and a required `onDelete`
policy. The generated model stores only the target ID as a native value.

```nim
model User:
  name = stringField(maxLength = 100)

model Post:
  title = stringField(maxLength = 200)
  author = foreignKey(
    User,
    onDelete = Cascade,
    relatedName = "posts")
  reviewer = foreignKey(
    User,
    onDelete = SetNull,
    nullable = true,
    relatedName = "reviewedPosts")
```

This emits `authorId: int64` and `reviewerId: Option[int64]`. A one-to-one
field also adds a UNIQUE constraint. Supported policies are `Cascade`,
`Restrict`, `SetNull`, `SetDefault`, and `NoAction`; invalid combinations such
as non-null `SetNull` fail at compile time.

## Forward and reverse access

```nim
let author = db.fetchRelated(post, relations(Post).author)
let reviewer = db.fetchRelatedOrNone(post, relations(Post).reviewer)

let authoredPosts = db.related(author, relations(Post).author)
  .orderBy(it.id.asc)
  .all()
```

`fetchRelated` raises when a nullable relation has no target.
`fetchRelatedOrNone` returns an `Option`. Reverse `related` returns a normal
typed `QuerySet`, so all filtering and terminal operations remain available.

For one-to-one relations, `relatedOneOrNone` returns at most one source record:

```nim
let profile = db.relatedOneOrNone(user, relations(Profile).user)
```

There is no lazy proxy hidden in a model value and no implicit database query.
Each relation fetch is explicit. `selectRelated`/`prefetchRelated` batching and
multi-hop query traversal are not implemented in `0.1.0`.
