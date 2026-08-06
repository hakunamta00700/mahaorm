# Contributing to nimorm

Thanks for helping make Nim database code easier to understand at compile time
and safer at runtime.

## Before opening a change

- Use an issue for behavior changes large enough to affect the public API,
  schema format, generated code, or migration safety rules.
- Keep pull requests focused. A field mapping and a query planner rewrite should
  not arrive as one review unit.
- Never include credentials, production databases, or generated binaries.

## Development setup

Requirements are Nim 2.0+, Nimble, a C compiler, and Git.

```shell
git clone https://github.com/hakunamta00700/mahaorm.git
cd mahaorm
nimble install -d
nimble develop
nimble check
nimble test
nimble example
```

`nimble test` checks the optional PostgreSQL symbols without requiring a server.
To load libpq and run the PostgreSQL backend test:

```shell
nim c -r -d:nimormPostgres --path:src tests/test_postgres_backend.nim
```

The server integration test additionally requires
`-d:nimormPostgresIntegration` and the `NIMORM_PG_*` variables documented in
[`docs/backends.md`](docs/backends.md).

## Project layout

```text
src/nimorm/          public ORM implementation
src/nimorm/backends/ SQLite and optional PostgreSQL execution
src/nimorm/query/    typed expression AST and compiler
src/nimorm/schema/   DDL, snapshots, and diffs
src/nimorm/migration migration format, compiler, executor, and history
tests/               executable unit and integration-style tests
examples/            programs compiled by `nimble example`
docs/                public user documentation
benchmarks/          release-mode microbenchmark and recorded baseline
```

## Change guidelines

- Keep generated model fields native. Do not introduce runtime field wrappers
  into application objects.
- Keep runtime values out of generated SQL strings. Use `DbValue` parameters.
- Add compile-failure coverage for invalid DSL forms.
- Add SQLite execution coverage for behavior shared by database backends.
- Treat migration safety classification changes as user-visible behavior.
- Update the relevant guide and reference page with public API changes.
- Put runnable documentation examples in `examples/` and add them to the
  `example` Nimble task.

Run `nimble benchmark` when changing serialization, query compilation, or row
mapping. Update `benchmarks/results.md` only when recording a deliberate new
baseline on a stated environment.

## Commits and pull requests

Use short, focused commits. This repository currently uses Korean commit
subjects for maintained work; a clear Korean subject is preferred. Explain the
user-facing reason in the body when the diff is not self-explanatory.

A pull request should include:

- the problem and intended user behavior;
- tests run and their results;
- migration or compatibility impact;
- documentation changed;
- benchmark results when a hot path changed.

By contributing, you agree that your contribution is licensed under the
[MIT License](LICENSE).
