import std/[options, sequtils, strutils]

import ../backends/base
import ../crud
import ../database
import ../errors
import ../metadata
import ../schema/generator
import ../schema/types
import ./[ast, compiler, expressions]

type
  Manager*[T] = object
    ## Model-level entry point. It creates immutable query sets and owns no
    ## query state itself.
    db*: Database
    meta*: ModelMeta

  QuerySet*[T] = object
    db*: Database
    meta*: ModelMeta
    predicate*: SqlExpression
    ordering*: seq[OrderExpression]
    limitValue*: Option[int]
    offsetValue*: int
    distinctValue*: bool
    emptyValue*: bool
    explicitOrdering*: bool

proc modelOrdering(meta: ModelMeta): seq[OrderExpression] =
  for entry in meta.ordering:
    let descending = entry.startsWith("-")
    let fieldName = if descending: entry[1 .. ^1] else: entry
    for field in meta.fields:
      if field.name == fieldName:
        result.add(OrderExpression(
          columnName: field.columnName,
          direction: if descending: sortDescending else: sortAscending))
        break

proc objects*[T](modelType: typedesc[T]; db: Database): Manager[T] =
  Manager[T](db: db, meta: getModelMeta(modelType))

proc getQuerySet*[T](manager: Manager[T]): QuerySet[T] =
  ## Returns a fresh query set so manager calls never share mutable query
  ## state. Model-level default ordering is applied here.
  QuerySet[T](db: manager.db, meta: manager.meta,
    ordering: modelOrdering(manager.meta))

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

template exclude*[T](query: QuerySet[T]; body: untyped): untyped =
  block:
    mixin nimOrmFields
    let it {.inject.} = nimOrmFields(T)
    filterExpression(query, not (body))

proc orderByExpression*[T](query: QuerySet[T];
                           expression: OrderExpression): QuerySet[T] =
  result = query
  if not result.explicitOrdering:
    result.ordering.setLen(0)
    result.explicitOrdering = true
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

proc reverse*[T](query: QuerySet[T]): QuerySet[T] =
  if query.limitValue.isSome or query.offsetValue > 0:
    raise newException(ValueError, "cannot reverse a sliced query")
  result = query
  for ordering in result.ordering.mitems:
    ordering.direction =
      if ordering.direction == sortAscending: sortDescending
      else: sortAscending

proc `distinct`*[T](query: QuerySet[T]): QuerySet[T] =
  result = query
  result.distinctValue = true

proc none*[T](query: QuerySet[T]): QuerySet[T] =
  result = query
  result.emptyValue = true

proc whereSql[T](query: QuerySet[T]; params: var seq[DbValue]): string =
  if query.emptyValue:
    return " WHERE 0 = 1"
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
  result.sql = "SELECT " & (if query.distinctValue: "DISTINCT " else: "") &
    selectColumns(query.meta, query.db.backend) &
    " FROM " & quoteIdentifier(query.meta.tableName, query.db.backend)
  result.sql.add(query.whereSql(result.params))
  result.sql.add(query.orderSql)
  result.sql.add(query.rangeSql)

proc all*[T](query: QuerySet[T]): seq[T] =
  mixin nimOrmDecode
  let compiled = query.toSql
  for row in query.db.queryRows(compiled.sql, compiled.params):
    result.add(nimOrmDecode(T, row))

proc capped[T](query: QuerySet[T]; rowCount: int): QuerySet[T] =
  result = query
  if result.limitValue.isNone or result.limitValue.get > rowCount:
    result.limitValue = some(rowCount)

proc orderedByPrimaryKey[T](query: QuerySet[T];
                            direction: SortDirection): QuerySet[T] =
  result = query
  if result.ordering.len > 0:
    return
  for field in result.meta.fields:
    if field.primaryKey:
      result.ordering.add(OrderExpression(
        columnName: field.columnName, direction: direction))
      return

proc firstOrNone*[T](query: QuerySet[T]): Option[T] =
  let rows = query.orderedByPrimaryKey(sortAscending).capped(1).all()
  if rows.len == 0: none(T) else: some(rows[0])

