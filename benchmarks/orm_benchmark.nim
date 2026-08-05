import std/[monotimes, strutils, times]

import nimorm

model BenchItem:
  title = stringField(maxLength = 100)
  score = integerField()

  meta:
    tableName = "bench_items"

template measure(label: string; iterations: int; body: untyped) =
  block:
    let started = getMonoTime()
    body
    let elapsed = getMonoTime() - started
    let totalMs = elapsed.inNanoseconds.float64 / 1_000_000.0
    let operationUs = totalMs * 1_000.0 / iterations.float64
    echo label.alignLeft(32), " ",
      totalMs.formatFloat(ffDecimal, 3).align(10), " ms  ",
      operationUs.formatFloat(ffDecimal, 3).align(10), " us/op"

proc main() =
  const
    objectCount = 100_000
    singleCount = 200
    bulkCount = 1_000
    queryBuildCount = 20_000
    resultSetRuns = 100

  let db = openSqlite(":memory:")
  defer: db.close()
  db.createTables(BenchItem)

  var checksum = 0'i64
  echo "nimorm SQLite in-memory benchmark"
  echo "Nim ", NimVersion, "; release build; rows=", bulkCount

  measure("native object creation", objectCount):
    for index in 0 ..< objectCount:
      let item = BenchItem(title: "item-" & $index, score: index)
      checksum += (item.score mod 7).int64 + item.title.len.int64

  measure("ORM single INSERT", singleCount):
    for index in 0 ..< singleCount:
      let item = db.insert(BenchItem(
        title: "single-" & $index,
        score: index))
      checksum += item.id

  discard BenchItem.objects(db).delete()
  measure("ORM transaction INSERT", bulkCount):
    db.transaction:
      for index in 0 ..< bulkCount:
        let item = db.insert(BenchItem(
          title: "bulk-" & $index,
          score: index))
        checksum += item.id

  let firstId = BenchItem.objects(db).orderBy(it.id.asc).first().id
  measure("ORM primary-key SELECT", singleCount):
    for unused in 0 ..< singleCount:
      let item = db.get(BenchItem, firstId)
      checksum += item.score

  measure("typed query compilation", queryBuildCount):
    for index in 0 ..< queryBuildCount:
      let compiled = BenchItem.objects(db)
      .filter((it.score >= index) and it.title.contains("bulk"))
        .orderBy(it.id.desc)
        .limit(25)
        .toSql()
      checksum += compiled.sql.len.int64 + compiled.params.len.int64

  measure("ORM fetch + row mapping", resultSetRuns * bulkCount):
    for unused in 0 ..< resultSetRuns:
      let items = BenchItem.objects(db).all()
      checksum += items[^1].score

  measure("raw SQLite row fetch", resultSetRuns * bulkCount):
    for unused in 0 ..< resultSetRuns:
      let rows = db.queryRows(
        "SELECT \"id\", \"title\", \"score\" FROM \"bench_items\"")
      checksum += rows[^1][2].integerValue

  echo "checksum=", checksum

when isMainModule:
  main()
