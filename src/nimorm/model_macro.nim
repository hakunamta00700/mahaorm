import std/[json, macros, options, strutils, tables, times]

import ./field_defs
import ./metadata
import ./types

type
  ParsedField = object
    name: string
    columnName: string
    kind: FieldKind
    nullable: bool
    primaryKey: bool
    unique: bool
    indexed: bool
    maxLength: int
    minLength: int
    trim: bool
    verboseName: string
    helpText: string
    editable: bool
    precision: int
    scale: int
    autoIncrement: bool
    autoNow: bool
    autoNowAdd: bool
    hasDefault: bool
    defaultValue: string
    dbDefault: string
    defaultFactory: string
    sourceNode: NimNode

  ParsedModelMeta = object
    tableName: string
    verboseName: string
    verboseNamePlural: string
    ordering: seq[string]
    uniqueTogether: seq[seq[string]]
    indexes: seq[seq[string]]
    managed: bool
    abstract: bool
    autoPrimaryKey: bool

proc normalizedIdent(name: string): string {.compileTime.} =
  for character in name:
    if character != '_':
      result.add(character.toLowerAscii)

proc nodeName(node: NimNode): string {.compileTime.} =
  if node.kind in {nnkIdent, nnkSym}:
    node.strVal
  else:
    ""

