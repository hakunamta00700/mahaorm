## Field vocabulary shared by the model macro and later ORM phases.
##
## Field calls in a model block are compile-time DSL nodes. They are parsed by
## the macro and intentionally do not create runtime Field wrapper values.

type
  FieldKind* = enum
    fkString,
    fkText,
    fkInteger,
    fkBigInteger,
    fkFloat,
    fkDecimal,
    fkBoolean,
    fkDate,
    fkDateTime,
    fkUuid,
    fkJson,
    fkBinary,
    fkForeignKey,
    fkOneToOne

  OnDeleteAction* = enum
    Cascade,
    Restrict,
    SetNull,
    SetDefault,
    NoAction
