import std/[os, osproc, strutils, unittest]

let projectRoot = currentSourcePath.parentDir.parentDir
let sourceDir = projectRoot / "src"
let fixtureDir = projectRoot / "tests" / "compile_fail"
let nimCompiler = findExe("nim")

proc compileFixture(name: string): tuple[output: string, exitCode: int] =
  let command = quoteShell(nimCompiler) & " c --hints:off --path:" &
    quoteShell(sourceDir) & " " & quoteShell(fixtureDir / name)
  execCmdEx(command, options = {poUsePath, poStdErrToStdOut})

suite "model DSL compile-time diagnostics":
  test "requires maxLength for string fields":
    let compilation = compileFixture("missing_max_length.nim")
    check compilation.exitCode != 0
    check "BadPost.title: stringField maxLength must be at least 1" in compilation.output

  test "rejects a non-positive string length":
    let compilation = compileFixture("max_length_zero.nim")
    check compilation.exitCode != 0
    check "BadPost.title: stringField maxLength must be at least 1" in compilation.output

  test "rejects an unsupported field option":
    let compilation = compileFixture("unknown_option.nim")
    check compilation.exitCode != 0
    check "BadPost.title: unsupported option 'unknownOption' for stringField" in compilation.output

  test "rejects ordering by an unknown field":
    let compilation = compileFixture("unknown_ordering.nim")
    check compilation.exitCode != 0
    check "BadPost.meta.ordering: unknown field 'missing'" in compilation.output

  test "rejects duplicate field declarations":
    let compilation = compileFixture("duplicate_field.nim")
    check compilation.exitCode != 0
    check "BadPost.title: duplicate field declaration" in compilation.output
