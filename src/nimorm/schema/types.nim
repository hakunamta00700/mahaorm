type
  BackendKind* = enum
    sqliteBackend,
    postgresBackend

  SchemaError* = object of CatchableError
