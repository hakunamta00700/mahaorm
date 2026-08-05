import ../schema/snapshot

type
  MigrationOperationKind* = enum
    CreateTable,
    DropTable,
    RenameTable,
    AddColumn,
    DropColumn,
    AlterColumn,
    RenameColumn,
    CreateIndex,
    DropIndex,
    AddForeignKey,
    DropForeignKey,
    AddUniqueConstraint,
    DropUniqueConstraint

  MigrationOperation* = object
    kind*: MigrationOperationKind
    modelName*: string
    tableName*: string
    previousTableName*: string
    fieldName*: string
    previousColumnName*: string
    field*: FieldSnapshot
    fields*: seq[string]
    model*: ModelSnapshot
    destructive*: bool
    requiresReview*: bool
    reason*: string

  Migration* = object
    name*: string
    dependency*: string
    operations*: seq[MigrationOperation]
