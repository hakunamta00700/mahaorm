import std/[strutils, unittest]

import nimorm

model InventoryItem:
  name = stringField(maxLength = 120, unique = true)
  description = textField(nullable = true)
  quantity = integerField(default = 0, dbIndex = true)
  externalId = uuidField(nullable = true)
  price = decimalField(precision = 12, scale = 2)
  score = floatField(default = 0.5)
  active = booleanField(default = true)
  releasedOn = dateField(nullable = true)
  createdAt = dateTimeField(dbDefault = "CURRENT_TIMESTAMP")
  payload = jsonField(nullable = true)
  checksum = binaryField(nullable = true)

  meta:
    tableName = "order"
    uniqueTogether = @[
      @["name", "quantity"]
    ]
    indexes = @[
      @["createdAt", "active"]
    ]

suite "schema generation":
  test "maps native Nim field types":
    doAssert typeof(default(InventoryItem).name) is string
    doAssert typeof(default(InventoryItem).quantity) is int
    doAssert typeof(default(InventoryItem).price) is Decimal
    doAssert typeof(default(InventoryItem).active) is bool
    doAssert typeof(default(InventoryItem).releasedOn) is Option[Date]
    doAssert typeof(default(InventoryItem).createdAt) is DateTime
    doAssert typeof(default(InventoryItem).payload) is Option[JsonNode]
    doAssert typeof(default(InventoryItem).checksum) is Option[seq[byte]]

  test "generates quoted SQLite DDL with constraints and indexes":
    let generated = schemaSql(InventoryItem, sqliteBackend)
    check generated.startsWith("CREATE TABLE \"order\"")
    check "\"id\" INTEGER PRIMARY KEY AUTOINCREMENT" in generated
    check "\"name\" VARCHAR(120) NOT NULL UNIQUE" in generated
    check "\"price\" NUMERIC(12, 2) NOT NULL" in generated
    check "\"active\" INTEGER NOT NULL DEFAULT 1" in generated
    check "\"createdAt\" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP" in generated
    check "UNIQUE (\"name\", \"quantity\")" in generated
    check "CREATE INDEX \"idx_order_quantity\"" in generated
    check "CREATE INDEX \"idx_order_createdAt_active\"" in generated

  test "generates PostgreSQL-compatible types from the same metadata":
    let generated = schemaSql(InventoryItem, postgresBackend)
    check "\"id\" BIGINT PRIMARY KEY NOT NULL" in generated
    check "\"externalId\" UUID" in generated
    check "\"createdAt\" TIMESTAMPTZ" in generated
    check "\"payload\" JSONB" in generated
    check "\"checksum\" BYTEA" in generated

  test "keeps exact decimal, UUID, and date values":
    check $decimal("1234567890.25") == "1234567890.25"
    check $uuid("550E8400-E29B-41D4-A716-446655440000") ==
      "550e8400-e29b-41d4-a716-446655440000"
    check $date(2026, 8, 6) == "2026-08-06"
