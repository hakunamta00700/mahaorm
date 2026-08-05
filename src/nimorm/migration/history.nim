import std/times

import ../backends/base
import ../database
import ../schema/types

const MigrationTable* = "_nimorm_migrations"

proc marker(db: Database; index: int): string =
  if db.backend == sqliteBackend: "?" else: "$" & $index

proc ensureMigrationHistory*(db: Database) =
  discard db.execute(
    "CREATE TABLE IF NOT EXISTS \"_nimorm_migrations\" (" &
    "\"name\" VARCHAR(255) PRIMARY KEY, " &
    "\"applied_at\" VARCHAR(64) NOT NULL)")

proc appliedMigrations*(db: Database): seq[string] =
  db.ensureMigrationHistory()
  for row in db.queryRows(
      "SELECT \"name\" FROM \"_nimorm_migrations\" ORDER BY \"name\""):
    result.add(row[0].textValue)

proc isMigrationApplied*(db: Database; name: string): bool =
  db.ensureMigrationHistory()
  let rows = db.queryRows(
    "SELECT 1 FROM \"_nimorm_migrations\" WHERE \"name\" = " &
      marker(db, 1) & " LIMIT 1",
    [dbValue(name)])
  rows.len > 0

proc recordMigration*(db: Database; name: string) =
  discard db.execute(
    "INSERT INTO \"_nimorm_migrations\" (\"name\", \"applied_at\") " &
      "VALUES (" & marker(db, 1) & ", " & marker(db, 2) & ")",
    [dbValue(name), dbValue(now().format("yyyy-MM-dd'T'HH:mm:sszzz"))])
