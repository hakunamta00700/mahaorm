import std/[json, os, strutils]

import ../schema/snapshot
import ./operations

proc toJson*(operation: MigrationOperation): JsonNode =
  %*{
    "kind": $operation.kind,
    "modelName": operation.modelName,
    "tableName": operation.tableName,
    "previousTableName": operation.previousTableName,
    "fieldName": operation.fieldName,
    "previousColumnName": operation.previousColumnName,
    "field": operation.field.toJson,
    "fields": operation.fields,
    "model": operation.model.toJson,
    "destructive": operation.destructive,
    "requiresReview": operation.requiresReview,
    "reason": operation.reason
  }

proc operationFromJson*(node: JsonNode): MigrationOperation =
  result = MigrationOperation(
    kind: parseEnum[MigrationOperationKind](node["kind"].getStr),
    modelName: node["modelName"].getStr,
    tableName: node["tableName"].getStr,
    previousTableName: node["previousTableName"].getStr,
    fieldName: node["fieldName"].getStr,
    previousColumnName: node["previousColumnName"].getStr,
    field: fieldSnapshotFromJson(node["field"]),
    model: modelSnapshotFromJson(node["model"]),
    destructive: node["destructive"].getBool,
    requiresReview: node["requiresReview"].getBool,
    reason: node["reason"].getStr)
  for value in node["fields"]:
    result.fields.add(value.getStr)

proc toJson*(migration: Migration): JsonNode =
  var operations = newJArray()
  for operation in migration.operations:
    operations.add(operation.toJson)
  %*{
    "name": migration.name,
    "dependency": migration.dependency,
    "operations": operations
  }

proc migrationFromJson*(node: JsonNode): Migration =
  result = Migration(
    name: node["name"].getStr,
    dependency: node["dependency"].getStr)
  for operation in node["operations"]:
    result.operations.add(operationFromJson(operation))

proc saveMigration*(migration: Migration; path: string) =
  let parent = path.parentDir
  if parent.len > 0:
    createDir(parent)
  writeFile(path, migration.toJson.pretty)

proc loadMigration*(path: string): Migration =
  migrationFromJson(parseFile(path))
