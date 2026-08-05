import std/[json, macros, os, strutils]

import ../field_defs
import ../metadata

type
  FieldSnapshot* = object
    name*: string
    storageName*: string
    columnName*: string
    kind*: FieldKind
    nullable*: bool
    primaryKey*: bool
    unique*: bool
    indexed*: bool
    maxLength*: int
    precision*: int
    scale*: int
    autoIncrement*: bool
    hasDefault*: bool
    defaultValue*: string
    dbDefault*: string
    relationTarget*: string
    relationTable*: string
    relatedName*: string
    onDelete*: OnDeleteAction

  ModelSnapshot* = object
    modelName*: string
    tableName*: string
    fields*: seq[FieldSnapshot]
    uniqueTogether*: seq[seq[string]]
    indexes*: seq[seq[string]]
    managed*: bool

  SchemaSnapshot* = object
    formatVersion*: int
    models*: seq[ModelSnapshot]

proc fieldSnapshot*(field: FieldMeta): FieldSnapshot =
  FieldSnapshot(
    name: field.name,
    storageName: field.storageName,
    columnName: field.columnName,
    kind: field.kind,
    nullable: field.nullable,
    primaryKey: field.primaryKey,
    unique: field.unique,
    indexed: field.indexed,
    maxLength: field.maxLength,
    precision: field.precision,
    scale: field.scale,
    autoIncrement: field.autoIncrement,
    hasDefault: field.hasDefault,
    defaultValue: field.defaultValue,
    dbDefault: field.dbDefault,
    relationTarget: field.relationTarget,
    relationTable: field.relationTable,
    relatedName: field.relatedName,
    onDelete: field.onDelete)

proc modelSnapshot*(meta: ModelMeta): ModelSnapshot =
  result = ModelSnapshot(
    modelName: meta.modelName,
    tableName: meta.tableName,
    uniqueTogether: meta.uniqueTogether,
    indexes: meta.indexes,
    managed: meta.managed)
  for field in meta.fields:
    result.fields.add(fieldSnapshot(field))

proc schemaSnapshotFromMeta*(metas: openArray[ModelMeta]): SchemaSnapshot =
  result.formatVersion = 1
  for meta in metas:
    if meta.managed and not meta.abstract:
      result.models.add(modelSnapshot(meta))

macro schemaSnapshot*(modelTypes: varargs[typed]): untyped =
  var values = newNimNode(nnkBracket)
  for modelType in modelTypes:
    values.add(newCall(bindSym("getModelMeta"), modelType))
  result = newCall(bindSym("schemaSnapshotFromMeta"),
    newTree(nnkPrefix, ident("@"), values))

proc toJson*(field: FieldSnapshot): JsonNode =
  %*{
    "name": field.name,
    "storageName": field.storageName,
    "columnName": field.columnName,
    "kind": $field.kind,
    "nullable": field.nullable,
    "primaryKey": field.primaryKey,
    "unique": field.unique,
    "indexed": field.indexed,
    "maxLength": field.maxLength,
    "precision": field.precision,
    "scale": field.scale,
    "autoIncrement": field.autoIncrement,
    "hasDefault": field.hasDefault,
    "defaultValue": field.defaultValue,
    "dbDefault": field.dbDefault,
    "relationTarget": field.relationTarget,
    "relationTable": field.relationTable,
    "relatedName": field.relatedName,
    "onDelete": $field.onDelete
  }

proc stringGroupsToJson(groups: seq[seq[string]]): JsonNode =
  result = newJArray()
  for group in groups:
    result.add(%group)

proc toJson*(model: ModelSnapshot): JsonNode =
  var fields = newJArray()
  for field in model.fields:
    fields.add(field.toJson)
  %*{
    "modelName": model.modelName,
    "tableName": model.tableName,
    "fields": fields,
    "uniqueTogether": stringGroupsToJson(model.uniqueTogether),
    "indexes": stringGroupsToJson(model.indexes),
    "managed": model.managed
  }

