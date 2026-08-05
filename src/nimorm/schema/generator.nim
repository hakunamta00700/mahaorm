import std/[sequtils, strutils]

import ../[field_defs, metadata]
import ./types

proc quoteIdentifier*(identifier: string; backend: BackendKind): string =
  ## Identifiers only originate from compile-time validated model metadata.
  ## Quoting still protects reserved words and unusual but valid names.
  discard backend
  "\"" & identifier.replace("\"", "\"\"") & "\""

proc quoteLiteral(value: string): string =
  "'" & value.replace("'", "''") & "'"

proc sqlType(field: FieldMeta; backend: BackendKind): string =
  case field.kind
  of fkString:
    "VARCHAR(" & $field.maxLength & ")"
  of fkText:
    "TEXT"
  of fkInteger:
    "INTEGER"
  of fkBigInteger:
    if backend == sqliteBackend: "INTEGER" else: "BIGINT"
  of fkFloat:
    if backend == sqliteBackend: "REAL" else: "DOUBLE PRECISION"
  of fkDecimal:
    "NUMERIC(" & $field.precision & ", " & $field.scale & ")"
  of fkBoolean:
    if backend == sqliteBackend: "INTEGER" else: "BOOLEAN"
  of fkDate:
    "DATE"
  of fkDateTime:
    if backend == sqliteBackend: "DATETIME" else: "TIMESTAMPTZ"
  of fkUuid:
    if backend == sqliteBackend: "TEXT" else: "UUID"
  of fkJson:
    if backend == sqliteBackend: "TEXT" else: "JSONB"
  of fkBinary:
    if backend == sqliteBackend: "BLOB" else: "BYTEA"
  of fkForeignKey, fkOneToOne:
    if backend == sqliteBackend: "INTEGER" else: "BIGINT"

proc sqlDefault(field: FieldMeta; backend: BackendKind): string =
  if field.dbDefault.len > 0:
    return field.dbDefault
  if not field.hasDefault:
    return ""
  case field.kind
  of fkString, fkText, fkDecimal, fkDate, fkDateTime, fkUuid, fkJson:
    quoteLiteral(field.defaultValue)
  of fkBoolean:
    if backend == sqliteBackend:
      if field.defaultValue == "true": "1" else: "0"
    else:
      field.defaultValue.toUpperAscii
  else:
    field.defaultValue

proc columnSql(field: FieldMeta; backend: BackendKind): string =
  result = quoteIdentifier(field.columnName, backend) & " "
  if backend == sqliteBackend and field.primaryKey and field.autoIncrement:
    return result & "INTEGER PRIMARY KEY AUTOINCREMENT"
  result.add(sqlType(field, backend))
  if field.primaryKey:
    result.add(" PRIMARY KEY")
  if not field.nullable:
    result.add(" NOT NULL")
  if field.unique and not field.primaryKey:
    result.add(" UNIQUE")
  let defaultValue = sqlDefault(field, backend)
  if defaultValue.len > 0:
    result.add(" DEFAULT " & defaultValue)

proc onDeleteSql(action: OnDeleteAction): string =
  case action
  of Cascade: "CASCADE"
  of Restrict: "RESTRICT"
  of SetNull: "SET NULL"
  of SetDefault: "SET DEFAULT"
  of NoAction: "NO ACTION"

proc indexName(tableName: string; fields: seq[FieldMeta]): string =
  "idx_" & tableName & "_" & fields.mapIt(it.columnName).join("_")

proc findField(meta: ModelMeta; fieldName: string): FieldMeta =
  for field in meta.fields:
    if field.name == fieldName:
      return field
  raise newException(SchemaError,
    meta.modelName & "." & fieldName & ": field not found while generating schema")

proc schemaSql*(meta: ModelMeta; backend: BackendKind): string =
  var definitions = meta.fields.mapIt(columnSql(it, backend))
  for fieldNames in meta.uniqueTogether:
    let columns = fieldNames.mapIt(
      quoteIdentifier(findField(meta, it).columnName, backend))
    definitions.add("UNIQUE (" & columns.join(", ") & ")")
  for field in meta.fields:
    if field.kind in {fkForeignKey, fkOneToOne}:
      definitions.add("FOREIGN KEY (" &
        quoteIdentifier(field.columnName, backend) & ") REFERENCES " &
        quoteIdentifier(field.relationTable, backend) & " (" &
        quoteIdentifier("id", backend) & ") ON DELETE " &
        onDeleteSql(field.onDelete))

  result = "CREATE TABLE " & quoteIdentifier(meta.tableName, backend) & " (\n  " &
    definitions.join(",\n  ") & "\n)"

  var declaredIndexes: seq[seq[string]] = meta.indexes
  for field in meta.fields:
    if field.indexed:
      declaredIndexes.add(@[field.name])
  for fieldNames in declaredIndexes:
    let fields = fieldNames.mapIt(findField(meta, it))
    let columns = fields.mapIt(quoteIdentifier(it.columnName, backend))
    result.add(";\nCREATE INDEX " &
      quoteIdentifier(indexName(meta.tableName, fields), backend) & " ON " &
      quoteIdentifier(meta.tableName, backend) & " (" & columns.join(", ") & ")")

template schemaSql*(modelType: typedesc; backend: BackendKind): string =
  schemaSql(getModelMeta(modelType), backend)
