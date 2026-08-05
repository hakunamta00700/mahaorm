import std/[options, unittest]

import nimorm

proc validateSlug(value: string): Option[string] =
  if ' ' in value: some("slug must not contain spaces")
  else: none(string)

model ValidatedRecord:
  slug = stringField(
    maxLength = 12,
    minLength = 3,
    pattern = "^[a-z0-9-]+$",
    validators = @[validateSlug]
  )
  score = integerField(minValue = 0, maxValue = 100)
  optionalName = stringField(maxLength = 5, nullable = true)
  amount = decimalField(
    precision = 6,
    scale = 2,
    minValue = 0,
    maxValue = 9999.99
  )

suite "generated model validation":
  test "accepts valid native values and nullable options":
    let value = ValidatedRecord(
      slug: "nim-orm",
      score: 80,
      optionalName: none(string),
      amount: decimal("12.50"))
    check value.validate().len == 0

  test "reports length, pattern, numeric and custom errors by field":
    let value = ValidatedRecord(
      slug: "BAD SLUG VALUE",
      score: 101,
      optionalName: some("too-long"),
      amount: decimal("-1.00"))
    let issues = value.validate()
    check issues.len >= 5
    var codes: seq[string]
    for issue in issues:
      codes.add(issue.field & ":" & issue.code)
    check "slug:max_length" in codes
    check "slug:pattern" in codes
    check "slug:custom" in codes
    check "score:max_value" in codes
    check "optionalName:max_length" in codes
    check "amount:min_value" in codes

  test "exposes validator names in static metadata":
    check getFieldMeta(ValidatedRecord, "slug").validatorNames ==
      @["validateSlug"]
