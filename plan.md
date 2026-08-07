# Plan: Django ORM parity roadmap

## Goal
Close the highest-impact gaps between mahaorm 0.1.0 and Django ORM without giving up its compile-time model DSL, typed query API, parameterized SQL guarantees, or explicit database-I/O model. Deliver each capability as a separately releasable, tested change.

## Scope
- In: relational query traversal and eager loading, projections and aggregation, expression and write APIs, many-to-many support, selected schema/migration improvements, and a separately designed async/multi-backend path.
- Out: a byte-for-byte Django API clone, Django web-framework integrations, hidden lazy relation queries, and an unreviewed automatic SQLite table rebuild.

## Assumptions and constraints
- `mahaorm` is a synchronous Nim 2.x ORM; SQLite is always available and PostgreSQL is gated by `-d:mahaormPostgres`.
- The current query implementation is a single-table AST in `src/mahaorm/query/{ast,builder,compiler,expressions}.nim`; relation metadata and access live in `src/mahaorm/relations.nim` and generated model macros.
- Every new SQL feature must compile identifiers from metadata and bind runtime values as parameters; raw SQL remains an explicit escape hatch.
- SQLite and PostgreSQL behavior must either match or expose a documented capability/error rather than silently degrade.
- Existing tests in `tests/` are standalone Nim programs invoked by `mahaorm.nimble`; add focused tests alongside the closest suite.
- Features are ordered by dependency and user impact. The async and additional-backend work is intentionally deferred until the synchronous query contract is stable.

## Checklist
- [x] Establish a parity acceptance matrix and regression fixtures for relational querying
  - Scope: Add shared `User`/`Post`/`Profile`/tag fixtures and focused assertions in `tests/test_query_builder.nim`, `tests/test_relations.nim`, and a new capability matrix in `docs/`; record SQL and result-shape expectations for SQLite and PostgreSQL.
  - Done when: Each planned query feature has a named acceptance case, including nullable relations, duplicate join rows, empty prefetch sets, and parameterized values; the baseline confirms current behavior before it changes.
  - Validation: Run the affected test programs with `nim c -r --hints:off --path:src`; inspect generated SQL through `toSql()` assertions.

- [x] Introduce typed join paths and multi-hop relation traversal in the query AST
  - Scope: Extend `src/mahaorm/query/ast.nim`, `expressions.nim`, `compiler.nim`, and `builder.nim`; expose generated relation-path metadata from `model_macro.nim` and `relations.nim` for forward and reverse FK/one-to-one joins.
  - Done when: Filtering and ordering can traverse one and multiple declared FK/one-to-one relations with deterministic aliases, nullable-relation semantics, and no runtime identifier interpolation.
  - Validation: Add SQLite SQL/result tests for forward, reverse, nullable, and multi-hop paths; compile PostgreSQL SQL with `-d:mahaormPostgres`; run `nimble test`.

- [x] Add joined eager loading with `selectRelated`
  - Scope: Build a joined-row hydration plan in `src/mahaorm/query/` and add public APIs plus examples in `src/mahaorm/relations.nim`, `docs/relations.md`, and `tests/test_relations.nim`.
  - Done when: Explicitly requested FK/one-to-one targets are hydrated from one query, absent nullable targets remain `Option.none`, and default queries retain today’s explicit-I/O behavior.
  - Validation: Assert query-log count is one for selected related records, verify nullable and nested cases, and run the relation and CRUD test suites.

- [x] Add batched collection eager loading with `prefetchRelated`
  - Scope: Add a prefetch-plan/result attachment API for reverse FK and one-to-one collections in `src/mahaorm/relations.nim` and query execution helpers; document ownership and lifetime of prefetched data.
  - Done when: A root collection plus requested reverse relation executes a bounded number of queries independent of root row count, preserves root ordering, and returns empty collections for targets without children.
  - Validation: Add query-log assertions for zero, one, and many root rows; run SQLite relation tests and PostgreSQL SQL compilation tests.

- [ ] Add many-to-many metadata, schema generation, and explicit through-model support
  - Scope: Extend `field_defs.nim`, `model_macro.nim`, `metadata.nim`, `schema/generator.nim`, snapshot/diff types, migration operations, and relation APIs; support an implicit join table and a declared through model with compile-time validation.
  - Done when: Models can define many-to-many relations, generate stable join-table DDL and migrations, manage links through typed APIs, and traverse/prefetch the relation without duplicate root records.
  - Validation: Add DSL compile-failure tests, schema-diff tests, migration round trips, and relation CRUD tests on SQLite; compile PostgreSQL DDL.

- [ ] Implement projections, default ordering, distinctness, and set-query operations
  - Scope: Extend `QuerySet` and compiler support in `src/mahaorm/query/`; honor `ModelMeta.ordering`; add typed projection result APIs, `distinct`, `exclude`, and compatible `union`/`intersection`/`difference` operations.
  - Done when: Callers can select only required fields, receive a statically defined result shape, reset or override default ordering, remove duplicate join rows, and receive explicit errors for backend-incompatible set operations.
  - Validation: Add projection type/SQL tests, default-ordering regressions, duplicate-row tests, and SQLite/PostgreSQL compiler coverage in `tests/test_query_builder.nim`.

