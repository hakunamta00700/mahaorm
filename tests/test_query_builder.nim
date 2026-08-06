import std/[options, sequtils, strutils, unittest]

import nimorm

model QueryPost:
  title = stringField(maxLength = 200)
  body = textField(nullable = true)
  views = integerField(default = 0)
  published = booleanField(default = false)

  meta:
    tableName = "query_posts"

model OrderedQueryPost:
  title = stringField(maxLength = 200)
  views = integerField(default = 0)

  meta:
    tableName = "ordered_query_posts"
    ordering = @["-views", "title"]

static:
  doAssert not compiles(nimOrmFields(QueryPost).views == "wrong type")
  doAssert not compiles(nimOrmFields(QueryPost).missing == 1)
  doAssert not compiles(block:
    proc deleteEverything(manager: Manager[QueryPost]) =
      discard manager.delete())

suite "typed query builder":
  test "exposes standard query operations through the model manager":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(QueryPost)

    let posts = QueryPost.objects(db)
    let saved = posts.create(QueryPost(title: "created", views: 1))

    check saved.id > 0
    check posts.count() == 1
    check posts.get(saved.id).title == "created"
    check posts.getOrNone(999).isNone
    check posts.filter(it.id == saved.id).get().title == "created"
    check posts.exclude(it.id == saved.id).none().all().len == 0
    check posts.contains(saved)

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
    check QueryPost.objects(db).filter(it.title == "missing").getOrNone().isNone
    check QueryPost.objects(db).exists()
    expect MultipleRecordsFound:
      discard QueryPost.objects(db).get()

  test "applies model ordering and supports reverse and last":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(OrderedQueryPost)
    discard OrderedQueryPost.objects(db).create(
      OrderedQueryPost(title: "beta", views: 10))
    discard OrderedQueryPost.objects(db).create(
      OrderedQueryPost(title: "alpha", views: 20))
    discard OrderedQueryPost.objects(db).create(
      OrderedQueryPost(title: "alpha", views: 10))

    let ordered = OrderedQueryPost.objects(db).all()
    let baseQuery = OrderedQueryPost.objects(db).getQuerySet()
    let reversedQuery = baseQuery.reverse()
    check ordered.mapIt(it.title) == @["alpha", "alpha", "beta"]
    check ordered.mapIt(it.views) == @[20, 10, 10]
    check baseQuery.first().views == 20
    check reversedQuery.first().title == "beta"
    check OrderedQueryPost.objects(db).first().views == 20
    check OrderedQueryPost.objects(db).last().title == "beta"
    check OrderedQueryPost.objects(db).reverse().first().title == "beta"
    check OrderedQueryPost.objects(db).orderBy(it.title.desc).first().title == "beta"

  test "count and exists preserve queryset limits and offsets":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(QueryPost)
    discard QueryPost.objects(db).create(QueryPost(title: "one"))
    discard QueryPost.objects(db).create(QueryPost(title: "two"))
    discard QueryPost.objects(db).create(QueryPost(title: "three"))

    let page = QueryPost.objects(db).orderBy(it.id.asc).limit(1).offset(1)
    check page.count() == 1
    check page.exists()
    check QueryPost.objects(db).limit(0).count() == 0
    check not QueryPost.objects(db).limit(0).exists()

  test "empty and sliced querysets keep writes scoped safely":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(QueryPost)
    discard QueryPost.objects(db).create(QueryPost(title: "one"))
    discard QueryPost.objects(db).create(QueryPost(title: "two"))

    check QueryPost.objects(db).none().update(it.published.set(true)) == 0
    check QueryPost.objects(db).none().delete() == 0
    check QueryPost.objects(db).count() == 2
    expect ValueError:
      discard QueryPost.objects(db).limit(1).update(it.published.set(true))
    expect ValueError:
      discard QueryPost.objects(db).limit(1).delete()

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
