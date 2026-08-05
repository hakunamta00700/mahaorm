import std/[os, unittest]

import nimorm
import nimorm/cli/main as migration_cli

model CliItem:
  name = stringField(maxLength = 80)

  meta:
    tableName = "cli_items"

suite "migration CLI":
  test "creates and applies migration files through real commands":
    let temp = getTempDir()
    let snapshotPath = temp / "nimorm-cli-current.json"
    let migrationPath = temp / "nimorm-cli-0001.json"
    let databasePath = temp / "nimorm-cli-test.sqlite3"
    defer:
      for path in [snapshotPath, migrationPath, databasePath]:
        if fileExists(path):
          removeFile(path)

    var snapshot = schemaSnapshot(CliItem)
    snapshot.models[0].modelName = "Item"
    snapshot.saveSnapshot(snapshotPath)
    check migration_cli.run(@[
      "makemigrations", "-", snapshotPath,
      "0001_initial", migrationPath]) == 0
    check fileExists(migrationPath)
    check migration_cli.run(@[
      "migrate", databasePath, migrationPath]) == 0
    check migration_cli.run(@[
      "migrate", databasePath, migrationPath]) == 0

    let db = openSqlite(databasePath)
    defer: db.close()
    check db.appliedMigrations() == @["0001_initial"]
    check db.queryRows(
      "SELECT name FROM sqlite_master WHERE type = ? AND name = ?",
      [dbValue("table"), dbValue("cli_items")]).len == 1

  test "returns failure for unknown commands":
    check migration_cli.run(@["unknown"]) == 1
