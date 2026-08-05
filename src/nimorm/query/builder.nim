import std/[options, sequtils, strutils]

import ../backends/base
import ../database
import ../errors
import ../metadata
import ../schema/generator
import ../schema/types
import ./[ast, compiler, expressions]

type
  QuerySet*[T] = object
    db*: Database
    meta*: ModelMeta
    predicate*: SqlExpression
    ordering*: seq[OrderExpression]
    limitValue*: Option[int]
    offsetValue*: int

proc objects*[T](modelType: typedesc[T]; db: Database): QuerySet[T] =
  QuerySet[T](db: db, meta: getModelMeta(modelType))

proc filterExpression*[T](query: QuerySet[T];
                          expression: SqlExpression): QuerySet[T] =
  result = query
  if result.predicate.isNil:
    result.predicate = expression
  else:
    result.predicate = result.predicate and expression

template filter*[T](query: QuerySet[T]; body: untyped): untyped =
  block:
    mixin nimOrmFields
    let it {.inject.} = nimOrmFields(T)
    filterExpression(query, body)

proc orderByExpression*[T](query: QuerySet[T];
                           expression: OrderExpression): QuerySet[T] =
  result = query
  result.ordering.add(expression)

template orderBy*[T](query: QuerySet[T]; body: untyped): untyped =
  block:
    mixin nimOrmFields
    let it {.inject.} = nimOrmFields(T)
    orderByExpression(query, body)

proc limit*[T](query: QuerySet[T]; value: int): QuerySet[T] =
  if value < 0:
    raise newException(ValueError, "query limit must not be negative")
  result = query
  result.limitValue = some(value)

proc offset*[T](query: QuerySet[T]; value: int): QuerySet[T] =
  if value < 0:
    raise newException(ValueError, "query offset must not be negative")
  result = query
  result.offsetValue = value

proc whereSql[T](query: QuerySet[T]; params: var seq[DbValue]): string =
  if query.predicate.isNil:
    return ""
  " WHERE " & compileExpression(query.predicate, query.db.backend, params)

proc orderSql[T](query: QuerySet[T]): string =
  if query.ordering.len == 0:
    return ""
  var parts: seq[string]
  for order in query.ordering:
    parts.add(quoteIdentifier(order.columnName, query.db.backend) &
      (if order.direction == sortAscending: " ASC" else: " DESC"))
  " ORDER BY " & parts.join(", ")

proc rangeSql[T](query: QuerySet[T]): string =
  if query.limitValue.isSome:
    result.add(" LIMIT " & $query.limitValue.get)
  elif query.offsetValue > 0:
    result.add(" LIMIT -1")
  if query.offsetValue > 0:
    result.add(" OFFSET " & $query.offsetValue)

proc selectColumns(meta: ModelMeta; backend: BackendKind): string =
  meta.fields.mapIt(quoteIdentifier(it.columnName, backend)).join(", ")

proc toSql*[T](query: QuerySet[T]): CompiledQuery =
  result.sql = "SELECT " & selectColumns(query.meta, query.db.backend) &
    " FROM " & quoteIdentifier(query.meta.tableName, query.db.backend)
  result.sql.add(query.whereSql(result.params))
  result.sql.add(query.orderSql)
  result.sql.add(query.rangeSql)

proc all*[T](query: QuerySet[T]): seq[T] =
  mixin nimOrmDecode
  let compiled = query.toSql
  for row in query.db.queryRows(compiled.sql, compiled.params):
    result.add(nimOrmDecode(T, row))

proc firstOrNone*[T](query: QuerySet[T]): Option[T] =
  let rows = query.limit(1).all()
  if rows.len == 0: none(T) else: some(rows[0])

proc first*[T](query: QuerySet[T]): T =
  let value = query.firstOrNone
  if value.isNone:
    raise newException(RecordNotFound,
      query.meta.modelName & ": query returned no records")
  value.get

proc get*[T](query: QuerySet[T]): T =
  let rows = query.limit(2).all()
  case rows.len
  of 0:
    raise newException(RecordNotFound,
      query.meta.modelName & ": query returned no records")
  of 1:
    rows[0]
  else:
    raise newException(MultipleRecordsFound,
      query.meta.modelName & ": query returned multiple records")

proc count*[T](query: QuerySet[T]): int64 =
  var params: seq[DbValue]
  var sqlText = "SELECT COUNT(*) FROM " &
    quoteIdentifier(query.meta.tableName, query.db.backend)
  sqlText.add(query.whereSql(params))
  let rows = query.db.queryRows(sqlText, params)
  if rows.len == 0: 0 else: rows[0][0].integerValue

proc exists*[T](query: QuerySet[T]): bool =
  var params: seq[DbValue]
  var sqlText = "SELECT 1 FROM " &
    quoteIdentifier(query.meta.tableName, query.db.backend)
  sqlText.add(query.whereSql(params))
  sqlText.add(" LIMIT 1")
  query.db.queryRows(sqlText, params).len > 0

proc delete*[T](query: QuerySet[T]): int =
  var params: seq[DbValue]
  var sqlText = "DELETE FROM " &
    quoteIdentifier(query.meta.tableName, query.db.backend)
  sqlText.add(query.whereSql(params))
  query.db.execute(sqlText, params)

proc updateAssignments*[T](query: QuerySet[T];
                           assignments: openArray[Assignment]): int =
  if assignments.len == 0:
    return 0
  var params: seq[DbValue]
  var parts: seq[string]
  for assignment in assignments:
    params.add(assignment.value)
    let marker =
      if query.db.backend == sqliteBackend: "?"
      else: "$" & $params.len
    parts.add(quoteIdentifier(assignment.columnName, query.db.backend) &
      " = " & marker)
  var sqlText = "UPDATE " &
    quoteIdentifier(query.meta.tableName, query.db.backend) & " SET " &
    parts.join(", ")
  sqlText.add(query.whereSql(params))
  query.db.execute(sqlText, params)

template update*[T](query: QuerySet[T]; body: untyped): untyped =
  block:
    mixin nimOrmFields
    let it {.inject.} = nimOrmFields(T)
    when body is Assignment:
      updateAssignments(query, [body])
    else:
      updateAssignments(query, body)
