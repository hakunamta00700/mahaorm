import std/[algorithm, strutils, tables]

import ../field_defs
import ../migration/operations
import ./snapshot

proc fieldMap(fields: seq[FieldSnapshot]): Table[string, FieldSnapshot] =
  for field in fields:
    result[field.name] = field

proc modelMap(models: seq[ModelSnapshot]): Table[string, ModelSnapshot] =
  for model in models:
    result[model.modelName] = model

proc groupKey(group: seq[string]): string =
  var copy = group
  copy.sort()
  copy.join("\x1f")

proc groupMap(groups: seq[seq[string]]): Table[string, seq[string]] =
  for group in groups:
    result[groupKey(group)] = group

proc fieldChanged(previous, current: FieldSnapshot): bool =
  previous.kind != current.kind or
    previous.nullable != current.nullable or
    previous.primaryKey != current.primaryKey or
    previous.unique != current.unique or
    previous.maxLength != current.maxLength or
    previous.precision != current.precision or
    previous.scale != current.scale or
    previous.hasDefault != current.hasDefault or
    previous.defaultValue != current.defaultValue or
    previous.dbDefault != current.dbDefault or
    previous.autoIncrement != current.autoIncrement

proc diffGroups(result: var seq[MigrationOperation];
                previous, current: seq[seq[string]];
                model: ModelSnapshot;
                addKind, dropKind: MigrationOperationKind) =
  let oldGroups = groupMap(previous)
  let newGroups = groupMap(current)
  for key, fields in oldGroups:
    if not newGroups.hasKey(key):
      result.add(MigrationOperation(
        kind: dropKind,
        modelName: model.modelName,
        tableName: model.tableName,
        fields: fields))
  for key, fields in newGroups:
    if not oldGroups.hasKey(key):
      result.add(MigrationOperation(
        kind: addKind,
        modelName: model.modelName,
        tableName: model.tableName,
        fields: fields))

proc diffSchemas*(previous, current: SchemaSnapshot;
                  migrationName: string;
                  dependency = ""): Migration =
  result = Migration(name: migrationName, dependency: dependency)
  let oldModels = modelMap(previous.models)
  let newModels = modelMap(current.models)

  for modelName, oldModel in oldModels:
    if not newModels.hasKey(modelName):
      result.operations.add(MigrationOperation(
        kind: DropTable,
        modelName: modelName,
        tableName: oldModel.tableName,
        model: oldModel,
        destructive: true,
        reason: "model was removed"))

  for modelName, newModel in newModels:
    if not oldModels.hasKey(modelName):
      result.operations.add(MigrationOperation(
        kind: CreateTable,
        modelName: modelName,
        tableName: newModel.tableName,
        model: newModel))
      continue

    let oldModel = oldModels[modelName]
    if oldModel.tableName != newModel.tableName:
      result.operations.add(MigrationOperation(
        kind: RenameTable,
        modelName: modelName,
        tableName: newModel.tableName,
        previousTableName: oldModel.tableName))

    let oldFields = fieldMap(oldModel.fields)
    let newFields = fieldMap(newModel.fields)
    for fieldName, oldField in oldFields:
      if not newFields.hasKey(fieldName):
        result.operations.add(MigrationOperation(
          kind: DropColumn,
          modelName: modelName,
          tableName: newModel.tableName,
          fieldName: fieldName,
          field: oldField,
          destructive: true,
          reason: "field was removed"))

    for fieldName, newField in newFields:
      if not oldFields.hasKey(fieldName):
        result.operations.add(MigrationOperation(
          kind: AddColumn,
          modelName: modelName,
          tableName: newModel.tableName,
          fieldName: fieldName,
          field: newField,
          requiresReview: not newField.nullable and not newField.hasDefault and
            newField.dbDefault.len == 0 and not newField.autoIncrement,
          reason:
            if not newField.nullable and not newField.hasDefault and
                newField.dbDefault.len == 0 and not newField.autoIncrement:
              "adding a required column without a default needs a data plan"
            else: ""))
        continue

      let oldField = oldFields[fieldName]
      if oldField.columnName != newField.columnName:
        result.operations.add(MigrationOperation(
          kind: RenameColumn,
          modelName: modelName,
          tableName: newModel.tableName,
          fieldName: fieldName,
          previousColumnName: oldField.columnName,
          field: newField))
      if fieldChanged(oldField, newField):
        let narrowing = newField.maxLength > 0 and oldField.maxLength > 0 and
          newField.maxLength < oldField.maxLength
        let requiredChange = oldField.nullable and not newField.nullable
        result.operations.add(MigrationOperation(
          kind: AlterColumn,
          modelName: modelName,
          tableName: newModel.tableName,
          fieldName: fieldName,
          field: newField,
          destructive: narrowing,
          requiresReview: oldField.kind != newField.kind or narrowing or
            requiredChange,
          reason:
            if oldField.kind != newField.kind: "field type changed"
            elif narrowing: "field length was reduced"
            elif requiredChange: "nullable field became required"
            else: "field constraints changed"))
      let oldRelation = oldField.kind in {fkForeignKey, fkOneToOne}
      let newRelation = newField.kind in {fkForeignKey, fkOneToOne}
      if oldRelation and (not newRelation or
          oldField.relationTable != newField.relationTable or
          oldField.onDelete != newField.onDelete):
        result.operations.add(MigrationOperation(
          kind: DropForeignKey,
          modelName: modelName,
          tableName: newModel.tableName,
          fieldName: fieldName,
          field: oldField))
      if newRelation and (not oldRelation or
          oldField.relationTable != newField.relationTable or
          oldField.onDelete != newField.onDelete):
        result.operations.add(MigrationOperation(
          kind: AddForeignKey,
          modelName: modelName,
          tableName: newModel.tableName,
          fieldName: fieldName,
          field: newField))

    diffGroups(result.operations, oldModel.indexes, newModel.indexes,
      newModel, CreateIndex, DropIndex)
    diffGroups(result.operations, oldModel.uniqueTogether,
      newModel.uniqueTogether, newModel,
      AddUniqueConstraint, DropUniqueConstraint)
