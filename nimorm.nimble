version       = "0.1.0"
author        = "nimorm contributors"
description   = "Compile-time model DSL for native Nim ORM models"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.0.0"
requires "db_connector >= 0.1.0"

task test, "Run the Phase 1 test suite":
  exec "nim c -r --hints:off --path:src tests/test_model_dsl.nim"
  exec "nim c -r --hints:off --path:src tests/test_compile_failures.nim"
  exec "nim c -r --hints:off --path:src tests/test_schema.nim"

task example, "Compile and run the basic model example":
  exec "nim c -r --hints:off --path:src examples/basic_model.nim"
