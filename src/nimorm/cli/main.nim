import std/strutils
when isMainModule:
  import std/os

import nimorm

const Usage = """
nimorm migration CLI

Usage:
  nimorm makemigrations <previous.json|-> <current.json> <name> <output.json> [dependency]
  nimorm migrate <sqlite.db> <migration.json> [--allow-destructive] [--allow-review]
  nimorm migrations <sqlite.db>
  nimorm sqlmigrate <migration.json> <sqlite|postgres>
"""

proc requireArgs(command: string; values: seq[string]; count: int) =
  if values.len < count:
    raise newException(ValueError,
      command & ": not enough arguments\n" & Usage)

proc makeMigrations(arguments: seq[string]) =
  requireArgs("makemigrations", arguments, 4)
  let previous =
    if arguments[0] == "-": SchemaSnapshot(formatVersion: 1)
    else: loadSnapshot(arguments[0])
  let current = loadSnapshot(arguments[1])
  let dependency = if arguments.len >= 5: arguments[4] else: ""
  let migration = diffSchemas(previous, current, arguments[2], dependency)
  migration.saveMigration(arguments[3])
  echo "created ", arguments[3], " with ", migration.operations.len,
    " operation(s)"

proc migrate(arguments: seq[string]) =
  requireArgs("migrate", arguments, 2)
  let allowDestructive = "--allow-destructive" in arguments
  let allowReview = "--allow-review" in arguments
  let db = openSqlite(arguments[0])
  defer: db.close()
  let migration = loadMigration(arguments[1])
  if db.applyMigration(migration, allowDestructive, allowReview):
    echo "applied ", migration.name
  else:
    echo "already applied ", migration.name

proc listMigrations(arguments: seq[string]) =
  requireArgs("migrations", arguments, 1)
  let db = openSqlite(arguments[0])
  defer: db.close()
  for migration in db.appliedMigrations():
    echo migration

proc sqlMigrate(arguments: seq[string]) =
  requireArgs("sqlmigrate", arguments, 2)
  let backend =
    case arguments[1].toLowerAscii
    of "sqlite": sqliteBackend
    of "postgres", "postgresql": postgresBackend
    else:
      raise newException(ValueError,
        "sqlmigrate: backend must be sqlite or postgres")
  echo loadMigration(arguments[0]).sqlMigration(backend)

proc run*(arguments: seq[string]): int =
  let normalized =
    if arguments.len > 0 and arguments[0] == "--": arguments[1 .. ^1]
    else: arguments
  if normalized.len == 0 or normalized[0] in ["-h", "--help", "help"]:
    echo Usage
    return 0
  try:
    let rest = normalized[1 .. ^1]
    case normalized[0]
    of "makemigrations": makeMigrations(rest)
    of "migrate": migrate(rest)
    of "migrations": listMigrations(rest)
    of "sqlmigrate": sqlMigrate(rest)
    else:
      raise newException(ValueError,
        "unknown command: " & normalized[0] & "\n" & Usage)
    0
  except CatchableError as error:
    stderr.writeLine("nimorm: " & error.msg)
    1

when isMainModule:
  quit(run(commandLineParams()))
