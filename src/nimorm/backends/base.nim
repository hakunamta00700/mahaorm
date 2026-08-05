import ../schema/types

type
  DbValueKind* = enum
    dvNull,
    dvInteger,
    dvFloat,
    dvText,
    dvBlob

  DbValue* = object
    case kind*: DbValueKind
    of dvNull:
      discard
    of dvInteger:
      integerValue*: int64
    of dvFloat:
      floatValue*: float64
    of dvText:
      textValue*: string
    of dvBlob:
      blobValue*: seq[byte]

  DbRow* = seq[DbValue]
  QueryLogger* = proc(sql: string; params: seq[DbValue]) {.closure.}

  Database* = ref object
    backend*: BackendKind
    handle*: pointer
    closed*: bool
    transactionDepth*: int
    logger*: QueryLogger

proc dbNull*(): DbValue = DbValue(kind: dvNull)
proc dbValue*(value: int): DbValue =
  DbValue(kind: dvInteger, integerValue: value.int64)
proc dbValue*(value: int64): DbValue =
  DbValue(kind: dvInteger, integerValue: value)
proc dbValue*(value: float64): DbValue =
  DbValue(kind: dvFloat, floatValue: value)
proc dbValue*(value: bool): DbValue =
  DbValue(kind: dvInteger, integerValue: ord(value))
proc dbValue*(value: string): DbValue =
  DbValue(kind: dvText, textValue: value)
proc dbValue*(value: seq[byte]): DbValue =
  DbValue(kind: dvBlob, blobValue: value)

proc enableQueryLogging*(db: Database; logger: QueryLogger) =
  db.logger = logger

proc disableQueryLogging*(db: Database) =
  db.logger = nil