proc toJson*(snapshot: SchemaSnapshot): JsonNode =
  var models = newJArray()
  for model in snapshot.models:
    models.add(model.toJson)
  %*{
    "formatVersion": snapshot.formatVersion,
    "models": models
  }

proc readStringGroups(node: JsonNode): seq[seq[string]] =
  for group in node:
    var values: seq[string]
    for value in group:
      values.add(value.getStr)
    result.add(values)

proc fieldSnapshotFromJson*(node: JsonNode): FieldSnapshot =
  FieldSnapshot(
    name: node["name"].getStr,
    storageName: node["storageName"].getStr,
    columnName: node["columnName"].getStr,
    kind: parseEnum[FieldKind](node["kind"].getStr),
    nullable: node["nullable"].getBool,
    primaryKey: node["primaryKey"].getBool,
    unique: node["unique"].getBool,
    indexed: node["indexed"].getBool,
    maxLength: node["maxLength"].getInt,
    precision: node["precision"].getInt,
    scale: node["scale"].getInt,
    autoIncrement: node["autoIncrement"].getBool,
    hasDefault: node["hasDefault"].getBool,
    defaultValue: node["defaultValue"].getStr,
    dbDefault: node["dbDefault"].getStr,
    relationTarget: node["relationTarget"].getStr,
    relationTable: node["relationTable"].getStr,
    relatedName: node["relatedName"].getStr,
    onDelete: parseEnum[OnDeleteAction](node["onDelete"].getStr))

proc modelSnapshotFromJson*(modelNode: JsonNode): ModelSnapshot =
  result = ModelSnapshot(
    modelName: modelNode["modelName"].getStr,
    tableName: modelNode["tableName"].getStr,
    uniqueTogether: readStringGroups(modelNode["uniqueTogether"]),
    indexes: readStringGroups(modelNode["indexes"]),
    managed: modelNode["managed"].getBool)
  for fieldNode in modelNode["fields"]:
    result.fields.add(fieldSnapshotFromJson(fieldNode))

proc toFieldMeta*(field: FieldSnapshot): FieldMeta =
  FieldMeta(
    name: field.name,
    storageName: field.storageName,
    columnName: field.columnName,
    kind: field.kind,
    nullable: field.nullable,
    primaryKey: field.primaryKey,
    unique: field.unique,
    indexed: field.indexed,
    maxLength: field.maxLength,
    precision: field.precision,
    scale: field.scale,
    autoIncrement: field.autoIncrement,
    hasDefault: field.hasDefault,
    defaultValue: field.defaultValue,
    dbDefault: field.dbDefault,
    relationTarget: field.relationTarget,
    relationTable: field.relationTable,
    relatedName: field.relatedName,
    onDelete: field.onDelete,
    editable: true)

proc toModelMeta*(model: ModelSnapshot): ModelMeta =
  result = ModelMeta(
    modelName: model.modelName,
    tableName: model.tableName,
    uniqueTogether: model.uniqueTogether,
    indexes: model.indexes,
    managed: model.managed)
  for field in model.fields:
    result.fields.add(field.toFieldMeta)

proc schemaSnapshotFromJson*(node: JsonNode): SchemaSnapshot =
  result.formatVersion = node["formatVersion"].getInt
  if result.formatVersion != 1:
    raise newException(ValueError,
      "unsupported schema snapshot format version: " & $result.formatVersion)
  for modelNode in node["models"]:
    result.models.add(modelSnapshotFromJson(modelNode))

proc saveSnapshot*(snapshot: SchemaSnapshot; path: string) =
  let parent = path.parentDir
  if parent.len > 0:
    createDir(parent)
  writeFile(path, snapshot.toJson.pretty)

proc loadSnapshot*(path: string): SchemaSnapshot =
  schemaSnapshotFromJson(parseFile(path))
