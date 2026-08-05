import nimorm

model BadPost:
  title = stringField(maxLength = 0)
