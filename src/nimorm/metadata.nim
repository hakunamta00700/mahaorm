import std/options

import ./field_defs

export field_defs

type
  FieldMeta* = object
    name*: string
    columnName*: string
    kind*: FieldKind
    nullable*: bool
    primaryKey*: bool
    unique*: bool
    indexed*: bool
    maxLength*: int
    minLength*: int
    trim*: bool
    verboseName*: string
    helpText*: string
    editable*: bool

  ModelMeta* = object
    modelName*: string
    tableName*: string
    verboseName*: string
    verboseNamePlural*: string
    fields*: seq[FieldMeta]
    ordering*: seq[string]
    uniqueTogether*: seq[seq[string]]
    indexes*: seq[seq[string]]
    managed*: bool
    abstract*: bool
    autoPrimaryKey*: bool

proc `$`*(field: FieldMeta): string =
  result = field.name & ":" & $field.kind
  if field.nullable:
    result.add("?")

proc `$`*(model: ModelMeta): string =
  result = model.modelName & "(" & model.tableName & ") ["
  for index, field in model.fields:
    if index > 0:
      result.add(", ")
    result.add($field)
  result.add("]")

template getModelMeta*(modelType: typedesc): untyped =
  ## Returns the immutable metadata constant generated for modelType.
  mixin nimOrmModelMeta
  nimOrmModelMeta(modelType)

proc getFieldMeta*[T](modelType: typedesc[T], fieldName: string): FieldMeta =
  ## Looks up a field by its DSL name. Unknown names are programmer errors.
  for field in getModelMeta(modelType).fields:
    if field.name == fieldName:
      return field
  raise newException(ValueError,
    getModelMeta(modelType).modelName & "." & fieldName &
    ": model has no such field")

template tableName*(modelType: typedesc): string =
  getModelMeta(modelType).tableName

proc primaryKeyField*[T](modelType: typedesc[T]): Option[FieldMeta] =
  for field in getModelMeta(modelType).fields:
    if field.primaryKey:
      return some(field)
  none(FieldMeta)
