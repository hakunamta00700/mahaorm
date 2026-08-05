import nimorm

model Target:
  name = stringField(maxLength = 10)

model BadRelation:
  target = foreignKey(Target, onDelete = SetNull, nullable = false)