- [ ] Build composable expressions, aggregation, grouping, and annotations
  - Scope: Add typed field-to-field arithmetic, literal values, database-function nodes, conditional expressions, aggregate nodes, aliases, `GROUP BY`/`HAVING`, and aggregate result decoding in the query AST/compiler and public API.
  - Done when: `sum`, `avg`, `min`, `max`, and `count` work for whole-query and grouped results; annotations can be reused in filters/orderings; unsupported function/backend combinations fail clearly.
  - Validation: Add numeric, null, empty-set, grouped, relation-aggregate, and parameter-binding tests; compile representative SQL for both backends and run `nimble test`.

- [ ] Add subquery, existence, and window-expression support after expression foundations land
  - Scope: Extend the expression AST/compiler with correlated subqueries, `Exists`, scalar subqueries, window specifications, partitions, frames, and backend capability checks.
  - Done when: Outer-field references are scoped safely, subqueries bind parameters in stable order, and unsupported SQLite/PostgreSQL version features return a structured error before execution.
  - Validation: Add compiler and integration tests for correlated existence, aggregate subqueries, ranking, and frame boundaries; verify no runtime values appear in generated SQL.

- [ ] Add high-level write APIs, atomic assignments, and locking contracts
  - Scope: Extend `crud.nim`, query assignments, expressions, and backend execution for `bulkCreate`, `bulkUpdate`, `getOrCreate`, `updateOrCreate`, backend-aware upsert, field-expression updates, and `selectForUpdate`.
  - Done when: Bulk operations use bounded statements, atomic increments do not read-modify-write in Nim, conflict targets are explicit, and SQLite locking limitations are documented rather than emulated incorrectly.
  - Validation: Add transaction/rollback, duplicate-key, concurrent-update SQL, batch-size, and PostgreSQL `FOR UPDATE` compiler tests; run CRUD and transaction regressions.

- [ ] Expand field, constraint, and index metadata without weakening compile-time validation
  - Scope: Add choice/enum validation, common scalar field mappings, generated/computed fields where supported, `CheckConstraint`, conditional/functional unique constraints, and functional/conditional/covering indexes across model metadata, schema generation, and snapshots.
  - Done when: The DSL rejects invalid option combinations at compile time, generated DDL is capability-aware, and metadata changes are detected by schema diffs.
  - Validation: Extend model DSL compile-failure tests, schema generation snapshots, schema-diff tests, and backend-specific DDL compiler tests.

- [ ] Add data and custom migration operations with explicit SQLite rebuild workflows
  - Scope: Extend `migration/operations.nim`, `compiler.nim`, `executor.nim`, `format.nim`, CLI, and documentation with reviewed `RunSql`/Nim callback/data-operation equivalents, reversible metadata where possible, and an explicit table-rebuild operation that requires a copy/backfill plan.
  - Done when: Data and custom SQL migrations are serializable, ordered, transactional when supported, auditable in migration history, and SQLite rebuilds cannot silently lose or miscast data.
  - Validation: Add migration JSON round trips, dependency/rollback/review-gate tests, SQLite rebuild failure/success fixtures, and PostgreSQL SQL compilation coverage.

- [ ] Design and implement an opt-in asynchronous database contract
  - Scope: Define separate async `Database`/query/result-lifetime interfaces and an async backend adapter without placing blocking SQLite/libpq calls behind async syntax; document connection ownership and transaction semantics.
  - Done when: Async callers can build queries without I/O and await terminal operations through an opt-in API, while the synchronous API remains source-compatible and no connection is used concurrently outside its contract.
  - Validation: Add compile-time API separation checks, async integration tests for success/error/rollback paths, and run all synchronous tests unchanged.

- [ ] Add multi-database routing and evaluate additional backend implementations
  - Scope: Introduce named database configuration and explicit routing/selection APIs; assess MySQL/MariaDB and Oracle against the stabilized backend contract before adding each in its own follow-up commit series.
  - Done when: A query and migration can select a named configured database deterministically, cross-database relations fail explicitly, and any newly accepted backend has a capability matrix plus integration suite.
  - Validation: Add routing unit tests, migration-target tests, cross-database rejection tests, and backend-specific CI/integration checks before documenting support.

- [ ] Publish migration guidance, examples, and a versioned capability matrix for the completed stages
  - Scope: Update `README.md`, `docs/queries.md`, `docs/relations.md`, `docs/fields.md`, `docs/migrations.md`, `docs/backends.md`, and examples to distinguish shipped APIs from deferred work and document upgrade boundaries.
  - Done when: Every public API added above has a minimal runnable example, backend caveats, error behavior, and migration notes; no 0.1.0 non-goal statement contradicts an implemented feature.
  - Validation: Run `nimble example`, `nimble test`, documentation link/reference search, and review the capability matrix against exported symbols.

## Completion condition
All checklist items are checked, their validation passes, and each completed item is committed with its plan update.
