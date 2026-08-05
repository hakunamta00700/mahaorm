import std/[options, re, strutils]

import ./types

type
  ValidationIssue* = object
    field*: string
    code*: string
    message*: string

proc issue(field, code, message: string): ValidationIssue =
  ValidationIssue(field: field, code: code, message: message)

proc validateStringValue*(field, value: string;
                          minLength, maxLength: int;
                          pattern: string): seq[ValidationIssue] =
  if minLength > 0 and value.len < minLength:
    result.add(issue(field, "min_length",
      field & " must contain at least " & $minLength & " characters"))
  if maxLength > 0 and value.len > maxLength:
    result.add(issue(field, "max_length",
      field & " must contain at most " & $maxLength & " characters"))
  if pattern.len > 0 and not value.match(re(pattern)):
    result.add(issue(field, "pattern",
      field & " does not match the required pattern"))

proc validateStringValue*(field: string; value: Option[string];
                          minLength, maxLength: int;
                          pattern: string): seq[ValidationIssue] =
  if value.isSome:
    validateStringValue(field, value.get, minLength, maxLength, pattern)
  else:
    @[]

proc validateNumericValue*[T: SomeNumber](
    field: string; value: T;
    hasMin: bool; minValue: float64;
    hasMax: bool; maxValue: float64): seq[ValidationIssue] =
  let number = value.float64
  if hasMin and number < minValue:
    result.add(issue(field, "min_value",
      field & " must be at least " & $minValue))
  if hasMax and number > maxValue:
    result.add(issue(field, "max_value",
      field & " must be at most " & $maxValue))

proc validateNumericValue*[T: SomeNumber](
    field: string; value: Option[T];
    hasMin: bool; minValue: float64;
    hasMax: bool; maxValue: float64): seq[ValidationIssue] =
  if value.isSome:
    validateNumericValue(field, value.get, hasMin, minValue, hasMax, maxValue)
  else:
    @[]

proc validateDecimalValue*(
    field: string; value: Decimal;
    hasMin: bool; minValue: float64;
    hasMax: bool; maxValue: float64): seq[ValidationIssue] =
  validateNumericValue(field, parseFloat($value),
    hasMin, minValue, hasMax, maxValue)

proc validateDecimalValue*(
    field: string; value: Option[Decimal];
    hasMin: bool; minValue: float64;
    hasMax: bool; maxValue: float64): seq[ValidationIssue] =
  if value.isSome:
    validateDecimalValue(field, value.get,
      hasMin, minValue, hasMax, maxValue)
  else:
    @[]

proc addCustomValidation*(issues: var seq[ValidationIssue];
                          field: string;
                          message: Option[string]) =
  if message.isSome:
    issues.add(issue(field, "custom", message.get))

proc addCustomValidation*(issues: var seq[ValidationIssue];
                          field, message: string) =
  if message.len > 0:
    issues.add(issue(field, "custom", message))

proc addCustomValidation*(issues: var seq[ValidationIssue];
                          field: string; valid: bool) =
  if not valid:
    issues.add(issue(field, "custom", field & " is invalid"))

proc validate*[T](value: T): seq[ValidationIssue] =
  mixin nimOrmValidate
  nimOrmValidate(value)
