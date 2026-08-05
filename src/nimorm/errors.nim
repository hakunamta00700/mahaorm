type
  OrmError* = object of CatchableError
  ConnectionError* = object of OrmError
  SqlExecutionError* = object of OrmError
  ConstraintViolation* = object of SqlExecutionError
  UniqueViolation* = object of ConstraintViolation
  ForeignKeyViolation* = object of ConstraintViolation
  NotNullViolation* = object of ConstraintViolation
  RecordNotFound* = object of OrmError
  MultipleRecordsFound* = object of OrmError
  SerializationError* = object of OrmError
  TransactionError* = object of OrmError
