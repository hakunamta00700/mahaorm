# nimorm Phase 1 design

## Scope

Phase 1 implements and verifies the compile-time model declaration boundary. It
does not connect to a database and does not claim CRUD, query-builder, relation,
schema-generation, or migration support.

## DSL and observed Nim AST

`model` is an untyped block macro. A probe compiled with Nim 2.2.4 showed these
relevant shapes (irrelevant children omitted):

```text
Command
  Ident "model"
  Ident "Post"
  StmtList
    Asgn
      Ident "title"
      Call
        Ident "stringField"
        ExprEqExpr
          Ident "maxLength"
          IntLit 200
    Call
      Ident "meta"
      StmtList
        Asgn
          Ident "tableName"
          StrLit "posts"
```

The implementation deliberately matches and validates those nodes. It reports
errors with model and field context instead of accepting arbitrary Nim
expressions and failing later during semantic analysis.

## Generated code

Conceptually, this declaration:

```nim
model Post:
  title = stringField(maxLength = 200)
  body = textField()
```

emits the equivalent of:

```nim
type Post* = object
  id*: int64
  title*: string
  body*: string

const PostModelMeta* = ModelMeta(...)
```

It also emits a typedesc-specific metadata accessor used by the public generic
APIs. Nullable fields are `Option[T]`; non-null fields are exactly `T`. Field
declarations are macro input and never survive as runtime wrapper objects.

Unless `meta.autoPrimaryKey = false` or an explicit primary key exists, the
macro inserts a native `int64` `id` field. This policy is recorded in metadata
so schema generation can consume the same decision in a later phase.

## Metadata storage

Each model owns an exported immutable `ModelNameModelMeta` constant. Public
lookups are typedesc based:

```nim
getModelMeta(Post)
getFieldMeta(Post, "title")
tableName(Post)
primaryKeyField(Post)
```

The model constant is usable in `static` assertions. A runtime string lookup is
provided only where the requested API itself uses a string; generated CRUD and
query code can consume typed metadata directly in later phases.

## Macro versus pragma

A pragma can annotate an existing declaration, but the intended DSL needs to
own a block grammar and generate both a native type and related metadata. A
macro therefore provides one validation point, clearer diagnostics, and a
single source of truth. Adding pragmas would not remove the need for a macro and
would split field information between two syntactic mechanisms.

## Validation and diagnostics

Phase 1 supports `stringField` and `textField`. It validates field syntax,
supported options, duplicate identifiers and columns, required positive
`maxLength`, length bounds, null primary keys, meta syntax, ordering fields,
composite constraints, and indexes at compile time. Errors include the model,
field, and option whenever applicable.

Identifiers are compared with Nim-style normalization (case-insensitive and
underscore-insensitive) to catch declarations that the compiler itself would
treat as collisions.

## Extension boundaries and risks

- `field_defs.nim` owns stable field-kind vocabulary.
- `metadata.nim` contains backend-independent descriptions and lookup APIs.
- `model_macro.nim` alone parses DSL AST and generates native declarations.
- Database execution and SQL dialects will live outside all three modules.

The primary compatibility risk is a future Nim release changing parser AST
shapes. The recorded probe and compile-failure fixtures make that visible.
Relations require symbol resolution and cycle handling and are intentionally a
later phase. Default values also need coordinated construction/insert semantics;
accepting them only as decorative metadata in Phase 1 would be misleading, so
they are not yet accepted.

## Phase 2 hazards

SQLite CRUD must preserve parameterized values, distinguish structured database
errors, serialize `Option` correctly, assign auto-generated IDs without Field
wrappers, and keep SQLite-specific behavior behind a backend boundary. Those
requirements are not implemented by Phase 1.
