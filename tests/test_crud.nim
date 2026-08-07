import std/[json, options, times, unittest]

import nimorm

model Article:
  title = stringField(maxLength = 200, unique = true)
  body = textField(nullable = true)
  views = integerField(default = 7)
  rating = floatField(default = 0.5)
  active = booleanField(default = true)
  price = decimalField(precision = 12, scale = 2, default = "12.50")
  publishedOn = dateField(nullable = true)
  publishedAt = dateTimeField(nullable = true)
  config = jsonField(nullable = true)
  rawData = binaryField(nullable = true)
  createdAt = dateTimeField(autoNowAdd = true)
  updatedAt = dateTimeField(autoNow = true)

  meta:
    tableName = "articles"

model ManualKeyRecord:
  key = stringField(maxLength = 40, primaryKey = true)
  label = stringField(maxLength = 100)

  meta:
    tableName = "manual_key_records"
    autoPrimaryKey = false

suite "SQLite model CRUD":
  test "persists explicit non-generated primary keys":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(ManualKeyRecord)

    var saved = db.insert(ManualKeyRecord(key: "manual-1", label: "first"))
    check saved.key == "manual-1"
    check db.get(ManualKeyRecord, "manual-1").label == "first"
    saved.label = "updated"
    check db.update(saved) == 1
    check db.get(ManualKeyRecord, "manual-1").label == "updated"
    check db.delete(saved) == 1

  test "round-trips native model fields and generated ID":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(Article)

    let publishTime = now()
    let saved = db.insert(Article(
      title: "Nim ORM",
      body: some("body"),
      publishedOn: some(date(2026, 8, 6)),
      publishedAt: some(publishTime),
      config: some(%*{"language": "nim"}),
      rawData: some(@[byte 0, 127, 255])
    ))

    check saved.id == 1
    check saved.views == 7
    check saved.rating == 0.5
    check saved.active
    check $saved.price == "12.50"
    check saved.createdAt.year > 2000
    check saved.updatedAt.year > 2000

    let loaded = db.get(Article, saved.id)
    check loaded.id == saved.id
    check loaded.title == "Nim ORM"
    check loaded.body == some("body")
    check loaded.views == 7
    check loaded.publishedOn == some(date(2026, 8, 6))
    check loaded.publishedAt.isSome
    check loaded.config.get["language"].getStr == "nim"
    check loaded.rawData == some(@[byte 0, 127, 255])

  test "updates, deletes, and distinguishes missing rows":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(Article)
    var saved = db.insert(Article(title: "before"))
    saved.title = "after"
    saved.views = 10
    check db.update(saved) == 1
    check db.get(Article, saved.id).title == "after"
    check db.delete(saved) == 1
    check db.getOrNone(Article, saved.id).isNone
    expect RecordNotFound:
      discard db.get(Article, saved.id)

  test "rolls back outer and nested transactions":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(Article)

    expect ValueError:
      db.transaction:
        discard db.insert(Article(title: "rolled back"))
        raise newException(ValueError, "stop")
    check db.queryRows("SELECT COUNT(*) FROM \"articles\"")[0][0].integerValue == 0

    db.transaction:
      discard db.insert(Article(title: "outer"))
      try:
        db.transaction:
          discard db.insert(Article(title: "inner"))
          raise newException(ValueError, "rollback savepoint")
      except ValueError:
        discard
    let titles = db.queryRows("SELECT \"title\" FROM \"articles\" ORDER BY \"id\"")
    check titles.len == 1
    check titles[0][0].textValue == "outer"

  test "rolls back cleanly when commit fails":
    let db = openSqlite(":memory:")
    defer: db.close()
    discard db.execute(
      "CREATE TABLE parent(id INTEGER PRIMARY KEY)")
    discard db.execute(
      "CREATE TABLE child(parent_id INTEGER, " &
      "FOREIGN KEY(parent_id) REFERENCES parent(id) " &
      "DEFERRABLE INITIALLY DEFERRED)")

    expect ForeignKeyViolation:
      db.transaction:
        discard db.execute("INSERT INTO child(parent_id) VALUES (?)", [dbValue(99)])
    check db.transactionDepth == 0
    check db.queryRows("SELECT COUNT(*) FROM child")[0][0].integerValue == 0
