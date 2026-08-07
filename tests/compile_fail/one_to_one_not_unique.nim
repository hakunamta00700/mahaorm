import nimorm

model Target:
  name = stringField(maxLength = 10)

model BadRelation:
  target = oneToOneField(Target, onDelete = Cascade, unique = false)
