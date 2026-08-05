# Fields and validation

## Field types

| Declaration | Native Nim type | SQLite | PostgreSQL |
| --- | --- | --- | --- |
| `stringField(maxLength = n)` | `string` | `VARCHAR(n)` | `VARCHAR(n)` |
| `textField()` | `string` | `TEXT` | `TEXT` |
| `integerField()` | `int` | `INTEGER` | `INTEGER` |
| `bigIntegerField()` | `int64` | `INTEGER` | `BIGINT` |
| `floatField()` | `float64` | `REAL` | `DOUBLE PRECISION` |
| `decimalField(precision, scale)` | `Decimal` | `NUMERIC` | `NUMERIC` |
| `booleanField()` | `bool` | `INTEGER` | `BOOLEAN` |
| `dateField()` | `Date` | `DATE` | `DATE` |
| `dateTimeField()` | `DateTime` | `DATETIME` | `TIMESTAMPTZ` |
| `uuidField()` | `Uuid` | `TEXT` | `UUID` |
| `jsonField()` | `JsonNode` | `TEXT` | `JSONB` |
| `binaryField()` | `seq[byte]` | `BLOB` | `BYTEA` |

`Decimal` stores an exact base-10 string instead of a binary float. Construct
special values with `decimal("12.50")`, `uuid("...")`, `date(...)`, or
`parseDate(...)`. Nullable fields wrap the native type in `Option`.

## Common options

All fields accept the relevant subset of `primaryKey`, `nullable`, `unique`,
`dbIndex`, `columnName`, `verboseName`, `helpText`, `editable`, `default`,
`dbDefault`, `defaultFactory`, and `validators`.

- `default` is a scalar literal applied before insert and represented in DDL.
- `defaultFactory` names a zero-argument proc and runs before insert.
- `dbDefault` is an explicit SQL expression. Treat it as trusted schema source,
  not user input.
- `autoNowAdd` writes the time on insert; `autoNow` writes it on insert and
  update. Both are limited to `dateTimeField`.
- `trim`, `verboseName`, `helpText`, and `editable` are descriptive metadata;
  `trim` does not mutate values automatically in `0.1.0`.

String fields require `maxLength` and may use `minLength` and `pattern`.
Numeric and decimal fields may use `minValue` and `maxValue`.

## Validation

Validation returns structured issues and never writes to the database:

```nim
proc noSpaces(value: string): Option[string] =
  if ' ' in value: some("must not contain spaces")
  else: none(string)

model Tag:
  slug = stringField(
    maxLength = 30,
    minLength = 2,
    pattern = "^[a-z0-9-]+$",
    validators = @[noSpaces])

for issue in Tag(slug: "Bad slug").validate():
  echo issue.field, " ", issue.code, " ", issue.message
```

A custom validator receives the native field value (including `Option[T]` for
nullable fields) and may return `Option[string]`, a string, or a boolean.
Built-in issue codes include `min_length`, `max_length`, `pattern`,
`min_value`, `max_value`, and `custom`.

Validation is opt-in before `insert` or `update`; persistence does not
implicitly call it. Database NOT NULL, UNIQUE, and foreign-key constraints are
independent and produce structured database exceptions.
