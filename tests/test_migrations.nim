import std/[os, strutils, tempfiles, unittest]

import nimorm

model MigratedItem:
  name = stringField(maxLength = 100)

  meta:
    tableName = "migrated_items"

suite "migration execution and history":
  test "applies initial migrations once and records history atomically":
    let db = openSqlite(":memory:")
    defer: db.close()
    let empty = SchemaSnapshot(formatVersion: 1)
    var current = schemaSnapshot(MigratedItem)
    current.models[0].modelName = "Item"
    let migration = diffSchemas(empty, current, "0001_initial")

    check db.applyMigration(migration)
    check not db.applyMigration(migration)
    check db.appliedMigrations() == @["0001_initial"]
    check db.queryRows(
      "SELECT name FROM sqlite_master WHERE type = ? AND name = ?",
      [dbValue("table"), dbValue("migrated_items")]).len == 1

  test "checks dependencies before executing operations":
    let db = openSqlite(":memory:")
    defer: db.close()
    let migration = Migration(
      name: "0002_missing_dependency",
      dependency: "0001_missing")
    expect MigrationError:
      discard db.applyMigration(migration)
    check not db.isMigrationApplied(migration.name)

  test "refuses destructive operations unless explicitly authorized":
    let db = openSqlite(":memory:")
    defer: db.close()
    let empty = SchemaSnapshot(formatVersion: 1)
    var current = schemaSnapshot(MigratedItem)
    current.models[0].modelName = "Item"
    let create = diffSchemas(empty, current, "0001_initial")
    discard db.applyMigration(create)
    let drop = diffSchemas(current, empty, "0002_drop", "0001_initial")

    expect MigrationError:
      discard db.applyMigration(drop)
    check db.applyMigration(drop, allowDestructive = true)
    check db.appliedMigrations() == @["0001_initial", "0002_drop"]

  test "persists migration files and emits reviewable SQL":
    let empty = SchemaSnapshot(formatVersion: 1)
    var current = schemaSnapshot(MigratedItem)
    current.models[0].modelName = "Item"
    let migration = diffSchemas(empty, current, "0001_initial")
    let (tempFile, path) = createTempFile("nimorm-migration-", ".json")
    tempFile.close()
    defer:
      if fileExists(path):
        removeFile(path)
    migration.saveMigration(path)
    let restored = loadMigration(path)
    check restored.name == "0001_initial"
    check restored.operations[0].kind == CreateTable
    let sqlText = restored.sqlMigration(sqliteBackend)
    check "CREATE TABLE \"migrated_items\"" in sqlText
    check sqlText.endsWith(";")

  test "preflights review gates and rolls back failed operation batches":
    let db = openSqlite(":memory:")
    defer: db.close()
    let reviewMigration = Migration(
      name: "0001_review",
      operations: @[
        MigrationOperation(
          kind: AddColumn,
          modelName: "Item",
          tableName: "items",
          requiresReview: true,
          reason: "required data backfill")
      ])
    expect MigrationError:
      discard db.applyMigration(reviewMigration)
    check not db.isMigrationApplied(reviewMigration.name)

    let model = schemaSnapshot(MigratedItem).models[0]
    let failedBatch = Migration(
      name: "0002_atomic",
      operations: @[
        MigrationOperation(
          kind: CreateTable,
          modelName: model.modelName,
          tableName: model.tableName,
          model: model),
        MigrationOperation(
          kind: AddColumn,
          modelName: "Missing",
          tableName: "missing_table",
          fieldName: "optional",
          field: FieldSnapshot(
            name: "optional",
            storageName: "optional",
            columnName: "optional",
            kind: fkText,
            nullable: true))
      ])
    expect SqlExecutionError:
      discard db.applyMigration(failedBatch)
    check db.queryRows(
      "SELECT name FROM sqlite_master WHERE type = ? AND name = ?",
      [dbValue("table"), dbValue("migrated_items")]).len == 0
    check not db.isMigrationApplied(failedBatch.name)
