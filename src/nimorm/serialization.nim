import std/[json, options, times]

import ./backends/base
import ./errors
import ./types

type
  EncodedModel* = object
    columns*: seq[string]
    values*: seq[DbValue]

proc toDbValue*(value: string): DbValue = dbValue(value)
proc toDbValue*(value: int): DbValue = dbValue(value)
proc toDbValue*(value: int64): DbValue = dbValue(value)
proc toDbValue*(value: float64): DbValue = dbValue(value)
proc toDbValue*(value: bool): DbValue = dbValue(value)
proc toDbValue*(value: Decimal): DbValue = dbValue($value)
proc toDbValue*(value: Uuid): DbValue = dbValue($value)
proc toDbValue*(value: Date): DbValue = dbValue($value)
proc toDbValue*(value: DateTime): DbValue =
  dbValue(value.format("yyyy-MM-dd'T'HH:mm:ss'.'fffzzz"))
proc toDbValue*(value: JsonNode): DbValue =
  if value.isNil: dbNull() else: dbValue($value)
proc toDbValue*(value: seq[byte]): DbValue = dbValue(value)

proc toDbValue*[T](value: Option[T]): DbValue =
  if value.isSome: toDbValue(value.get) else: dbNull()

proc requireKind(value: DbValue; kinds: set[DbValueKind]; target: string) =
  if value.kind notin kinds:
    raise newException(SerializationError,
      "cannot decode " & $value.kind & " as " & target)

proc parseDateTimeValue(value: string): DateTime =
  const formats = [
    "yyyy-MM-dd'T'HH:mm:ss'.'fffzzz",
    "yyyy-MM-dd HH:mm:ss'.'fffzzz",
    "yyyy-MM-dd HH:mm:sszzz",
    "yyyy-MM-dd'T'HH:mm:sszzz",
    "yyyy-MM-dd HH:mm:ss"
  ]
  for format in formats:
    try:
      return times.parse(value, format)
    except ValueError:
      discard
  raise newException(SerializationError,
    "invalid DateTime database value: " & value)

proc fromDbValue*[T](value: DbValue; target: typedesc[T]): T =
  when T is Option:
    type Inner = typeof(default(T).get)
    if value.kind == dvNull:
      result = none(Inner)
    else:
      result = some(fromDbValue(value, Inner))
  elif T is string:
    requireKind(value, {dvText}, "string")
    result = value.textValue
  elif T is int:
    requireKind(value, {dvInteger}, "int")
    result = value.integerValue.int
  elif T is int64:
    requireKind(value, {dvInteger}, "int64")
    result = value.integerValue
  elif T is float64:
    requireKind(value, {dvInteger, dvFloat}, "float64")
    result =
      if value.kind == dvFloat: value.floatValue
      else: value.integerValue.float64
  elif T is bool:
    requireKind(value, {dvInteger}, "bool")
    result = value.integerValue != 0
  elif T is Decimal:
    requireKind(value, {dvInteger, dvFloat, dvText}, "Decimal")
    let text =
      case value.kind
      of dvInteger: $value.integerValue
      of dvFloat: $value.floatValue
      of dvText: value.textValue
      else: ""
    result = decimal(text)
  elif T is Uuid:
    requireKind(value, {dvText}, "Uuid")
    result = uuid(value.textValue)
  elif T is Date:
    requireKind(value, {dvText}, "Date")
    result = parseDate(value.textValue)
  elif T is DateTime:
    requireKind(value, {dvText}, "DateTime")
    result = parseDateTimeValue(value.textValue)
  elif T is JsonNode:
    requireKind(value, {dvText}, "JsonNode")
    result = parseJson(value.textValue)
  elif T is seq[byte]:
    requireKind(value, {dvBlob}, "seq[byte]")
    result = value.blobValue
  else:
    {.error: "nimorm does not know how to deserialize this field type".}
