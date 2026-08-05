import nimorm

model Account:
  email = stringField(maxLength = 254, unique = true)

  meta:
    tableName = "accounts"
