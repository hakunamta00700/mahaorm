import std/[strutils, times]

type
  Decimal* = distinct string
    ## Exact base-10 value. It is intentionally not represented by float64.

  Uuid* = distinct string
    ## Canonical UUID text representation.

  Date* = object
    year*: int
    month*: int
    day*: int

proc decimal*(value: string): Decimal =
  let text = value.strip
  if text.len == 0:
    raise newException(ValueError, "decimal value must not be empty")
  var seenDigit = false
  var seenPoint = false
  for index, character in text:
    case character
    of '+', '-':
      if index != 0:
        raise newException(ValueError, "invalid decimal value: " & value)
    of '.':
      if seenPoint:
        raise newException(ValueError, "invalid decimal value: " & value)
      seenPoint = true
    of '0'..'9':
      seenDigit = true
    else:
      raise newException(ValueError, "invalid decimal value: " & value)
  if not seenDigit:
    raise newException(ValueError, "invalid decimal value: " & value)
  Decimal(text)

proc `$`*(value: Decimal): string {.borrow.}

proc uuid*(value: string): Uuid =
  let text = value.toLowerAscii
  if text.len != 36 or text[8] != '-' or text[13] != '-' or
      text[18] != '-' or text[23] != '-':
    raise newException(ValueError, "invalid UUID value: " & value)
  for index, character in text:
    if index in [8, 13, 18, 23]:
      continue
    if character notin HexDigits:
      raise newException(ValueError, "invalid UUID value: " & value)
  Uuid(text)

proc `$`*(value: Uuid): string {.borrow.}

proc date*(year, month, day: int): Date =
  let parsed = dateTime(year, Month(month), MonthdayRange(day), 0, 0, 0, 0, utc())
  result = Date(year: parsed.year, month: ord(parsed.month), day: parsed.monthday)

proc parseDate*(value: string): Date =
  let parsed = times.parse(value, "yyyy-MM-dd", utc())
  Date(year: parsed.year, month: ord(parsed.month), day: parsed.monthday)

proc `$`*(value: Date): string =
  align($value.year, 4, '0') & "-" & align($value.month, 2, '0') & "-" &
    align($value.day, 2, '0')
