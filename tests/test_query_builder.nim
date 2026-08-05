import std/[options, strutils, unittest]

import nimorm

model QueryPost:
  title = stringField(maxLength = 200)
  body = textField(nullable = true)
  views = integerField(default = 0)
  published = booleanField(default = false)

  meta:
    tableName = "query_posts"

static:
  doAssert not compiles(nimOrmFields(QueryPost).views == "wrong type")
  doAssert not compiles(nimOrmFields(QueryPost).missing == 1)

suite "typed query builder":
  test "filters, orders, limits, and offsets with native field types":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(QueryPost)
    discard db.insert(QueryPost(title: "Nim ORM", views: 10, published: true))
    discard db.insert(QueryPost(title: "Nim macros", views: 20))
    discard db.insert(QueryPost(title: "Other", views: 30))

    let filtered = QueryPost.objects(db)
      .filter:
        it.title.contains("Nim") and it.views >= 10
    let ordered = filtered
      .orderBy:
        it.views.desc
    let posts = ordered
      .limit(10)
      .offset(0)
      .all()

    check posts.len == 2
    check posts[0].title == "Nim macros"
    check posts[1].title == "Nim ORM"

  test "supports all comparison and predicate operators":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(QueryPost)
    discard db.insert(QueryPost(title: "alpha", views: 1))
    discard db.insert(QueryPost(title: "alphabet", views: 2, body: some("text")))
    discard db.insert(QueryPost(title: "omega", views: 3))

    check QueryPost.objects(db).filter(it.views > 0 and it.views <= 3).count() == 3
    check QueryPost.objects(db).filter(it.views != 2).count() == 2
    check QueryPost.objects(db).filter(it.views.between(1, 2)).count() == 2
    check QueryPost.objects(db).filter(it.views.inList([1, 3])).count() == 2
    check QueryPost.objects(db).filter(it.title.startsWith("alph")).count() == 2
    check QueryPost.objects(db).filter(it.title.endsWith("bet")).count() == 1
    check QueryPost.objects(db).filter(it.body.isNull()).count() == 2
    check QueryPost.objects(db).filter(it.body.isNotNull()).count() == 1
    check QueryPost.objects(db).filter(not (it.views == 2)).count() == 2
    check QueryPost.objects(db).filter(
      (it.title == "alpha") or (it.title == "omega")).count() == 2

  test "implements result cardinality APIs without loading extra rows":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(QueryPost)
    let firstPost = db.insert(QueryPost(title: "first"))
    discard db.insert(QueryPost(title: "second"))

    check QueryPost.objects(db).filter(it.id == firstPost.id).get().title == "first"
    check QueryPost.objects(db).filter(it.title == "missing").firstOrNone().isNone
    check QueryPost.objects(db).exists()
    expect MultipleRecordsFound:
      discard QueryPost.objects(db).get()

  test "compiles placeholders separately from hostile values":
    let db = openSqlite(":memory:")
    defer: db.close()
    let hostile = "x%' OR 1=1 --"
    let query = QueryPost.objects(db).filter(it.title.contains(hostile))
    let compiled = query.toSql()
    check hostile notin compiled.sql
    check "LIKE ?" in compiled.sql
    check compiled.params.len == 1

  test "bulk updates and deletes selected rows":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(QueryPost)
    discard db.insert(QueryPost(title: "one", views: 1))
    discard db.insert(QueryPost(title: "two", views: 2))
    check QueryPost.objects(db)
      .filter(it.views >= 2)
      .update(it.published.set(true)) == 1
    check QueryPost.objects(db).filter(it.published == true).count() == 1
    check QueryPost.objects(db).filter(it.views < 2).delete() == 1
    check QueryPost.objects(db).count() == 1
