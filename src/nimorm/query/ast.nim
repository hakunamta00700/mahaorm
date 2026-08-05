import ../backends/base

type
  ExpressionKind* = enum
    ekCompare,
    ekAnd,
    ekOr,
    ekNot,
    ekLike,
    ekIn,
    ekIsNull,
    ekIsNotNull,
    ekBetween

  CompareOperator* = enum
    coEqual,
    coNotEqual,
    coGreater,
    coGreaterOrEqual,
    coLess,
    coLessOrEqual

  LikeOperator* = enum
    loContains,
    loStartsWith,
    loEndsWith

  SqlExpression* = ref object
    kind*: ExpressionKind
    columnName*: string
    compareOperator*: CompareOperator
    likeOperator*: LikeOperator
    values*: seq[DbValue]
    children*: seq[SqlExpression]

  SortDirection* = enum
    sortAscending,
    sortDescending

  OrderExpression* = object
    columnName*: string
    direction*: SortDirection

  Assignment* = object
    columnName*: string
    value*: DbValue

  CompiledQuery* = object
    sql*: string
    params*: seq[DbValue]
