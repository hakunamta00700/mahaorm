# MahaORM

MahaORM은 Nim package와 CLI에서는 **`nimorm`**이라는 이름을 사용하는 Nim 2.x용
compile-time model DSL 및 동기식 ORM입니다. 모델 선언을 native Nim object,
불변 metadata, serializer, validator, typed field·relation reference로 컴파일하며
runtime field wrapper나 숨겨진 lazy query를 만들지 않습니다.

> **개발 상태:** `0.1.0` 개발 프리뷰입니다. API와 snapshot format이 바뀔 수
> 있으며, 아직 안정 버전이나 모든 운영 환경에 대한 production 보증을 의미하지
> 않습니다.

## 설계 원칙

- 모델·필드·제약 조건 오류를 가능한 한 compile time에 발견합니다.
- 애플리케이션 값은 일반 Nim object와 `Option[T]`로 유지합니다.
- SQL 값은 문자열 보간 대신 typed parameter로 전달합니다.
- relation 조회와 validation, migration 위험 승인은 명시적으로 실행합니다.
- SQLite와 PostgreSQL의 dialect 차이는 backend·compiler 경계에 둡니다.
- blocking database 호출을 async 문법 뒤에 숨기지 않습니다.

## 현재 제공 범위

| 영역 | 제공 기능 |
| --- | --- |
| 모델 | `model` DSL, native object 생성, immutable metadata, compile-time diagnostics, 자동 `int64` primary key |
| 필드 | 문자열·텍스트·정수·실수·Decimal·Bool·Date·DateTime·UUID·JSON·Binary, nullable `Option[T]` |
| Validation | 길이·pattern·범위·custom validator, 구조화된 validation issue |
| CRUD | insert, get/getOrNone, update, delete, generated ID와 timestamp 처리 |
| Typed query | filter, order, limit, offset, count, exists, bulk update/delete, inspectable parameterized SQL |
| Relation | foreign key, one-to-one, 명시적 forward/reverse lookup, compile-time `onDelete` 검증 |
| Transaction | SQLite transaction과 nested savepoint, backend별 structured database error |
| Schema | SQLite/PostgreSQL DDL 생성, versioned JSON snapshot, schema diff |
| Migration | dependency·history·idempotency, destructive/review safety gate, SQLite migration CLI, PostgreSQL SQL 생성 |
| Backend | 기본 SQLite, `-d:nimormPostgres`로 선택하는 PostgreSQL/libpq backend |
| 관측성 | opt-in query logging, 민감 field·parameter redaction |

## 요구 사항

- Nim `>= 2.0.0`
- Nimble
- 개발·테스트 기준 버전: Nim `2.2.4`
- `db_connector` package
- PostgreSQL 사용 시 compatible `libpq` runtime

## 설치 및 개발

Package를 설치하려면:

```text
nimble install https://github.com/hakunamta00700/mahaorm
```

저장소에서 개발하려면:

```text
git clone https://github.com/hakunamta00700/mahaorm.git
cd mahaorm
nimble install -d
nimble test
nimble example
```

별도 consumer project에서 checkout을 직접 사용하려면 저장소에서
`nimble develop`을 실행하거나 consumer의 Nimble dependency source를 지정합니다.

## 빠른 시작

```nim
import nimorm

model Post:
  title = stringField(maxLength = 200, minLength = 3)
  body = textField(nullable = true)
  views = integerField(default = 0)

  meta:
    tableName = "posts"

let db = openSqlite(":memory:")
defer: db.close()

db.createTables(Post)

var post = Post(title: "Nim ORM", views: 1)
let issues = post.validate()
if issues.len == 0:
  post = db.insert(post)

let posts = Post.objects(db)
  .filter(it.title.contains("Nim") and it.views >= 0)
  .orderBy(it.id.desc)
  .limit(20)
  .all()

echo post.id
echo posts[0].title
```

