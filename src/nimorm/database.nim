import std/macros

import ./backends/[base, sqlite]
import ./metadata

export base, sqlite

macro createTables*(db: typed; modelTypes: varargs[typed]): untyped =
  result = newStmtList()
  for modelType in modelTypes:
    result.add quote do:
      createTable(`db`, getModelMeta(`modelType`))
