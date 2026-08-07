import std/[parseutils, strutils]

import db_connector/postgres

import ../errors
import ../metadata
import ../schema/[generator, types]
import ./base

const
  PgDiagSqlState = 67'i32
  PgBoolOid = 16'i32
  PgByteaOid = 17'i32
  PgInt8Oid = 20'i32
  PgInt2Oid = 21'i32
  PgInt4Oid = 23'i32
  PgFloat4Oid = 700'i32
  PgFloat8Oid = 701'i32

proc postgresHandle(db: Database): PPGconn =
  if db.isNil or db.closed or db.backend != postgresBackend:
    raise newException(ConnectionError, "PostgreSQL connection is not open")
  cast[PPGconn](db.handle)

proc postgresMessage(handle: PPGconn): string =
  let message = pqerrorMessage(handle)
  if message.isNil: "unknown PostgreSQL error" else: ($message).strip

proc resultMessage(queryResult: PPGresult): string =
  let message = pqresultErrorMessage(queryResult)
  if message.isNil: "unknown PostgreSQL error" else: ($message).strip

proc raisePostgres(handle: PPGconn; queryResult: PPGresult;
                   sqlText: string) {.noreturn.} =
  let message =
    if queryResult.isNil: postgresMessage(handle)
    else: resultMessage(queryResult)
  let detail = message & " [SQL: " & sqlText & "]"
  var sqlState = ""
  if not queryResult.isNil:
    let state = pqresultErrorField(queryResult, PgDiagSqlState)
    if not state.isNil:
      sqlState = $state
  case sqlState
  of "23505":
    raise newException(UniqueViolation, detail)
  of "23503":
    raise newException(ForeignKeyViolation, detail)
  of "23502":
    raise newException(NotNullViolation, detail)
  else:
    if sqlState.startsWith("23"):
      raise newException(ConstraintViolation, detail)
    raise newException(SqlExecutionError, detail)

proc executeParams(db: Database; sqlText: string;
                   params: openArray[DbValue]): PPGresult =
  let handle = db.postgresHandle
  if not db.logger.isNil:
    db.logger(sqlText, params.redacted)

  var buffers = newSeq[string](params.len)
  var values = newSeq[cstring](params.len)
  var lengths = newSeq[int32](params.len)
  var formats = newSeq[int32](params.len)
  for index, value in params:
    case value.kind
    of dvNull:
      values[index] = nil
    of dvInteger:
      buffers[index] = $value.integerValue
      values[index] = buffers[index].cstring
    of dvFloat:
      buffers[index] = $value.floatValue
      values[index] = buffers[index].cstring
    of dvText:
      buffers[index] = value.textValue
      values[index] = buffers[index].cstring
    of dvBlob:
      buffers[index] = newString(value.blobValue.len)
      if value.blobValue.len > 0:
        copyMem(buffers[index][0].addr, value.blobValue[0].unsafeAddr,
          value.blobValue.len)
      values[index] =
        if buffers[index].len == 0: "".cstring
        else: buffers[index].cstring
      lengths[index] = buffers[index].len.int32
      formats[index] = 1

  let valuePointer =
    if values.len == 0: nil
    else: cast[cstringArray](values[0].addr)
  let lengthPointer =
    if lengths.len == 0: nil
    else: lengths[0].addr
  let formatPointer =
    if formats.len == 0: nil
    else: formats[0].addr
  result = pqexecParams(handle, sqlText.cstring, params.len.int32, nil,
    valuePointer, lengthPointer, formatPointer, 0)
  if result.isNil:
    raisePostgres(handle, result, sqlText)

proc parseBytea(value: string): seq[byte] =
  if not value.startsWith("\\x"):
    raise newException(SerializationError,
      "unsupported PostgreSQL bytea output format")
  if (value.len - 2) mod 2 != 0:
    raise newException(SerializationError, "invalid PostgreSQL bytea value")
  result = newSeq[byte]((value.len - 2) div 2)
  for index in 0 ..< result.len:
    var parsed: int
    if parseHex(value, parsed, 2 + index * 2, 2) != 2:
      raise newException(SerializationError, "invalid PostgreSQL bytea value")
    result[index] = parsed.byte

proc readPostgresColumn(queryResult: PPGresult; row, column: int32): DbValue =
  if pqgetisnull(queryResult, row, column) != 0:
    return dbNull()
  let raw = $pqgetvalue(queryResult, row, column)
  case pqftype(queryResult, column)
  of PgBoolOid:
    dbValue(raw == "t")
  of PgInt2Oid, PgInt4Oid, PgInt8Oid:
    dbValue(parseBiggestInt(raw).int64)
  of PgFloat4Oid, PgFloat8Oid:
    dbValue(parseFloat(raw))
  of PgByteaOid:
    dbValue(parseBytea(raw))
  else:
    dbValue(raw)

proc executePostgres*(db: Database; sqlText: string;
                      params: openArray[DbValue] = []): int =
  let handle = db.postgresHandle
  let queryResult = db.executeParams(sqlText, params)
  try:
    if pqresultStatus(queryResult) notin {PGRES_COMMAND_OK, PGRES_TUPLES_OK}:
      raisePostgres(handle, queryResult, sqlText)
    let affected = pqcmdTuples(queryResult)
    if affected.isNil or ($affected).len == 0: 0
    else: parseInt($affected)
  finally:
    pqclear(queryResult)

proc queryRowsPostgres*(db: Database; sqlText: string;
                        params: openArray[DbValue] = []): seq[DbRow] =
  let handle = db.postgresHandle
  let queryResult = db.executeParams(sqlText, params)
  try:
    if pqresultStatus(queryResult) != PGRES_TUPLES_OK:
      raisePostgres(handle, queryResult, sqlText)
    for row in 0 ..< pqntuples(queryResult):
      var values: DbRow
      for column in 0 ..< pqnfields(queryResult):
        values.add(readPostgresColumn(queryResult, row, column))
      result.add(values)
  finally:
    pqclear(queryResult)

proc openPostgres*(host: string; port: int; database, user, password: string): Database =
  let handle = pqsetdbLogin(
    host.cstring,
    ($port).cstring,
    nil,
    nil,
    database.cstring,
    user.cstring,
    password.cstring)
  if handle.isNil:
    raise newException(ConnectionError, "unable to allocate PostgreSQL connection")
  if pqstatus(handle) != CONNECTION_OK:
    let message = postgresMessage(handle)
    pqfinish(handle)
    raise newException(ConnectionError, message)
  result = Database(backend: postgresBackend, handle: cast[pointer](handle))
  try:
    discard result.executePostgres("SET bytea_output = 'hex'")
  except CatchableError:
    pqfinish(handle)
    result.closed = true
    result.handle = nil
    raise

proc closePostgres*(db: Database) =
  if db.isNil or db.closed:
    return
  if db.backend != postgresBackend:
    raise newException(ConnectionError, "connection backend is not PostgreSQL")
  pqfinish(cast[PPGconn](db.handle))
  db.closed = true
  db.handle = nil

proc createTablePostgres*(db: Database; meta: ModelMeta) =
  for statement in schemaSql(meta, postgresBackend).split(";\n"):
    if statement.strip.len > 0:
      discard db.executePostgres(statement)
