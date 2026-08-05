import ./backends/base
import ./backends/sqlite
import ./errors

proc savepointName(depth: int): string =
  "nimorm_savepoint_" & $depth

proc beginTransaction*(db: Database) =
  if db.isNil or db.closed:
    raise newException(TransactionError, "cannot begin transaction on a closed connection")
  if db.transactionDepth == 0:
    discard db.execute("BEGIN")
  else:
    discard db.execute("SAVEPOINT " & savepointName(db.transactionDepth))
  inc db.transactionDepth

proc commitTransaction*(db: Database) =
  if db.transactionDepth <= 0:
    raise newException(TransactionError, "no transaction is active")
  dec db.transactionDepth
  if db.transactionDepth == 0:
    discard db.execute("COMMIT")
  else:
    discard db.execute("RELEASE SAVEPOINT " & savepointName(db.transactionDepth))

proc rollbackTransaction*(db: Database) =
  if db.transactionDepth <= 0:
    raise newException(TransactionError, "no transaction is active")
  dec db.transactionDepth
  if db.transactionDepth == 0:
    discard db.execute("ROLLBACK")
  else:
    let savepoint = savepointName(db.transactionDepth)
    discard db.execute("ROLLBACK TO SAVEPOINT " & savepoint)
    discard db.execute("RELEASE SAVEPOINT " & savepoint)

template transaction*(db: Database; body: untyped): untyped =
  {.push warning[UnreachableCode]: off.}
  block:
    beginTransaction(db)
    try:
      body
      commitTransaction(db)
    except CatchableError:
      rollbackTransaction(db)
      raise
  {.pop.}
