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
- manager와 QuerySet은 상태를 공유하지 않으며 실행 범위를 명시합니다.
- relation 조회와 validation, migration 위험 승인은 명시적으로 실행합니다.
- SQLite와 PostgreSQL의 dialect 차이는 backend·compiler 경계에 둡니다.
- blocking database 호출을 async 문법 뒤에 숨기지 않습니다.

## 현재 제공 범위

| 영역 | 제공 기능 |
| --- | --- |
| 모델 | `model` DSL, native object, immutable metadata, compile-time diagnostics, 자동 `int64` primary key |
| 필드 | 문자열·텍스트·정수·실수·Decimal·Bool·Date·DateTime·UUID·JSON·Binary, nullable `Option[T]` |
| Validation | 길이·pattern·범위·custom validator, 구조화된 validation issue |
| CRUD | stateless `Manager[T]`, insert/create, get/getOrNone, update, delete, generated ID·timestamp |
| Typed query | filter/exclude, ordering/reverse, distinct/none, pagination, cardinality, bulk update/delete, parameterized SQL |
| Relation | foreign key, one-to-one, 명시적 forward/reverse lookup, compile-time `onDelete` 검증 |
| Transaction | SQLite transaction과 nested savepoint, backend별 structured database error |
| Schema·migration | SQLite/PostgreSQL DDL, versioned snapshot, schema diff, dependency·history·safety gate |
| Backend | 기본 SQLite, `-d:nimormPostgres`로 선택하는 PostgreSQL/libpq backend |
| 관측성 | opt-in query logging, 민감 field·parameter redaction |

## 요구 사항과 설치

- Nim `>= 2.0.0`
- Nimble과 Nim이 지원하는 C compiler
- 기본 SQLite·`db_connector`
- PostgreSQL 사용 시 compatible `libpq` runtime

현재 Nimble package directory에 release되지 않았으므로 GitHub에서 직접
설치합니다.

```shell
nimble install https://github.com/hakunamta00700/mahaorm.git
```

저장소 개발 환경은 다음 순서로 준비합니다.

```shell
git clone https://github.com/hakunamta00700/mahaorm.git
cd mahaorm
nimble install -d
nimble develop
nimble test
```

자세한 설치 경계와 consumer project 연결은
[설치 문서](docs/installation.md)를 참고하세요.

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

var saved = Post(title: "Nim ORM", views: 1)
if saved.validate().len == 0:
  saved = db.insert(saved)

let posts = Post.objects(db)
  .filter(it.title.contains("Nim") and it.views >= 0)
  .exclude(it.title.startsWith("Draft:"))
  .orderBy(it.id.desc)
  .limit(20)
  .all()