proc first*[T](query: QuerySet[T]): T =
  let value = query.firstOrNone
  if value.isNone:
    raise newException(RecordNotFound,
      query.meta.modelName & ": query returned no records")
  value.get

proc get*[T](query: QuerySet[T]): T =
  let rows = query.capped(2).all()
  case rows.len
  of 0:
    raise newException(RecordNotFound,
      query.meta.modelName & ": query returned no records")
  of 1:
    rows[0]
  else:
    raise newException(MultipleRecordsFound,
      query.meta.modelName & ": query returned multiple records")

proc withPrimaryKey[T](query: QuerySet[T]; value: DbValue): QuerySet[T] =
  for field in query.meta.fields:
    if field.primaryKey:
      return query.filterExpression(SqlExpression(
        kind: ekCompare,
        columnName: field.columnName,
        compareOperator: coEqual,
        values: @[value]))
  raise newException(SerializationError,
    query.meta.modelName & ": model has no primary key")

proc get*[T](query: QuerySet[T]; primaryKey: DbValue): T =
  query.withPrimaryKey(primaryKey).get()

proc get*[T](query: QuerySet[T]; primaryKey: int64): T =
  query.get(dbValue(primaryKey))

proc get*[T](query: QuerySet[T]; primaryKey: int): T =
  query.get(dbValue(primaryKey))

proc get*[T](query: QuerySet[T]; primaryKey: string): T =
  query.get(dbValue(primaryKey))

proc getOrNone*[T](query: QuerySet[T]): Option[T] =
  try:
    some(query.get())
  except RecordNotFound:
    none(T)

proc getOrNone*[T](query: QuerySet[T]; primaryKey: DbValue): Option[T] =
  query.withPrimaryKey(primaryKey).getOrNone()

proc getOrNone*[T](query: QuerySet[T]; primaryKey: int64): Option[T] =
  query.getOrNone(dbValue(primaryKey))

proc getOrNone*[T](query: QuerySet[T]; primaryKey: int): Option[T] =
  query.getOrNone(dbValue(primaryKey))

proc getOrNone*[T](query: QuerySet[T]; primaryKey: string): Option[T] =
  query.getOrNone(dbValue(primaryKey))

proc lastOrNone*[T](query: QuerySet[T]): Option[T] =
  if query.limitValue.isSome or query.offsetValue > 0:
    raise newException(ValueError, "cannot get the last row of a sliced query")
  var reversed = query
  if reversed.ordering.len == 0:
    reversed = reversed.orderedByPrimaryKey(sortDescending)
  else:
    for ordering in reversed.ordering.mitems:
      ordering.direction =
        if ordering.direction == sortAscending: sortDescending
        else: sortAscending
  reversed.firstOrNone()

proc last*[T](query: QuerySet[T]): T =
  let value = query.lastOrNone()
  if value.isNone:
    raise newException(RecordNotFound,
      query.meta.modelName & ": query returned no records")
  value.get

proc count*[T](query: QuerySet[T]): int64 =
  let compiled = query.toSql()
  let sqlText = "SELECT COUNT(*) FROM (" & compiled.sql &
    ") AS " & quoteIdentifier("nimorm_count", query.db.backend)
  let rows = query.db.queryRows(sqlText, compiled.params)
  if rows.len == 0: 0 else: rows[0][0].integerValue

proc exists*[T](query: QuerySet[T]): bool =
  if query.limitValue.isSome and query.limitValue.get == 0:
    return false
  let compiled = query.capped(1).toSql()
  query.db.queryRows(compiled.sql, compiled.params).len > 0

proc contains*[T](query: QuerySet[T]; value: T): bool =
  mixin nimOrmPrimaryKey
  query.withPrimaryKey(nimOrmPrimaryKey(value)).exists()

proc create*[T](query: QuerySet[T]; value: T): T =
  ## Creates a model value through the query set's database. Existing query
  ## predicates do not modify the value, matching Manager/QuerySet create APIs.
  query.db.insert(value)

