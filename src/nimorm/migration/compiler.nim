import std/[sequtils, strutils]

import ../errors
import ../field_defs
import ../schema/[generator, snapshot, types]
import ./operations

proc fieldByName(model: ModelSnapshot; name: string): FieldSnapshot =
  for field in model.fields:
    if field.name == name:
      return field
  raise newException(MigrationError,
    model.modelName & "." & name & ": migration field not found")

proc onDeleteSql(action: OnDeleteAction): string =
  case action
  of Cascade: "CASCADE"
  of Restrict: "RESTRICT"
  of SetNull: "SET NULL"
  of SetDefault: "SET DEFAULT"
  of NoAction: "NO ACTION"

proc operationSql*(operation: MigrationOperation;
                   backend: BackendKind): seq[string] =
  let table = quoteIdentifier(operation.tableName, backend)
  case operation.kind
  of CreateTable:
    result = schemaSql(operation.model.toModelMeta, backend).split(";\n")
  of DropTable:
    result.add("DROP TABLE " & table)
  of RenameTable:
    result.add("ALTER TABLE " &
      quoteIdentifier(operation.previousTableName, backend) & " RENAME TO " &
      quoteIdentifier(operation.tableName, backend))
  of AddColumn:
    result.add("ALTER TABLE " & table & " ADD COLUMN " &
      columnDefinitionSql(operation.field.toFieldMeta, backend))
  of DropColumn:
    result.add("ALTER TABLE " & table & " DROP COLUMN " &
      quoteIdentifier(operation.field.columnName, backend))
  of RenameColumn:
    result.add("ALTER TABLE " & table & " RENAME COLUMN " &
      quoteIdentifier(operation.previousColumnName, backend) & " TO " &
      quoteIdentifier(operation.field.columnName, backend))
  of AlterColumn:
    if backend == sqliteBackend:
      raise newException(MigrationError,
        operation.modelName & "." & operation.fieldName &
        ": SQLite AlterColumn requires an explicit table-rebuild migration")
    let column = quoteIdentifier(operation.field.columnName, backend)
    let field = operation.field.toFieldMeta
    result.add("ALTER TABLE " & table & " ALTER COLUMN " & column &
      " TYPE " & fieldSqlType(field, backend))
    result.add("ALTER TABLE " & table & " ALTER COLUMN " & column &
      (if field.nullable: " DROP NOT NULL" else: " SET NOT NULL"))
    let defaultValue = fieldDefaultSql(field, backend)
    result.add("ALTER TABLE " & table & " ALTER COLUMN " & column &
      (if defaultValue.len == 0: " DROP DEFAULT"
       else: " SET DEFAULT " & defaultValue))
  of CreateIndex:
    let fields = operation.fields.mapIt(
      operation.model.fieldByName(it).toFieldMeta)
    let columns = fields.mapIt(quoteIdentifier(it.columnName, backend))
    result.add("CREATE INDEX " &
      quoteIdentifier(indexName(operation.tableName, fields), backend) &
      " ON " & table & " (" & columns.join(", ") & ")")
  of DropIndex:
    let fields = operation.fields.mapIt(
      operation.model.fieldByName(it).toFieldMeta)
    result.add("DROP INDEX " &
      quoteIdentifier(indexName(operation.tableName, fields), backend))
  of AddForeignKey:
    if backend == sqliteBackend:
      raise newException(MigrationError,
        operation.modelName & "." & operation.fieldName &
        ": SQLite AddForeignKey requires an explicit table-rebuild migration")
    let field = operation.field
    let name = constraintName("fk", operation.tableName,
      @[field.columnName])
    result.add("ALTER TABLE " & table & " ADD CONSTRAINT " &
      quoteIdentifier(name, backend) & " FOREIGN KEY (" &
      quoteIdentifier(field.columnName, backend) & ") REFERENCES " &
      quoteIdentifier(field.relationTable, backend) & " (" &
      quoteIdentifier("id", backend) & ") ON DELETE " &
      onDeleteSql(field.onDelete))
  of DropForeignKey:
    if backend == sqliteBackend:
      raise newException(MigrationError,
        operation.modelName & "." & operation.fieldName &
        ": SQLite DropForeignKey requires an explicit table-rebuild migration")
    let name = constraintName("fk", operation.tableName,
      @[operation.field.columnName])
    result.add("ALTER TABLE " & table & " DROP CONSTRAINT " &
      quoteIdentifier(name, backend))
  of AddUniqueConstraint:
    if backend == sqliteBackend:
      raise newException(MigrationError,
        operation.modelName &
        ": SQLite AddUniqueConstraint requires an explicit table-rebuild migration")
    let columnNames = operation.fields.mapIt(
      operation.model.fieldByName(it).columnName)
    let columns = columnNames.mapIt(quoteIdentifier(it, backend))
    let name = constraintName("uq", operation.tableName, columnNames)
    result.add("ALTER TABLE " & table & " ADD CONSTRAINT " &
      quoteIdentifier(name, backend) & " UNIQUE (" & columns.join(", ") & ")")
  of DropUniqueConstraint:
    if backend == sqliteBackend:
      raise newException(MigrationError,
        operation.modelName &
        ": SQLite DropUniqueConstraint requires an explicit table-rebuild migration")
    let columnNames = operation.fields.mapIt(
      operation.model.fieldByName(it).columnName)
    let name = constraintName("uq", operation.tableName, columnNames)
    result.add("ALTER TABLE " & table & " DROP CONSTRAINT " &
      quoteIdentifier(name, backend))

proc migrationSql*(migration: Migration;
                   backend: BackendKind): seq[string] =
  for operation in migration.operations:
    result.add(operation.operationSql(backend))
