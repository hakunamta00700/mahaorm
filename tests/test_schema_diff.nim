import std/[json, os, strutils, tempfiles, unittest]

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

model RelationTargetSnapshot:
  name = stringField(maxLength = 80)

  meta:
    tableName = "relation_targets"

model RelationSourceV1:
  name = stringField(maxLength = 80)

  meta:
    tableName = "relation_sources"

model RelationSourceV2:
  name = stringField(maxLength = 80)
  target = foreignKey(RelationTargetSnapshot, onDelete = Cascade)

  meta:
    tableName = "relation_sources"

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

    let (tempFile, path) = createTempFile(
      "nimorm-schema-snapshot-", ".json")
    tempFile.close()
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

  test "adds the foreign-key constraint for a new relation field":
    var previous = schemaSnapshot(RelationTargetSnapshot, RelationSourceV1)
    var current = schemaSnapshot(RelationTargetSnapshot, RelationSourceV2)
    previous.models[1].modelName = "RelationSource"
    current.models[1].modelName = "RelationSource"

    let migration = diffSchemas(previous, current, "0002_add_target")
    check migration.hasOperation(AddColumn, "target")
    check migration.hasOperation(AddForeignKey, "target")
    let postgresSql = migration.sqlMigration(postgresBackend)
    check "ADD COLUMN \"target_id\"" in postgresSql
    check "ADD CONSTRAINT \"fk_relation_sources_target_id\"" in postgresSql
    expect MigrationError:
      discard migration.sqlMigration(sqliteBackend)

  test "orders related table creation and removal by dependency":
    let empty = SchemaSnapshot(formatVersion: 1)
    let related = schemaSnapshot(RelationSourceV2, RelationTargetSnapshot)

    let createMigration = diffSchemas(empty, related, "0001_related")
    check createMigration.operations[0].tableName == "relation_targets"
    check createMigration.operations[1].tableName == "relation_sources"

    let dropMigration = diffSchemas(related, empty, "0002_drop_related")
    check dropMigration.operations[0].tableName == "relation_sources"
    check dropMigration.operations[1].tableName == "relation_targets"

  test "rejects unsupported constraint changes and diffs field indexes":
    var previous = schemaSnapshot(SnapshotV1)
    var unsupported = previous
    unsupported.models[0].fields[1].unique = true
    expect MigrationError:
      discard diffSchemas(previous, unsupported, "0002_unique")

    var indexed = previous
    indexed.models[0].fields[1].indexed = true
    let addIndex = diffSchemas(previous, indexed, "0002_index")
    check addIndex.hasOperation(CreateIndex, "title")

    let dropIndex = diffSchemas(indexed, previous, "0003_index")
    check dropIndex.hasOperation(DropIndex, "title")
