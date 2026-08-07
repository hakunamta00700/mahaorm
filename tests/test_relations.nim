import std/[options, strutils, unittest]

import nimorm

model RelationUser:
  username = stringField(maxLength = 100, unique = true)

  meta:
    tableName = "relation_users"

model RelationProfile:
  bio = textField()
  user = oneToOneField(
    RelationUser,
    onDelete = Cascade,
    relatedName = "profile"
  )

  meta:
    tableName = "relation_profiles"

model RelationPost:
  title = stringField(maxLength = 200)
  author = foreignKey(
    RelationUser,
    onDelete = Cascade,
    relatedName = "posts"
  )
  reviewer = foreignKey(
    RelationUser,
    onDelete = SetNull,
    nullable = true,
    relatedName = "reviewedPosts"
  )

  meta:
    tableName = "relation_posts"

suite "model relations":
  test "generates native ID storage and foreign-key schema":
    doAssert typeof(default(RelationPost).authorId) is int64
    doAssert typeof(default(RelationPost).reviewerId) is Option[int64]
    let ddl = schemaSql(RelationPost, sqliteBackend)
    check "CONSTRAINT \"fk_relation_posts_author_id\"" in ddl
    check "\"author_id\" INTEGER NOT NULL" in ddl
    check "REFERENCES \"relation_users\" (\"id\") ON DELETE CASCADE" in ddl
    check "REFERENCES \"relation_users\" (\"id\") ON DELETE SET NULL" in ddl
    let profileDdl = schemaSql(RelationProfile, sqliteBackend)
    check "\"user_id\" INTEGER NOT NULL UNIQUE" in profileDdl

  test "fetches forward and reverse relations with static types":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(RelationUser, RelationProfile, RelationPost)
    let user = db.insert(RelationUser(username: "david"))
    let other = db.insert(RelationUser(username: "reviewer"))
    let profile = db.insert(RelationProfile(bio: "hello", userId: user.id))
    let first = db.insert(RelationPost(
      title: "one",
      authorId: user.id,
      reviewerId: some(other.id)))
    discard db.insert(RelationPost(title: "two", authorId: user.id))

    let author: RelationUser =
      db.fetchRelated(first, relations(RelationPost).author)
    check author.username == "david"
    let reviewer =
      db.fetchRelatedOrNone(first, relations(RelationPost).reviewer)
    check reviewer.get.username == "reviewer"
    check db.fetchRelatedOrNone(
      RelationPost(title: "none", authorId: user.id),
      relations(RelationPost).reviewer).isNone

    let posts = db.related(user, relations(RelationPost).author)
      .orderBy(it.id.asc)
      .all()
    check posts.len == 2
    check posts[0].title == "one"
    check db.relatedOneOrNone(
      user, relations(RelationProfile).user).get.bio == profile.bio

  test "enforces foreign keys and cascades deletes":
    let db = openSqlite(":memory:")
    defer: db.close()
    db.createTables(RelationUser, RelationPost)
    expect ForeignKeyViolation:
      discard db.insert(RelationPost(title: "invalid", authorId: 999))
    let user = db.insert(RelationUser(username: "owner"))
    discard db.insert(RelationPost(title: "owned", authorId: user.id))
    check db.delete(user) == 1
    check RelationPost.objects(db).count() == 0