proc ensureWritable[T](query: QuerySet[T]) =
  if query.limitValue.isSome or query.offsetValue > 0:
    raise newException(ValueError,
      "cannot update or delete a sliced query")

proc delete*[T](query: QuerySet[T]): int =
  query.ensureWritable()
  if query.emptyValue:
    return 0
  var params: seq[DbValue]
  var sqlText = "DELETE FROM " &
    quoteIdentifier(query.meta.tableName, query.db.backend)
  sqlText.add(query.whereSql(params))
  query.db.execute(sqlText, params)

proc updateAssignments*[T](query: QuerySet[T];
                           assignments: openArray[Assignment]): int =
  query.ensureWritable()
  if query.emptyValue:
    return 0
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

template filter*[T](manager: Manager[T]; body: untyped): untyped =
  filter(manager.getQuerySet(), body)

template exclude*[T](manager: Manager[T]; body: untyped): untyped =
  exclude(manager.getQuerySet(), body)

template orderBy*[T](manager: Manager[T]; body: untyped): untyped =
  orderBy(manager.getQuerySet(), body)

proc limit*[T](manager: Manager[T]; value: int): QuerySet[T] =
  manager.getQuerySet().limit(value)

proc offset*[T](manager: Manager[T]; value: int): QuerySet[T] =
  manager.getQuerySet().offset(value)

proc reverse*[T](manager: Manager[T]): QuerySet[T] =
  manager.getQuerySet().reverse()

proc `distinct`*[T](manager: Manager[T]): QuerySet[T] =
  manager.getQuerySet().distinct()

proc none*[T](manager: Manager[T]): QuerySet[T] =
  manager.getQuerySet().none()

proc toSql*[T](manager: Manager[T]): CompiledQuery =
  manager.getQuerySet().toSql()

proc all*[T](manager: Manager[T]): seq[T] =
  manager.getQuerySet().all()

proc firstOrNone*[T](manager: Manager[T]): Option[T] =
  manager.getQuerySet().firstOrNone()

proc first*[T](manager: Manager[T]): T =
  manager.getQuerySet().first()

proc lastOrNone*[T](manager: Manager[T]): Option[T] =
  manager.getQuerySet().lastOrNone()

proc last*[T](manager: Manager[T]): T =
  manager.getQuerySet().last()

proc getOrNone*[T](manager: Manager[T]): Option[T] =
  manager.getQuerySet().getOrNone()

proc getOrNone*[T](manager: Manager[T]; primaryKey: DbValue): Option[T] =
  manager.getQuerySet().getOrNone(primaryKey)

proc getOrNone*[T](manager: Manager[T]; primaryKey: int64): Option[T] =
  manager.getQuerySet().getOrNone(primaryKey)

proc getOrNone*[T](manager: Manager[T]; primaryKey: int): Option[T] =
  manager.getQuerySet().getOrNone(primaryKey)

proc getOrNone*[T](manager: Manager[T]; primaryKey: string): Option[T] =
  manager.getQuerySet().getOrNone(primaryKey)

proc get*[T](manager: Manager[T]): T =
  manager.getQuerySet().get()

proc get*[T](manager: Manager[T]; primaryKey: DbValue): T =
  manager.getQuerySet().get(primaryKey)

proc get*[T](manager: Manager[T]; primaryKey: int64): T =
  manager.getQuerySet().get(primaryKey)

proc get*[T](manager: Manager[T]; primaryKey: int): T =
  manager.getQuerySet().get(primaryKey)

proc get*[T](manager: Manager[T]; primaryKey: string): T =
  manager.getQuerySet().get(primaryKey)

proc count*[T](manager: Manager[T]): int64 =
  manager.getQuerySet().count()

proc exists*[T](manager: Manager[T]): bool =
  manager.getQuerySet().exists()

proc contains*[T](manager: Manager[T]; value: T): bool =
  manager.getQuerySet().contains(value)

proc create*[T](manager: Manager[T]; value: T): T =
  manager.getQuerySet().create(value)

template update*[T](manager: Manager[T]; body: untyped): untyped =
  update(manager.getQuerySet(), body)
