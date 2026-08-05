import std/[options, unittest]

import nimorm
import model_fixture

model Post:
  title = stringField(
    maxLength = 200,
    minLength = 1,
    trim = true,
    verboseName = "Title",
    dbIndex = true
  )

  body = textField(
    verboseName = "Body"
  )

  subtitle = stringField(
    maxLength = 100,
    nullable = true,
    columnName = "subtitle_text"
  )

  meta:
    tableName = "posts"
    verboseName = "Post"
    verboseNamePlural = "Posts"
    ordering = @["-id"]
    uniqueTogether = @[
      @["title", "body"]
    ]
    indexes = @[
      @["title"],
      @["title", "id"]
    ]

static:
  doAssert getModelMeta(Post).modelName == "Post"
  doAssert getModelMeta(Post).fields.len == 4
  doAssert tableName(Post) == "posts"
  doAssert typeof(default(Post).title) is string
  doAssert typeof(default(Post).subtitle) is Option[string]

suite "model DSL":
  test "generates a native Nim object":
    var post = Post(
      title: "Nim ORM",
      body: "Native fields",
      subtitle: none(string)
    )
    check post.id == 0'i64
    check post.title == "Nim ORM"
    post.title = "Updated"
    check post.title == "Updated"

  test "generates field and table metadata":
    let meta = getModelMeta(Post)
    check meta.tableName == "posts"
    check meta.verboseName == "Post"
    check meta.ordering == @["-id"]
    check meta.uniqueTogether == @[@["title", "body"]]
    check meta.indexes == @[@["title"], @["title", "id"]]

    let title = getFieldMeta(Post, "title")
    check title.kind == fkString
    check title.maxLength == 200
    check title.minLength == 1
    check title.trim
    check title.indexed

    let subtitle = getFieldMeta(Post, "subtitle")
    check subtitle.nullable
    check subtitle.columnName == "subtitle_text"

  test "adds a native int64 primary key by default":
    let primaryKey = primaryKeyField(Post)
    check primaryKey.isSome
    check primaryKey.get.name == "id"
    check primaryKey.get.kind == fkBigInteger

  test "reports runtime metadata lookup mistakes precisely":
    expect ValueError:
      discard getFieldMeta(Post, "missing")

  test "exports generated declarations across module boundaries":
    let account = Account(email: "nim@example.com")
    check account.email == "nim@example.com"
    check tableName(Account) == "accounts"
    check getFieldMeta(Account, "email").unique
