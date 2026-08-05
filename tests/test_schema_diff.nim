import std/[json, os, unittest]

import nimorm

model SnapshotV1:
  title = stringField(maxLength = 200)
  obsolete = textField(nullable = true)

  meta:
    tableName = "articles"
    indexes = @[
      @["title"]
    ]

model SnapshotV2:
  title = stringField(maxLength = 100, columnName = "headline")
  summary = textField(nullable = true)

  meta:
    tableName = "published_articles"
    uniqueTogether = @[
      @["title", "summary"]
    ]

proc hasOperation(migration: Migration;
                  kind: MigrationOperationKind;
                  fieldName = ""): bool =
  for operation in migration.operations:
    if operation.kind == kind and
        (fieldName.len == 0 or operation.fieldName == fieldName):
      return true

suite "schema snapshots and diffs":
  test "round-trips versioned JSON snapshots":
    let snapshot = schemaSnapshot(SnapshotV1)
    check snapshot.formatVersion == 1
    check snapshot.models[0].fields[0].name == "id"
    let restored = schemaSnapshotFromJson(snapshot.toJson)
    check restored.models[0].tableName == "articles"
    check restored.models[0].fields.len == snapshot.models[0].fields.len

    let path = getTempDir() / "nimorm-schema-snapshot-test.json"
    defer:
      if fileExists(path):
        removeFile(path)
    snapshot.saveSnapshot(path)
    check loadSnapshot(path).models[0].modelName == "SnapshotV1"

  test "classifies additions, removals, renames and unsafe alterations":
    var previous = schemaSnapshot(SnapshotV1)
    var current = schemaSnapshot(SnapshotV2)
    previous.models[0].modelName = "Article"
    current.models[0].modelName = "Article"

    let migration = diffSchemas(previous, current, "0002_article")
    check migration.hasOperation(RenameTable)
    check migration.hasOperation(RenameColumn, "title")
    check migration.hasOperation(AlterColumn, "title")
    check migration.hasOperation(DropColumn, "obsolete")
    check migration.hasOperation(AddColumn, "summary")
    check migration.hasOperation(DropIndex)
    check migration.hasOperation(AddUniqueConstraint)

    var unsafeCount = 0
    for operation in migration.operations:
      if operation.destructive or operation.requiresReview:
        inc unsafeCount
    check unsafeCount >= 2

  test "creates and drops complete model tables explicitly":
    let empty = SchemaSnapshot(formatVersion: 1)
    var current = schemaSnapshot(SnapshotV1)
    current.models[0].modelName = "Article"
    let createMigration = diffSchemas(empty, current, "0001_initial")
    check createMigration.operations.len == 1
    check createMigration.operations[0].kind == CreateTable

    let dropMigration = diffSchemas(current, empty, "0002_drop")
    check dropMigration.operations.len == 1
    check dropMigration.operations[0].kind == DropTable
    check dropMigration.operations[0].destructive
