import nimorm

model BadPost:
  title = stringField(maxLength = 100)

  meta:
    ordering = @["missing"]
