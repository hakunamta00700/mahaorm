import std/macros

import ./backends/[base, sqlite]
when defined(nimormPostgres):
  import ./backends/postgres
import ./errors
import ./metadata
import ./schema/types

export base, sqlite
when defined(nimormPostgres):
  export postgres
else:
  proc openPostgres*(host: string; port: int;
                     database, user, password: string): Database =
    discard host
    discard port
    discard database
    discard user
    discard password
    raise newException(ConnectionError,
      "PostgreSQL support requires compilation with -d:nimormPostgres")

proc execute*(db: Database; sqlText: string;
              params: openArray[DbValue] = []): int =
  case db.backend
  of sqliteBackend:
    db.executeSqlite(sqlText, params)
  of postgresBackend:
    when defined(nimormPostgres):
      db.executePostgres(sqlText, params)
    else:
      raise newException(ConnectionError,
        "PostgreSQL support requires compilation with -d:nimormPostgres")

proc queryRows*(db: Database; sqlText: string;
                params: openArray[DbValue] = []): seq[DbRow] =
  case db.backend
  of sqliteBackend:
    db.queryRowsSqlite(sqlText, params)
  of postgresBackend:
    when defined(nimormPostgres):
      db.queryRowsPostgres(sqlText, params)
    else:
      raise newException(ConnectionError,
        "PostgreSQL support requires compilation with -d:nimormPostgres")

proc lastInsertId*(db: Database): int64 =
  case db.backend
  of sqliteBackend:
    db.lastInsertIdSqlite()
  of postgresBackend:
    raise newException(SqlExecutionError,
      "PostgreSQL generated IDs require an INSERT ... RETURNING clause")

proc close*(db: Database) =
  if db.isNil or db.closed:
    return
  case db.backend
  of sqliteBackend:
    db.closeSqlite()
  of postgresBackend:
    when defined(nimormPostgres):
      db.closePostgres()
    else:
      raise newException(ConnectionError,
        "PostgreSQL support requires compilation with -d:nimormPostgres")

proc createTable*(db: Database; meta: ModelMeta) =
  case db.backend
  of sqliteBackend:
    db.createTableSqlite(meta)
  of postgresBackend:
    when defined(nimormPostgres):
      db.createTablePostgres(meta)
    else:
      raise newException(ConnectionError,
        "PostgreSQL support requires compilation with -d:nimormPostgres")

macro createTables*(db: typed; modelTypes: varargs[typed]): untyped =
  result = newStmtList()
  for modelType in modelTypes:
    result.add quote do:
      createTable(`db`, getModelMeta(`modelType`))
