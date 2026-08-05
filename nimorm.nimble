version       = "0.1.0"
author        = "nimorm contributors"
description   = "Compile-time model DSL for native Nim ORM models"
license       = "MIT"
srcDir        = "src"
namedBin["nimorm"] = "nimorm/cli/main"

requires "nim >= 2.0.0"
requires "db_connector >= 0.1.0"

task test, "Run the Phase 1 test suite":
  exec "nim check --hints:off -d:nimormPostgres --path:src src/nimorm.nim"
  exec "nim c -r --hints:off --path:src tests/test_model_dsl.nim"
  exec "nim c -r --hints:off --path:src tests/test_compile_failures.nim"
  exec "nim c -r --hints:off --path:src tests/test_schema.nim"
  exec "nim c -r --hints:off --path:src tests/test_sqlite_backend.nim"
  exec "nim c -r --hints:off --path:src tests/test_crud.nim"
  exec "nim c -r --hints:off --path:src tests/test_query_builder.nim"
  exec "nim c -r --hints:off --path:src tests/test_relations.nim"
  exec "nim c -r --hints:off --path:src tests/test_postgres_backend.nim"
  exec "nim c -r --hints:off --path:src tests/test_schema_diff.nim"
  exec "nim c -r --hints:off --path:src tests/test_migrations.nim"
  exec "nim c -r --hints:off --path:src tests/test_cli.nim"
  exec "nim c -r --hints:off --path:src tests/test_validation.nim"
  exec "nim c -r --hints:off --path:src src/nimorm/cli/main.nim -- --help"

task example, "Compile and run the basic model example":
  exec "nim c -r --hints:off --path:src examples/basic_model.nim"

task benchmark, "Run the release-mode SQLite benchmark":
  exec "nim c -d:release -r --hints:off --path:src benchmarks/orm_benchmark.nim"