`createTables`는 테스트와 초기 prototype에 적합합니다. 보존해야 하는 데이터의
schema를 변경할 때는 versioned snapshot과 migration을 사용하세요.

## 모델과 필드

`model` macro는 exported object type, metadata, encode/decode, validation,
`FieldRef`, `RelationRef`를 생성합니다. 기본적으로 다음 primary key가 추가됩니다.

```nim
id = bigIntegerField(primaryKey = true, autoIncrement = true)
```

`meta.autoPrimaryKey = false`로 끄고 직접 primary key를 선언할 수 있습니다.
`meta`는 `tableName`, `ordering`, `uniqueTogether`, `indexes`, `managed`,
`abstract` 등의 option을 지원합니다. 정확한 field mapping과 option은
[필드 및 validation 문서](docs/fields.md)를 참고하세요.

Validation은 저장 시 자동 실행되지 않습니다. 애플리케이션 입력은 `validate()`로
검사하고, NOT NULL·UNIQUE·foreign key는 데이터베이스의 최종 무결성 경계로
유지합니다.

## Typed query와 SQL 안전성

`filter`, `orderBy`, `update`의 `it`은 compile-time typed field reference입니다.
알 수 없는 field나 호환되지 않는 타입 비교는 컴파일에 실패합니다.

지원 predicate:

```text
==  !=  <  <=  >  >=  between  inList
contains  startsWith  endsWith  isNull  isNotNull
```

Terminal API:

```text
all  first  firstOrNone  get  count  exists  update  delete
```

`toSql()`은 SQL 문자열과 parameter sequence가 분리된 `CompiledQuery`를
반환합니다. SQLite는 `?`, PostgreSQL은 `$1`, `$2` placeholder를 사용하며
LIKE metacharacter도 escape합니다.

```nim
let compiled = Post.objects(db)
  .filter(it.title.contains("100% Nim"))
  .toSql()

echo compiled.sql
echo compiled.params.len
```

Field나 column 이름에 `password`, `token`, `secret`, `apiKey`가 포함되면 query
log에서 값이 자동으로 가려집니다. Raw SQL의 민감 값은
`sensitiveDbValue(dbValue(value))`로 표시하세요.

## Relation

`foreignKey`와 `oneToOneField`는 target model과 `onDelete` 정책을 요구합니다.
모델에는 proxy object 대신 target ID만 저장됩니다.

```nim
model User:
  name = stringField(maxLength = 100)

model Post:
  title = stringField(maxLength = 200)
  author = foreignKey(User, onDelete = Cascade, relatedName = "posts")
```

```nim
let author = db.fetchRelated(post, relations(Post).author)
let authoredPosts = db.related(author, relations(Post).author).all()
```

조회는 항상 명시적으로 발생합니다. `selectRelated`·`prefetchRelated`와 multi-hop
filter traversal은 `0.1.0`에서 지원하지 않습니다.

## Schema snapshot과 migration

모델을 변경할 때 명시적인 versioned JSON snapshot을 생성합니다.

```nim
import nimorm

schemaSnapshot(User, Post).saveSnapshot("schema/current.json")
```

`nimorm` CLI는 Nimble 설치 또는 build 후 사용할 수 있습니다.

```text
nimorm makemigrations <previous.json|-> <current.json> <name> <output.json> [dependency]
nimorm sqlmigrate <migration.json> <sqlite|postgres>
nimorm migrate <sqlite.db> <migration.json> [--allow-destructive] [--allow-review]
nimorm migrations <sqlite.db>
```

Migration은 dependency와 적용 history를 검사하고 operation과 history row를 하나의
transaction에서 처리합니다. Destructive operation과 data/type 결정을 요구하는
operation은 각각 명시적 flag 없이는 거부됩니다.

SQLite table rebuild가 필요한 column·foreign key·composite UNIQUE 변경은
자동 data copy나 cast를 추측하지 않고 `MigrationError`로 중단합니다. 발생한 SQL과
operation의 `reason`을 검토한 후 애플리케이션에 맞는 rebuild 절차를 작성해야 합니다.

