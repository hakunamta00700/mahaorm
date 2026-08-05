import nimorm

model BadPost:
  title = stringField(maxLength = 100, unknownOption = true)
