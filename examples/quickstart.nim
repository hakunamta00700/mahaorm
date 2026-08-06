import nimorm

model QuickPost:
  title = stringField(maxLength = 200, minLength = 3)
  published = booleanField(default = false)

  meta:
    tableName = "quick_posts"

proc main() =
  let db = openSqlite(":memory:")
  defer: db.close()
  db.createTables(QuickPost)

  let first = db.insert(QuickPost(title: "Learning nimorm"))
  discard db.insert(QuickPost(
    title: "Already published",
    published: true))

  let drafts = QuickPost.objects(db)
    .filter(it.published == false and it.title.contains("nimorm"))
    .orderBy(it.id.asc)
    .all()

  echo first.id
  echo drafts[0].title

when isMainModule:
  main()
