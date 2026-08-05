import std/strutils

import ../database
import ../errors
import ../schema/types
import ../transaction
import ./[compiler, history, operations]

proc validateSafety(migration: Migration;
                    allowDestructive, allowReview: bool) =
  for operation in migration.operations:
    if operation.destructive and not allowDestructive:
      raise newException(MigrationError,
        migration.name & ": destructive operation " & $operation.kind &
        " requires allowDestructive = true" &
        (if operation.reason.len > 0: " (" & operation.reason & ")" else: ""))
    if operation.requiresReview and not allowReview:
      raise newException(MigrationError,
        migration.name & ": operation " & $operation.kind &
        " requires allowReview = true" &
        (if operation.reason.len > 0: " (" & operation.reason & ")" else: ""))

proc applyMigration*(db: Database; migration: Migration;
                     allowDestructive = false;
                     allowReview = false): bool =
  migration.validateSafety(allowDestructive, allowReview)
  db.ensureMigrationHistory()
  if db.isMigrationApplied(migration.name):
    return false
  if migration.dependency.len > 0 and
      not db.isMigrationApplied(migration.dependency):
    raise newException(MigrationError,
      migration.name & ": dependency '" & migration.dependency &
      "' has not been applied")

  let statements = migration.migrationSql(db.backend)
  db.transaction:
    for statement in statements:
      if statement.len > 0:
        discard db.execute(statement)
    db.recordMigration(migration.name)
  true

proc sqlMigration*(migration: Migration;
                   backend: BackendKind): string =
  migration.migrationSql(backend).join(";\n") & ";"
