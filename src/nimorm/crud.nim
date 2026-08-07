import std/[options, sequtils, strutils]

import ./backends/base
import ./database
import ./errors
import ./metadata
import ./schema/generator
import ./schema/types

proc parameterMarker(db: Database; index: int): string =
  case db.backend
  of sqliteBackend: "?"
  of postgresBackend: "$" & $index

proc primaryKeyMeta(meta: ModelMeta): FieldMeta =
  for field in meta.fields:
    if field.primaryKey:
      return field
  raise newException(SerializationError,
    meta.modelName & ": model has no primary key")

proc selectColumns(meta: ModelMeta; backend: BackendKind): string =
  meta.fields.mapIt(quoteIdentifier(it.columnName, backend)).join(", ")

proc insert*[T](db: Database; value: T): T =
  mixin nimOrmEncode, nimOrmPrepareInsert, nimOrmSetGeneratedPrimaryKey
  result = value
  nimOrmPrepareInsert(result)
  let meta = getModelMeta(T)
  let primaryKey = primaryKeyMeta(meta)
  let encoded = nimOrmEncode(result,
    includePrimaryKey = not primaryKey.autoIncrement, forInsert = true)
  let sqlText =
    if encoded.columns.len == 0:
      "INSERT INTO " & quoteIdentifier(meta.tableName, db.backend) &
        " DEFAULT VALUES"
    else:
      let columns = encoded.columns.mapIt(quoteIdentifier(it, db.backend)).join(", ")
      var markers: seq[string]
      for index in 1 .. encoded.values.len:
        markers.add(parameterMarker(db, index))
      "INSERT INTO " & quoteIdentifier(meta.tableName, db.backend) &
        " (" & columns & ") VALUES (" & markers.join(", ") & ")"
  if primaryKey.autoIncrement and db.backend == postgresBackend:
    let rows = db.queryRows(sqlText & " RETURNING " &
      quoteIdentifier(primaryKey.columnName, db.backend), encoded.values)
    if rows.len != 1 or rows[0].len != 1:
      raise newException(SqlExecutionError,
        meta.modelName & ": INSERT RETURNING did not return one generated ID")
    nimOrmSetGeneratedPrimaryKey(result, rows[0][0].integerValue)
  else:
    discard db.execute(sqlText, encoded.values)
    if primaryKey.autoIncrement:
      nimOrmSetGeneratedPrimaryKey(result, db.lastInsertId())

proc get*[T](db: Database; modelType: typedesc[T]; primaryKey: DbValue): T =
  mixin nimOrmDecode
  let meta = getModelMeta(modelType)
  let pk = primaryKeyMeta(meta)
  let sqlText = "SELECT " & selectColumns(meta, db.backend) & " FROM " &
    quoteIdentifier(meta.tableName, db.backend) & " WHERE " &
    quoteIdentifier(pk.columnName, db.backend) & " = " &
    parameterMarker(db, 1) & " LIMIT 2"
  let rows = db.queryRows(sqlText, [primaryKey])
  case rows.len
  of 0:
    raise newException(RecordNotFound,
      meta.modelName & ": record was not found")
  of 1:
    result = nimOrmDecode(modelType, rows[0])
  else:
    raise newException(MultipleRecordsFound,
      meta.modelName & ": primary-key lookup returned multiple records")

proc get*[T](db: Database; modelType: typedesc[T]; primaryKey: int64): T =
  db.get(modelType, dbValue(primaryKey))

proc get*[T](db: Database; modelType: typedesc[T]; primaryKey: int): T =
  db.get(modelType, dbValue(primaryKey))

proc get*[T](db: Database; modelType: typedesc[T]; primaryKey: string): T =
  db.get(modelType, dbValue(primaryKey))

proc getOrNone*[T](db: Database; modelType: typedesc[T];
                   primaryKey: DbValue): Option[T] =
  try:
    some(db.get(modelType, primaryKey))
  except RecordNotFound:
    none(T)

proc getOrNone*[T](db: Database; modelType: typedesc[T];
                   primaryKey: int64): Option[T] =
  db.getOrNone(modelType, dbValue(primaryKey))

proc getOrNone*[T](db: Database; modelType: typedesc[T];
                   primaryKey: int): Option[T] =
  db.getOrNone(modelType, dbValue(primaryKey))

proc getOrNone*[T](db: Database; modelType: typedesc[T];
                   primaryKey: string): Option[T] =
  db.getOrNone(modelType, dbValue(primaryKey))

proc update*[T](db: Database; value: var T): int =
  mixin nimOrmEncode, nimOrmPrepareUpdate, nimOrmPrimaryKey
  nimOrmPrepareUpdate(value)
  let meta = getModelMeta(T)
  let pk = primaryKeyMeta(meta)
  let encoded = nimOrmEncode(value, includePrimaryKey = false)
  var assignments: seq[string]
  for index, column in encoded.columns:
    assignments.add(quoteIdentifier(column, db.backend) & " = " &
      parameterMarker(db, index + 1))
  var params = encoded.values
  params.add(nimOrmPrimaryKey(value))
  let sqlText = "UPDATE " & quoteIdentifier(meta.tableName, db.backend) &
    " SET " & assignments.join(", ") & " WHERE " &
    quoteIdentifier(pk.columnName, db.backend) & " = " &
    parameterMarker(db, params.len)
  result = db.execute(sqlText, params)

proc delete*[T](db: Database; value: T): int =
  mixin nimOrmPrimaryKey
  let meta = getModelMeta(T)
  let pk = primaryKeyMeta(meta)
  let sqlText = "DELETE FROM " & quoteIdentifier(meta.tableName, db.backend) &
    " WHERE " & quoteIdentifier(pk.columnName, db.backend) & " = " &
    parameterMarker(db, 1)
  db.execute(sqlText, [nimOrmPrimaryKey(value)])
