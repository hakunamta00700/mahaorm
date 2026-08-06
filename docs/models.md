# Models and metadata

The `model` macro owns the declaration grammar and emits an exported object,
metadata constant, serializers, validators, typed field references, and typed
relation references.

```nim
model Product:
  sku = stringField(maxLength = 40, unique = true)
  name = stringField(maxLength = 200)
  price = decimalField(precision = 12, scale = 2)

  meta:
    tableName = "catalog_products"
    verboseName = "Product"
    ordering = @["name"]
    indexes = @[
      @["name", "price"]
    ]
```

The generated value is an ordinary Nim object:

```nim
var product = Product(
  sku: "NIM-1",
  name: "Nim handbook",
  price: decimal("19.90"))
product.name = "Nim handbook, second edition"
```

There is no runtime `Field` container around `product.name` or
`product.price`. The macro rejects unknown field options, duplicate names or
columns, invalid constraints, and unknown fields in model metadata at compile
time.

## Model options

`meta` accepts `tableName`, `verboseName`, `verboseNamePlural`, `ordering`,
`uniqueTogether`, `indexes`, `managed`, `abstract`, and `autoPrimaryKey`.
Composite groups refer to DSL field names, not physical column names.

`ordering` is applied whenever `Model.objects(db)` creates a QuerySet. A leading
`-` selects descending order, as in `@["-createdAt", "title"]`. Explicit
`orderBy` calls replace the model default; subsequent calls append additional
query-specific ordering. `managed = false` excludes a
model from generated schema snapshots. `abstract = true` also excludes it from
snapshots. Automatic model inheritance is not part of the current macro.

## Primary keys

By default the macro adds the equivalent of:

```nim
id = bigIntegerField(primaryKey = true, autoIncrement = true)
```

Set `meta.autoPrimaryKey = false` when declaring an explicit primary key. CRUD
APIs require a primary key. The built-in PostgreSQL and SQLite auto-ID paths are
designed for integer primary keys.

## Metadata API

```nim
let modelMeta = getModelMeta(Product)
let priceMeta = getFieldMeta(Product, "price")
echo tableName(Product)
echo primaryKeyField(Product).get.columnName
```

`ProductModelMeta` is an exported immutable constant and can be inspected in a
`static` block. Metadata is backend independent; schema generation maps it to a
dialect only when `schemaSql`, `createTables`, or a migration is invoked.
