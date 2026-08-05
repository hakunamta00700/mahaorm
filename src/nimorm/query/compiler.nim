import std/strutils

import ../backends/base
import ../schema/[generator, types]
import ./ast

proc marker(backend: BackendKind; index: int): string =
  if backend == sqliteBackend: "?" else: "$" & $index

proc compareSql(operator: CompareOperator): string =
  case operator
  of coEqual: "="
  of coNotEqual: "<>"
  of coGreater: ">"
  of coGreaterOrEqual: ">="
  of coLess: "<"
  of coLessOrEqual: "<="

proc escapeLike(value: string): string =
  result = value
    .replace("\\", "\\\\")
    .replace("%", "\\%")
    .replace("_", "\\_")

proc compileExpression*(expression: SqlExpression; backend: BackendKind;
                        params: var seq[DbValue]): string =
  if expression.isNil:
    return ""
  case expression.kind
  of ekCompare:
    params.add(expression.values[0])
    quoteIdentifier(expression.columnName, backend) & " " &
      compareSql(expression.compareOperator) & " " &
      marker(backend, params.len)
  of ekAnd, ekOr:
    let operator = if expression.kind == ekAnd: " AND " else: " OR "
    "(" & compileExpression(expression.children[0], backend, params) &
      operator & compileExpression(expression.children[1], backend, params) & ")"
  of ekNot:
    "(NOT " & compileExpression(expression.children[0], backend, params) & ")"
  of ekLike:
    let raw = expression.values[0].textValue
    let pattern =
      case expression.likeOperator
      of loContains: "%" & escapeLike(raw) & "%"
      of loStartsWith: escapeLike(raw) & "%"
      of loEndsWith: "%" & escapeLike(raw)
    params.add(dbValue(pattern))
    quoteIdentifier(expression.columnName, backend) & " LIKE " &
      marker(backend, params.len) & " ESCAPE '\\'"
  of ekIn:
    if expression.values.len == 0:
      return "(0 = 1)"
    var markers: seq[string]
    for value in expression.values:
      params.add(value)
      markers.add(marker(backend, params.len))
    quoteIdentifier(expression.columnName, backend) & " IN (" &
      markers.join(", ") & ")"
  of ekIsNull:
    quoteIdentifier(expression.columnName, backend) & " IS NULL"
  of ekIsNotNull:
    quoteIdentifier(expression.columnName, backend) & " IS NOT NULL"
  of ekBetween:
    params.add(expression.values[0])
    let lower = marker(backend, params.len)
    params.add(expression.values[1])
    let upper = marker(backend, params.len)
    quoteIdentifier(expression.columnName, backend) & " BETWEEN " &
      lower & " AND " & upper
