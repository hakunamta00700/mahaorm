import ../backends/base
import ../serialization
import ./ast

type
  FieldRef*[T] = object
    name*: string
    columnName*: string
    nullable*: bool
    sensitive*: bool

proc fieldRef*[T](name, columnName: string; nullable = false;
                  sensitive = false): FieldRef[T] =
  FieldRef[T](name: name, columnName: columnName, nullable: nullable,
    sensitive: sensitive)

proc parameter[T](field: FieldRef[T]; value: T): DbValue =
  withSensitivity(toDbValue(value), field.sensitive)

proc comparison[T](field: FieldRef[T]; operator: CompareOperator;
                   value: T): SqlExpression =
  SqlExpression(
    kind: ekCompare,
    columnName: field.columnName,
    compareOperator: operator,
    values: @[field.parameter(value)])

proc `==`*[T](field: FieldRef[T]; value: T): SqlExpression =
  comparison(field, coEqual, value)

proc `!=`*[T](field: FieldRef[T]; value: T): SqlExpression =
  comparison(field, coNotEqual, value)

proc `>`*[T](field: FieldRef[T]; value: T): SqlExpression =
  comparison(field, coGreater, value)

proc `>=`*[T](field: FieldRef[T]; value: T): SqlExpression =
  comparison(field, coGreaterOrEqual, value)

proc `<`*[T](field: FieldRef[T]; value: T): SqlExpression =
  comparison(field, coLess, value)

proc `<=`*[T](field: FieldRef[T]; value: T): SqlExpression =
  comparison(field, coLessOrEqual, value)

proc contains*(field: FieldRef[string]; value: string): SqlExpression =
  SqlExpression(kind: ekLike, columnName: field.columnName,
    likeOperator: loContains, values: @[field.parameter(value)])

proc startsWith*(field: FieldRef[string]; value: string): SqlExpression =
  SqlExpression(kind: ekLike, columnName: field.columnName,
    likeOperator: loStartsWith, values: @[field.parameter(value)])

proc endsWith*(field: FieldRef[string]; value: string): SqlExpression =
  SqlExpression(kind: ekLike, columnName: field.columnName,
    likeOperator: loEndsWith, values: @[field.parameter(value)])

proc inList*[T](field: FieldRef[T]; values: openArray[T]): SqlExpression =
  result = SqlExpression(kind: ekIn, columnName: field.columnName)
  for value in values:
    result.values.add(field.parameter(value))

proc isNull*[T](field: FieldRef[T]): SqlExpression =
  SqlExpression(kind: ekIsNull, columnName: field.columnName)

proc isNotNull*[T](field: FieldRef[T]): SqlExpression =
  SqlExpression(kind: ekIsNotNull, columnName: field.columnName)

proc between*[T](field: FieldRef[T]; lower, upper: T): SqlExpression =
  SqlExpression(kind: ekBetween, columnName: field.columnName,
    values: @[field.parameter(lower), field.parameter(upper)])

proc `and`*(left, right: SqlExpression): SqlExpression =
  SqlExpression(kind: ekAnd, children: @[left, right])

proc `or`*(left, right: SqlExpression): SqlExpression =
  SqlExpression(kind: ekOr, children: @[left, right])

proc `not`*(expression: SqlExpression): SqlExpression =
  SqlExpression(kind: ekNot, children: @[expression])

proc asc*[T](field: FieldRef[T]): OrderExpression =
  OrderExpression(columnName: field.columnName, direction: sortAscending)

proc desc*[T](field: FieldRef[T]): OrderExpression =
  OrderExpression(columnName: field.columnName, direction: sortDescending)

proc set*[T](field: FieldRef[T]; value: T): Assignment =
  Assignment(columnName: field.columnName, value: field.parameter(value))
