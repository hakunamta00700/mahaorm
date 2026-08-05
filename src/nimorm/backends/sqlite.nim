import std/strutils

import db_connector/sqlite3

import ../errors
import ../metadata
import ../schema/[generator, types]
import ./base

proc sqliteHandle(db: Database): PSqlite3 =
  if db.isNil or db.closed or db.backend != sqliteBackend:
    raise newException(ConnectionError, "SQLite connection is not open")
  cast[PSqlite3](db.handle)

proc sqliteMessage(handle: PSqlite3): string =
  let message = errmsg(handle)
  if message.isNil: "unknown SQLite error" else: $message

proc raiseSqlite(handle: PSqlite3; sqlText: string) {.noreturn.} =
  let message = sqliteMessage(handle)
  let detail = message & " [SQL: " & sqlText & "]"
  if "UNIQUE constraint failed" in message or "PRIMARY KEY" in message:
    raise newException(UniqueViolation, detail)
  if "FOREIGN KEY constraint failed" in message:
    raise newException(ForeignKeyViolation, detail)
  if "NOT NULL constraint failed" in message:
    raise newException(NotNullViolation, detail)
  if errcode(handle) == SQLITE_CONSTRAINT:
    raise newException(ConstraintViolation, detail)
  raise newException(SqlExecutionError, detail)

proc bindValue(statement: PStmt; index: int32; value: DbValue) =
  let code =
    case value.kind
    of dvNull:
      bind_null(statement, index)
    of dvInteger:
      bind_int64(statement, index, value.integerValue)
    of dvFloat:
      bind_double(statement, index, value.floatValue)
    of dvText:
      bind_text(statement, index, value.textValue.cstring,
        value.textValue.len.int32, SQLITE_TRANSIENT)
    of dvBlob:
      let data =
        if value.blobValue.len == 0: nil
        else: unsafeAddr value.blobValue[0]
      bind_blob(statement, index, data, value.blobValue.len.int32,
        SQLITE_TRANSIENT)
  if code != SQLITE_OK:
    raise newException(SerializationError,
      "failed to bind SQLite parameter " & $index)

proc prepare(db: Database; sqlText: string; params: openArray[DbValue]): PStmt =
  let handle = db.sqliteHandle
  if not db.logger.isNil:
    db.logger(sqlText, params.redacted)
  if prepare_v2(handle, sqlText.cstring, sqlText.len.cint, result, nil) != SQLITE_OK:
    raiseSqlite(handle, sqlText)
  try:
    for index, value in params:
      bindValue(result, (index + 1).int32, value)
  except:
    discard finalize(result)
    raise

proc readColumn(statement: PStmt; column: int32): DbValue =
  case column_type(statement, column)
  of SQLITE_NULL:
    dbNull()
  of SQLITE_INTEGER:
    dbValue(column_int64(statement, column))
  of SQLITE_FLOAT:
    dbValue(column_double(statement, column))
  of SQLITE_BLOB:
    let byteCount = column_bytes(statement, column).int
    var bytes = newSeq[byte](byteCount)
    if byteCount > 0:
      copyMem(bytes[0].addr, column_blob(statement, column), byteCount)
    dbValue(bytes)
  else:
    let text = column_text(statement, column)
    dbValue(if text.isNil: "" else: $text)

proc executeSqlite*(db: Database; sqlText: string;
                    params: openArray[DbValue] = []): int =
  let handle = db.sqliteHandle
  let statement = db.prepare(sqlText, params)
  try:
    let code = step(statement)
    if code notin [SQLITE_DONE, SQLITE_ROW]:
      raiseSqlite(handle, sqlText)
    changes(handle).int
  finally:
    discard finalize(statement)

proc queryRowsSqlite*(db: Database; sqlText: string;
                      params: openArray[DbValue] = []): seq[DbRow] =
  let handle = db.sqliteHandle
  let statement = db.prepare(sqlText, params)
  try:
    while true:
      let code = step(statement)
      case code
      of SQLITE_ROW:
        var row: DbRow
        for column in 0 ..< column_count(statement):
          row.add(readColumn(statement, column))
        result.add(row)
      of SQLITE_DONE:
        break
      else:
        raiseSqlite(handle, sqlText)
  finally:
    discard finalize(statement)

proc lastInsertIdSqlite*(db: Database): int64 =
  last_insert_rowid(db.sqliteHandle)

proc openSqlite*(path: string): Database =
  var handle: PSqlite3
  let code = sqlite3.open(path.cstring, handle)
  if code != SQLITE_OK:
    let message =
      if handle.isNil: "unable to open SQLite database"
      else: sqliteMessage(handle)
    if not handle.isNil:
      discard sqlite3.close(handle)
    raise newException(ConnectionError, message)
  result = Database(backend: sqliteBackend, handle: cast[pointer](handle))
  try:
    discard result.executeSqlite("PRAGMA foreign_keys = ON")
  except:
    discard sqlite3.close(handle)
    result.closed = true
    raise

proc closeSqlite*(db: Database) =
  if db.isNil or db.closed:
    return
  if db.backend != sqliteBackend:
    raise newException(ConnectionError, "connection backend is not SQLite")
  let handle = cast[PSqlite3](db.handle)
  if sqlite3.close(handle) != SQLITE_OK:
    raise newException(ConnectionError, sqliteMessage(handle))
  db.closed = true
  db.handle = nil

proc createTableSqlite*(db: Database; meta: ModelMeta) =
  for statement in schemaSql(meta, sqliteBackend).split(";\n"):
    if statement.strip.len > 0:
      discard db.executeSqlite(statement)
