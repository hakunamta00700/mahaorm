import nimorm

model CustomTarget:
  key = stringField(maxLength = 40, primaryKey = true)

  meta:
    autoPrimaryKey = false

model BadRelation:
  target = foreignKey(CustomTarget, onDelete = Cascade)
