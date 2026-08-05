import std/unittest

import nimorm

model Entry:
  key = stringField(maxLength = 50, unique = true)
  value = textField(nullable = true)
  payload = binaryField(nullable = true)

  meta:
    tableName = "entries"

suite "SQLite backend":
  test "creates model tables and preserves typed parameters":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(Entry)

    let hostile = "Robert'); DROP TABLE entries;--"
    check db.execute(
      "INSERT INTO \"entries\" (\"key\", \"value\", \"payload\") VALUES (?, ?, ?)",
      [dbValue(hostile), dbNull(), dbValue(@[byte 0, 1, 255])]) == 1

    let rows = db.queryRows(
      "SELECT \"key\", \"value\", \"payload\" FROM \"entries\"")
    check rows.len == 1
    check rows[0][0].kind == dvText
    check rows[0][0].textValue == hostile
    check rows[0][1].kind == dvNull
    check rows[0][2].blobValue == @[byte 0, 1, 255]

    let tableRows = db.queryRows(
      "SELECT name FROM sqlite_master WHERE type = ? AND name = ?",
      [dbValue("table"), dbValue("entries")])
    check tableRows.len == 1

  test "returns generated IDs and affected row counts":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(Entry)
    check db.execute(
      "INSERT INTO \"entries\" (\"key\") VALUES (?)", [dbValue("one")]) == 1
    check db.lastInsertId() == 1
    check db.execute(
      "UPDATE \"entries\" SET \"key\" = ? WHERE \"id\" = ?",
      [dbValue("updated"), dbValue(1)]) == 1

  test "classifies constraint failures":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(Entry)
    discard db.execute(
      "INSERT INTO \"entries\" (\"key\") VALUES (?)", [dbValue("same")])
    expect UniqueViolation:
      discard db.execute(
        "INSERT INTO \"entries\" (\"key\") VALUES (?)", [dbValue("same")])

  test "logs SQL separately from bound values":
    let db = openSqlite(":memory:")
    defer: db.close()
    var loggedSql = ""
    var loggedParams: seq[DbValue]
    db.enableQueryLogging(proc(sql: string; params: seq[DbValue]) =
      loggedSql = sql
      loggedParams = params
    )
    discard db.queryRows("SELECT ? AS value", [dbValue("secret")])
    check loggedSql == "SELECT ? AS value"
    check loggedParams[0].textValue == "secret"