## Database backend

### SQLite

SQLite는 기본 backend이며 foreign key enforcement를 활성화합니다. Nested
transaction은 savepoint를 사용합니다.

```nim
let db = openSqlite("app.sqlite3")
defer: db.close()
```

### PostgreSQL

PostgreSQL은 SQLite-only binary가 libpq를 로드하지 않도록 opt-in입니다.

```text
nim c -d:nimormPostgres --path:src app.nim
```

```nim
let db = openPostgres(
  host = "localhost",
  port = 5432,
  database = "app",
  user = "app",
  password = getEnv("APP_DATABASE_PASSWORD"))
defer: db.close()
```

PostgreSQL integration fixture는 disposable database를 재구성합니다. 운영 또는
공유 database를 대상으로 실행하지 마세요. 필요한 환경 변수는
`NIMORM_PG_HOST`, `NIMORM_PG_PORT`, `NIMORM_PG_DATABASE`, `NIMORM_PG_USER`,
`NIMORM_PG_PASSWORD`입니다.

## 검증과 benchmark

```text
nimble test
nimble example
nimble benchmark
git diff --check
```

- `nimble test`: public entry point check, DSL compile failure, schema, SQLite,
  CRUD, query, relation, PostgreSQL compile contract, migration, CLI, validation
- `nimble example`: `examples/basic_model.nim`, `examples/blog.nim` 실행
- `nimble benchmark`: release mode SQLite in-memory microbenchmark

Benchmark는 object 생성, single/transactional insert, primary-key lookup, query
compile, ORM row mapping, raw row fetch를 측정합니다. 같은 machine, Nim 버전,
compiler mode, dependency에서만 결과를 비교하세요. 데이터베이스 서버의 처리량이나
production 성능을 보증하는 수치가 아닙니다.

## 저장소 구조

```text
src/nimorm.nim          공개 package entry point
src/nimorm/             model·query·backend·schema·migration 구현
src/nimorm/cli/main.nim migration CLI
examples/               실행 가능한 사용 예제
tests/                  unit·compile-failure·backend·CLI contract
benchmarks/             SQLite microbenchmark와 측정 지침
docs/                   모델·query·relation·migration·설계 문서
```

## 문서

- [시작하기](docs/getting-started.md)
- [모델과 metadata](docs/models.md)
- [필드와 validation](docs/fields.md)
- [Typed query와 CRUD](docs/queries.md)
- [Relation](docs/relations.md)
- [Migration](docs/migrations.md)
- [SQLite와 PostgreSQL](docs/backends.md)
- [아키텍처와 설계](docs/design.md)
- [Benchmark 방법](benchmarks/README.md)

## 의도적인 제약

- API는 동기식입니다. Async backend는 별도 connection ownership과 result lifetime
  계약으로 제공해야 하며, blocking 호출을 async 문법으로 감싸지 않습니다.
- Projection, `count` 이외의 arbitrary aggregation, eager loading, relation
  traversal filter, 자동 model discovery는 `0.1.0`에서 제공하지 않습니다.
- 모델 값에 lazy relation proxy를 저장하지 않으며 relation fetch는 항상 명시적입니다.
- Persistence는 validation을 자동 호출하지 않습니다.
- Destructive migration과 SQLite table rebuild를 자동 추측하지 않습니다.
- PostgreSQL CLI `migrate` 연결은 제공하지 않습니다. `sqlmigrate ... postgres`로
  SQL을 생성하거나 PostgreSQL backend로 `applyMigration`을 호출해야 합니다.

## 라이선스

`nimorm.nimble` package metadata는 MIT로 설정되어 있습니다. 독립적인
`LICENSE` 파일은 아직 저장소에 포함되어 있지 않으므로 배포 전에 라이선스 문서를
확정해야 합니다.