echo saved.id
echo posts[0].title
```

`createTables`는 테스트와 초기 prototype에 적합합니다. 보존해야 하는 데이터의
schema를 변경할 때는 versioned snapshot과 migration을 사용하세요.

## Typed query와 SQL 안전성

`Model.objects(db)`는 stateless `Manager[T]`를 반환합니다. 각 호출은 새로운
immutable `QuerySet[T]`를 만들므로 filter와 pagination 상태가 다른 query로
누출되지 않습니다. `filter`, `exclude`, `orderBy`, `update`의 `it`은 compile-time
typed field reference이며 알 수 없는 field나 잘못된 타입 비교는 컴파일에 실패합니다.

Terminal API는 `all`, `first`, `firstOrNone`, `last`, `lastOrNone`, `get`,
`getOrNone`, `count`, `exists`, `contains`, `update`, `delete`를 제공합니다.
`all()`은 `seq[T]`를 반환하는 명시적 실행 경계입니다. Sliced query의 update/delete는
쓰기 범위가 넓어지는 것을 막기 위해 `ValueError`로 거부됩니다.

`toSql()`은 SQL과 parameter sequence가 분리된 `CompiledQuery`를 반환합니다.
SQLite는 `?`, PostgreSQL은 `$1`, `$2` placeholder를 사용합니다. Field나 column
이름에 `password`, `token`, `secret`, `apiKey`가 포함되면 query log에서 값이
가려집니다.

## Relation과 migration

`foreignKey`와 `oneToOneField`는 target model과 `onDelete` 정책을 요구하며,
모델에는 proxy 대신 target ID만 저장됩니다. `fetchRelated`, `related`,
`relatedOneOrNone`을 통해 relation query가 명시적으로 드러납니다.

모델 변경은 versioned JSON snapshot으로 고정합니다.

```nim
schemaSnapshot(User, Post).saveSnapshot("schema/current.json")
```

```text
nimorm makemigrations <previous.json|-> <current.json> <name> <output.json> [dependency]
nimorm sqlmigrate <migration.json> <sqlite|postgres>
nimorm migrate <sqlite.db> <migration.json> [--allow-destructive] [--allow-review]
nimorm migrations <sqlite.db>
```

Migration은 dependency·history·idempotency를 검사하며 destructive/review operation은
명시적인 flag 없이는 거부합니다. SQLite table rebuild가 필요한 변경은 자동 data
copy나 cast를 추측하지 않고 중단합니다.

## 검증과 benchmark

```shell
nimble test
nimble example
nimble benchmark
nimble docs
git diff --check
```

- `nimble test`: DSL compile failure, schema, SQLite, CRUD, QuerySet, relation,
  PostgreSQL compile contract, migration, CLI, validation
- `nimble example`: basic model, quickstart, blog 예제 실행
- `nimble benchmark`: release mode SQLite in-memory microbenchmark
- `nimble docs`: 로컬 Markdown 링크 검사

Benchmark는 database server capacity나 production 처리량 보증이 아니라 같은
machine·Nim·compiler mode·dependency에서의 회귀 비교 자료입니다.

## 문서

- [문서 안내](docs/index.md) · [시작 경로](docs/getting-started.md)
- [설치](docs/installation.md) · [5분 빠른 시작](docs/quickstart.md) · [Blog tutorial](docs/tutorial.md)
- [모델](docs/models.md) · [필드와 validation](docs/fields.md) · [Typed query](docs/queries.md) · [Relation](docs/relations.md)
- [Migration](docs/migrations.md) · [Backend](docs/backends.md) · [CLI reference](docs/cli-reference.md)
- [Cookbook](docs/cookbook.md) · [API reference](docs/api-reference.md)
- [문제 해결](docs/troubleshooting.md) · [FAQ](docs/faq.md) · [아키텍처](docs/design.md)
- [Benchmark 방법](benchmarks/README.md)

## 프로젝트

- [변경 이력](CHANGELOG.md) · [로드맵](ROADMAP.md)
- [기여 가이드](CONTRIBUTING.md) · [보안 정책](SECURITY.md)
- [행동 강령](CODE_OF_CONDUCT.md) · [MIT License](LICENSE)

## 의도적인 제약

API는 동기식입니다. Async backend는 별도 connection ownership과 result lifetime
계약으로 제공해야 하며 blocking 호출을 async 문법으로 감싸지 않습니다. Projection,
`count` 이외의 arbitrary aggregation, eager loading, relation traversal filter,
자동 model discovery는 `0.1.0`에서 제공하지 않습니다. SQLite table rebuild가
필요한 변경은 손실 가능성이 있는 implicit rewrite 대신 명시적 오류로 보고합니다.

Native object literal은 생략된 scalar와 명시적으로 전달한 Nim zero value를 구분하지
못합니다. 예를 들어 `booleanField(default = true)`에 plain object literal로
`false`를 넣으면 현재는 default가 적용됩니다. Presence-aware constructor API가
도입되기 전에는 zero-valued application default 또는 명시적인 raw/after-insert
update를 사용하세요.

PostgreSQL은 `-d:nimormPostgres`로만 컴파일되며 libpq runtime이 필요합니다.
CLI `migrate`는 SQLite 연결만 열고, PostgreSQL은 `sqlmigrate`로 SQL을 검토하거나
application code에서 `applyMigration`을 호출해야 합니다.

## 라이선스

이 프로젝트는 [MIT License](LICENSE)로 배포되며 `nimorm.nimble`의
`license = "MIT"` 선언과 같은 package 계약을 사용합니다.
