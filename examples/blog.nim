import nimorm

model Author:
  username = stringField(maxLength = 80, unique = true)
  apiToken = stringField(maxLength = 120)

  meta:
    tableName = "authors"

model BlogPost:
  title = stringField(maxLength = 200, minLength = 3)
  body = textField(nullable = true)
  published = booleanField(default = false)
  author = foreignKey(
    Author,
    onDelete = Cascade,
    relatedName = "posts"
  )
  createdAt = dateTimeField(autoNowAdd = true)

  meta:
    tableName = "blog_posts"
    indexes = @[
      @["author", "published"]
    ]

proc main() =
  let db = openSqlite(":memory:")
  defer: db.close()

  db.enableQueryLogging(proc(sql: string; params: seq[DbValue]) =
    echo sql, " parameters=", params.len
  )
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
  discard BlogPost.objects(db)
    .filter(it.id == draft.id)
    .update(it.published.set(true))

  let published = BlogPost.objects(db)
    .filter(it.published == true and it.title.contains("ORM"))
    .orderBy(it.createdAt.desc)
    .all()

  let owner = db.fetchRelated(published[0], relations(BlogPost).author)
  echo owner.username, " wrote ", published[0].title

when isMainModule:
  main()