proc expectString(node: NimNode; context: string): string {.compileTime.} =
  if node.kind notin {nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
    error(context & " must be a string literal", node)
  node.strVal

proc expectBool(node: NimNode; context: string): bool {.compileTime.} =
  if node.kind notin {nnkIdent, nnkSym} or node.strVal notin ["true", "false"]:
    error(context & " must be true or false", node)
  node.strVal == "true"

proc expectInt(node: NimNode; context: string): int {.compileTime.} =
  if node.kind < nnkIntLit or node.kind > nnkUInt64Lit:
    error(context & " must be an integer literal", node)
  int(node.intVal)

proc expectDefault(node: NimNode; context: string): string {.compileTime.} =
  case node.kind
  of nnkStrLit, nnkRStrLit, nnkTripleStrLit:
    node.strVal
  of nnkCharLit:
    $chr(node.intVal)
  of nnkIntLit..nnkUInt64Lit:
    $node.intVal
  of nnkFloatLit..nnkFloat64Lit:
    $node.floatVal
  of nnkIdent, nnkSym:
    if node.strVal in ["true", "false"]:
      node.strVal
    else:
      error(context & " must be a scalar literal", node)
  else:
    error(context & " must be a scalar literal", node)

proc expectProcName(node: NimNode; context: string): string {.compileTime.} =
  if node.kind notin {nnkIdent, nnkSym}:
    error(context & " must name a proc", node)
  node.strVal

proc expectStringSeq(node: NimNode; context: string): seq[string] {.compileTime.} =
  if node.kind != nnkPrefix or node.len != 2 or nodeName(node[0]) != "@" or
      node[1].kind != nnkBracket:
    error(context & " must be a sequence literal such as @[\"field\"]", node)
  for item in node[1]:
    result.add(expectString(item, context))

proc expectNestedStringSeq(node: NimNode; context: string): seq[seq[string]] {.compileTime.} =
  if node.kind != nnkPrefix or node.len != 2 or nodeName(node[0]) != "@" or
      node[1].kind != nnkBracket:
    error(context & " must be a nested sequence literal", node)
  for item in node[1]:
    result.add(expectStringSeq(item, context))

proc defaultTableName(modelName: string): string {.compileTime.} =
  if modelName.len == 0:
    return ""
  result = modelName
  result[0] = result[0].toLowerAscii

proc parseField(modelName, fieldName: string; rhs: NimNode): ParsedField {.compileTime.} =
  let context = modelName & "." & fieldName
  if rhs.kind notin {nnkCall, nnkCommand} or rhs.len == 0:
    error(context & ": expected a field declaration such as stringField(maxLength = 200)", rhs)

  let fieldType = nodeName(rhs[0])
  case fieldType
  of "stringField":
    result.kind = fkString
    result.maxLength = -1
  of "textField":
    result.kind = fkText
  of "integerField":
    result.kind = fkInteger
  of "bigIntegerField":
    result.kind = fkBigInteger
  of "floatField":
    result.kind = fkFloat
  of "decimalField":
    result.kind = fkDecimal
    result.precision = -1
    result.scale = -1
  of "booleanField":
    result.kind = fkBoolean
  of "dateField":
    result.kind = fkDate
  of "dateTimeField":
    result.kind = fkDateTime
  of "uuidField":
    result.kind = fkUuid
  of "jsonField":
    result.kind = fkJson
  of "binaryField":
    result.kind = fkBinary
  else:
    error(context & ": unsupported field type '" & fieldType &
      "'", rhs[0])

  result.name = fieldName
  result.columnName = fieldName
  result.editable = true
  result.sourceNode = rhs

  var seen = initTable[string, bool]()
  for index in 1 ..< rhs.len:
    let argument = rhs[index]
    if argument.kind != nnkExprEqExpr or argument.len != 2:
      error(context & ": field options must use name = value", argument)
    let optionName = nodeName(argument[0])
    if optionName.len == 0:
      error(context & ": invalid field option name", argument[0])
    let normalized = normalizedIdent(optionName)
    if seen.hasKey(normalized):
      error(context & ": duplicate option '" & optionName & "'", argument)
    seen[normalized] = true

    case optionName
    of "primaryKey": result.primaryKey = expectBool(argument[1], context & ".primaryKey")
    of "nullable": result.nullable = expectBool(argument[1], context & ".nullable")
    of "unique": result.unique = expectBool(argument[1], context & ".unique")
    of "dbIndex": result.indexed = expectBool(argument[1], context & ".dbIndex")
    of "columnName":
      result.columnName = expectString(argument[1], context & ".columnName")
      if result.columnName.len == 0:
        error(context & ".columnName must not be empty", argument[1])
    of "verboseName": result.verboseName = expectString(argument[1], context & ".verboseName")
    of "helpText": result.helpText = expectString(argument[1], context & ".helpText")
    of "editable": result.editable = expectBool(argument[1], context & ".editable")
    of "default":
      result.hasDefault = true
      result.defaultValue = expectDefault(argument[1], context & ".default")
    of "dbDefault":
      result.dbDefault = expectString(argument[1], context & ".dbDefault")
    of "defaultFactory":
      result.defaultFactory = expectProcName(argument[1], context & ".defaultFactory")
    of "autoIncrement":
      result.autoIncrement = expectBool(argument[1], context & ".autoIncrement")
    of "autoNow":
      result.autoNow = expectBool(argument[1], context & ".autoNow")
    of "autoNowAdd":
      result.autoNowAdd = expectBool(argument[1], context & ".autoNowAdd")
    of "maxLength":
      if result.kind != fkString:
        error(context & ": textField does not support option 'maxLength'", argument)
      result.maxLength = expectInt(argument[1], context & ".maxLength")
    of "minLength":
      if result.kind != fkString:
        error(context & ": textField does not support option 'minLength'", argument)
      result.minLength = expectInt(argument[1], context & ".minLength")
    of "trim":
      if result.kind != fkString:
        error(context & ": textField does not support option 'trim'", argument)
      result.trim = expectBool(argument[1], context & ".trim")
    of "precision":
      if result.kind != fkDecimal:
        error(context & ": " & fieldType & " does not support option 'precision'", argument)
      result.precision = expectInt(argument[1], context & ".precision")
    of "scale":
      if result.kind != fkDecimal:
        error(context & ": " & fieldType & " does not support option 'scale'", argument)
      result.scale = expectInt(argument[1], context & ".scale")
    else:
      error(context & ": unsupported option '" & optionName & "' for " & fieldType, argument[0])

  if result.kind == fkString:
    if result.maxLength < 1:
      error(context & ": stringField maxLength must be at least 1", rhs)
    if result.minLength < 0:
      error(context & ": stringField minLength must not be negative", rhs)
    if result.minLength > result.maxLength:
      error(context & ": stringField minLength must not exceed maxLength", rhs)
  if result.kind == fkDecimal:
    if result.precision < 1:
      error(context & ": decimalField precision must be at least 1", rhs)
    if result.scale < 0:
      error(context & ": decimalField scale must not be negative", rhs)
    if result.scale > result.precision:
      error(context & ": decimalField scale must not exceed precision", rhs)
  if result.primaryKey and result.nullable:
    error(context & ": a primary key cannot be nullable", rhs)
  if result.autoIncrement and result.kind notin {fkInteger, fkBigInteger}:
    error(context & ": autoIncrement is only valid for integer fields", rhs)
  if result.autoIncrement and not result.primaryKey:
    error(context & ": autoIncrement requires primaryKey = true", rhs)
  if (result.autoNow or result.autoNowAdd) and result.kind != fkDateTime:
    error(context & ": autoNow and autoNowAdd are only valid for dateTimeField", rhs)
  if result.autoNow and result.autoNowAdd:
    error(context & ": autoNow and autoNowAdd cannot both be true", rhs)
  if result.hasDefault and result.defaultFactory.len > 0:
    error(context & ": default and defaultFactory cannot be used together", rhs)
  if (result.autoNow or result.autoNowAdd) and
      (result.hasDefault or result.defaultFactory.len > 0):
    error(context & ": automatic timestamps cannot be combined with a default", rhs)

proc parseMeta(modelName: string; metaBlock: NimNode;
               meta: var ParsedModelMeta) {.compileTime.} =
  if metaBlock.kind != nnkStmtList:
    error(modelName & ".meta: expected an indented block", metaBlock)
  var seen = initTable[string, bool]()
  for statement in metaBlock:
    if statement.kind != nnkAsgn or statement.len != 2 or nodeName(statement[0]).len == 0:
      error(modelName & ".meta: expected option = value", statement)
    let optionName = nodeName(statement[0])
    let normalized = normalizedIdent(optionName)
    if seen.hasKey(normalized):
      error(modelName & ".meta: duplicate option '" & optionName & "'", statement)
    seen[normalized] = true
    case optionName
    of "tableName":
      meta.tableName = expectString(statement[1], modelName & ".meta.tableName")
      if meta.tableName.len == 0:
        error(modelName & ".meta.tableName must not be empty", statement[1])
    of "verboseName": meta.verboseName = expectString(statement[1], modelName & ".meta.verboseName")
    of "verboseNamePlural": meta.verboseNamePlural = expectString(statement[1], modelName & ".meta.verboseNamePlural")
    of "ordering": meta.ordering = expectStringSeq(statement[1], modelName & ".meta.ordering")
    of "uniqueTogether": meta.uniqueTogether = expectNestedStringSeq(statement[1], modelName & ".meta.uniqueTogether")
    of "indexes": meta.indexes = expectNestedStringSeq(statement[1], modelName & ".meta.indexes")
    of "managed": meta.managed = expectBool(statement[1], modelName & ".meta.managed")
    of "abstract": meta.abstract = expectBool(statement[1], modelName & ".meta.abstract")
    of "autoPrimaryKey": meta.autoPrimaryKey = expectBool(statement[1], modelName & ".meta.autoPrimaryKey")
    else:
      error(modelName & ".meta: unsupported option '" & optionName & "'", statement[0])

proc fieldExists(fields: seq[ParsedField]; name: string): bool {.compileTime.} =
  let wanted = normalizedIdent(name)
  for field in fields:
    if normalizedIdent(field.name) == wanted:
      return true

proc validateMeta(modelName: string; fields: seq[ParsedField]; meta: ParsedModelMeta;
                  metaNode: NimNode) {.compileTime.} =
  for orderEntry in meta.ordering:
    let fieldName =
      if orderEntry.len > 0 and orderEntry[0] == '-': orderEntry[1 .. ^1]
      else: orderEntry
    if fieldName.len == 0 or not fields.fieldExists(fieldName):
      error(modelName & ".meta.ordering: unknown field '" & fieldName & "'", metaNode)

  var uniqueKeys = initTable[string, bool]()
  for group in meta.uniqueTogether:
    if group.len < 2:
      error(modelName & ".meta.uniqueTogether: each group must contain at least two fields", metaNode)
    var local = initTable[string, bool]()
    var key = ""
    for fieldName in group:
      let normalized = normalizedIdent(fieldName)
      if not fields.fieldExists(fieldName):
        error(modelName & ".meta.uniqueTogether: unknown field '" & fieldName & "'", metaNode)
      if local.hasKey(normalized):
        error(modelName & ".meta.uniqueTogether: duplicate field '" & fieldName & "'", metaNode)
      local[normalized] = true
      key.add(normalized & "|")
    if uniqueKeys.hasKey(key):
      error(modelName & ".meta.uniqueTogether: duplicate constraint", metaNode)
    uniqueKeys[key] = true

  var indexKeys = initTable[string, bool]()
  for group in meta.indexes:
    if group.len == 0:
      error(modelName & ".meta.indexes: an index must contain at least one field", metaNode)
    var local = initTable[string, bool]()
    var key = ""
    for fieldName in group:
      let normalized = normalizedIdent(fieldName)
      if not fields.fieldExists(fieldName):
        error(modelName & ".meta.indexes: unknown field '" & fieldName & "'", metaNode)
      if local.hasKey(normalized):
        error(modelName & ".meta.indexes: duplicate field '" & fieldName & "'", metaNode)
      local[normalized] = true
      key.add(normalized & "|")
    if indexKeys.hasKey(key):
      error(modelName & ".meta.indexes: duplicate index", metaNode)
    indexKeys[key] = true

proc stringSeqNode(values: seq[string]): NimNode {.compileTime.} =
  var bracket = newNimNode(nnkBracket)
  for value in values:
    bracket.add(newLit(value))
  newTree(nnkPrefix, ident("@"), bracket)

proc nestedStringSeqNode(values: seq[seq[string]]): NimNode {.compileTime.} =
  var bracket = newNimNode(nnkBracket)
  for value in values:
    bracket.add(stringSeqNode(value))
  newTree(nnkPrefix, ident("@"), bracket)

proc fieldMetaNode(field: ParsedField): NimNode {.compileTime.} =
  newTree(nnkObjConstr,
    bindSym("FieldMeta"),
    newTree(nnkExprColonExpr, ident("name"), newLit(field.name)),
    newTree(nnkExprColonExpr, ident("columnName"), newLit(field.columnName)),
    newTree(nnkExprColonExpr, ident("kind"), ident($field.kind)),
    newTree(nnkExprColonExpr, ident("nullable"), newLit(field.nullable)),
    newTree(nnkExprColonExpr, ident("primaryKey"), newLit(field.primaryKey)),
    newTree(nnkExprColonExpr, ident("unique"), newLit(field.unique)),
    newTree(nnkExprColonExpr, ident("indexed"), newLit(field.indexed)),
    newTree(nnkExprColonExpr, ident("maxLength"), newLit(field.maxLength)),
    newTree(nnkExprColonExpr, ident("minLength"), newLit(field.minLength)),
    newTree(nnkExprColonExpr, ident("trim"), newLit(field.trim)),
    newTree(nnkExprColonExpr, ident("verboseName"), newLit(field.verboseName)),
    newTree(nnkExprColonExpr, ident("helpText"), newLit(field.helpText)),
    newTree(nnkExprColonExpr, ident("editable"), newLit(field.editable)),
    newTree(nnkExprColonExpr, ident("precision"), newLit(field.precision)),
    newTree(nnkExprColonExpr, ident("scale"), newLit(field.scale)),
    newTree(nnkExprColonExpr, ident("autoIncrement"), newLit(field.autoIncrement)),
    newTree(nnkExprColonExpr, ident("autoNow"), newLit(field.autoNow)),
    newTree(nnkExprColonExpr, ident("autoNowAdd"), newLit(field.autoNowAdd)),
    newTree(nnkExprColonExpr, ident("hasDefault"), newLit(field.hasDefault)),
    newTree(nnkExprColonExpr, ident("defaultValue"), newLit(field.defaultValue)),
    newTree(nnkExprColonExpr, ident("dbDefault"), newLit(field.dbDefault)),
    newTree(nnkExprColonExpr, ident("defaultFactory"), newLit(field.defaultFactory)))

proc fieldsNode(fields: seq[ParsedField]): NimNode {.compileTime.} =
  var bracket = newNimNode(nnkBracket)
  for field in fields:
    bracket.add(fieldMetaNode(field))
  newTree(nnkPrefix, ident("@"), bracket)

proc modelMetaNode(modelName: string; fields: seq[ParsedField]; meta: ParsedModelMeta): NimNode {.compileTime.} =
  newTree(nnkObjConstr,
    bindSym("ModelMeta"),
    newTree(nnkExprColonExpr, ident("modelName"), newLit(modelName)),
    newTree(nnkExprColonExpr, ident("tableName"), newLit(meta.tableName)),
    newTree(nnkExprColonExpr, ident("verboseName"), newLit(meta.verboseName)),
    newTree(nnkExprColonExpr, ident("verboseNamePlural"), newLit(meta.verboseNamePlural)),
    newTree(nnkExprColonExpr, ident("fields"), fieldsNode(fields)),
    newTree(nnkExprColonExpr, ident("ordering"), stringSeqNode(meta.ordering)),
    newTree(nnkExprColonExpr, ident("uniqueTogether"), nestedStringSeqNode(meta.uniqueTogether)),
    newTree(nnkExprColonExpr, ident("indexes"), nestedStringSeqNode(meta.indexes)),
    newTree(nnkExprColonExpr, ident("managed"), newLit(meta.managed)),
    newTree(nnkExprColonExpr, ident("abstract"), newLit(meta.abstract)),
    newTree(nnkExprColonExpr, ident("autoPrimaryKey"), newLit(meta.autoPrimaryKey)))

proc fieldTypeNode(field: ParsedField): NimNode {.compileTime.} =
  var nativeType: NimNode
  case field.kind
  of fkString, fkText:
    nativeType = bindSym("string")
  of fkInteger:
    nativeType = bindSym("int")
  of fkBigInteger:
    nativeType = bindSym("int64")
  of fkFloat:
    nativeType = bindSym("float64")
  of fkDecimal:
    nativeType = bindSym("Decimal")
  of fkBoolean:
    nativeType = bindSym("bool")
  of fkDate:
    nativeType = bindSym("Date")
  of fkDateTime:
    nativeType = bindSym("DateTime")
  of fkUuid:
    nativeType = bindSym("Uuid")
  of fkJson:
    nativeType = bindSym("JsonNode")
  of fkBinary:
    nativeType = newTree(nnkBracketExpr, bindSym("seq"), bindSym("byte"))
  else:
    error("internal error: no native type for " & $field.kind, field.sourceNode)
  if field.nullable:
    newTree(nnkBracketExpr, bindSym("Option"), nativeType)
  else:
    nativeType

macro model*(name: untyped; body: untyped): untyped =
  if name.kind != nnkIdent:
    error("model: expected a simple model type name", name)
  if body.kind != nnkStmtList:
    error($name & ": expected an indented model body", body)

  let modelName = name.strVal
  var fields: seq[ParsedField]
  var meta = ParsedModelMeta(
    tableName: defaultTableName(modelName),
    managed: true,
    autoPrimaryKey: true)
  var fieldNames = initTable[string, bool]()
  var metaSeen = false
  var metaNode = body

  for statement in body:
    if statement.kind == nnkAsgn and statement.len == 2 and nodeName(statement[0]).len > 0:
      let fieldName = nodeName(statement[0])
      let normalized = normalizedIdent(fieldName)
      if fieldNames.hasKey(normalized):
        error(modelName & "." & fieldName & ": duplicate field declaration", statement[0])
      fieldNames[normalized] = true
      fields.add(parseField(modelName, fieldName, statement[1]))
    elif statement.kind in {nnkCall, nnkCommand} and statement.len == 2 and
        nodeName(statement[0]) == "meta":
      if metaSeen:
        error(modelName & ".meta: duplicate meta block", statement)
      metaSeen = true
      metaNode = statement
      parseMeta(modelName, statement[1], meta)
    else:
      error(modelName & ": expected a field assignment or meta block", statement)

  var primaryKeyCount = 0
  for field in fields:
    if field.primaryKey:
      inc primaryKeyCount
  if primaryKeyCount > 1:
    error(modelName & ": multiple primary-key fields are not supported", body)

  if meta.autoPrimaryKey and primaryKeyCount == 0:
    if fields.fieldExists("id"):
      error(modelName & ".id: autoPrimaryKey cannot add id because that field already exists; " &
        "mark it primaryKey = true or set meta.autoPrimaryKey = false", body)
    fields.insert(ParsedField(
      name: "id",
      columnName: "id",
      kind: fkBigInteger,
      primaryKey: true,
      unique: true,
      autoIncrement: true,
      editable: false,
      sourceNode: body), 0)

  var columnNames = initTable[string, string]()
  for field in fields:
    let normalized = normalizedIdent(field.columnName)
    if columnNames.hasKey(normalized):
      error(modelName & "." & field.name & ": columnName '" & field.columnName &
        "' is already used by field '" & columnNames[normalized] & "'", field.sourceNode)
    columnNames[normalized] = field.name

  validateMeta(modelName, fields, meta, metaNode)

  var recordList = newNimNode(nnkRecList)
  for field in fields:
    recordList.add(newTree(nnkIdentDefs,
      postfix(ident(field.name), "*"),
      fieldTypeNode(field),
      newEmptyNode()))

  let modelType = newTree(nnkTypeSection,
    newTree(nnkTypeDef,
      postfix(ident(modelName), "*"),
      newEmptyNode(),
      newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), recordList)))
  let metadataName = ident(modelName & "ModelMeta")
  let metadataConst = newTree(nnkConstSection,
    newTree(nnkConstDef,
      postfix(metadataName, "*"),
      newEmptyNode(),
      modelMetaNode(modelName, fields, meta)))
  let modelTypeIdent = ident(modelName)
  let metadataIdent = ident(modelName & "ModelMeta")
  let accessor = quote do:
    template nimOrmModelMeta*(modelType: typedesc[`modelTypeIdent`]): untyped =
      `metadataIdent`

  result = newStmtList(modelType, metadataConst, accessor)
