import std/options

import ./backends/base
import ./crud
import ./errors
import ./query/[ast, builder]

type
  RelationGetter*[Source] = proc(source: Source): DbValue {.nimcall.}

  RelationRef*[Source, Target] = object
    name*: string
    columnName*: string
    nullable*: bool
    oneToOne*: bool
    getter*: RelationGetter[Source]

proc relationRef*[Source, Target](
    name, columnName: string;
    nullable, oneToOne: bool;
    getter: RelationGetter[Source]): RelationRef[Source, Target] =
  RelationRef[Source, Target](
    name: name,
    columnName: columnName,
    nullable: nullable,
    oneToOne: oneToOne,
    getter: getter)

proc fetchRelated*[Source, Target](
    db: Database;
    source: Source;
    relation: RelationRef[Source, Target]): Target =
  let value = relation.getter(source)
  if value.kind == dvNull:
    raise newException(RecordNotFound,
      relation.name & ": nullable relation has no target")
  db.get(Target, value)

proc fetchRelatedOrNone*[Source, Target](
    db: Database;
    source: Source;
    relation: RelationRef[Source, Target]): Option[Target] =
  let value = relation.getter(source)
  if value.kind == dvNull:
    return none(Target)
  db.getOrNone(Target, value)

proc related*[Source, Target](
    db: Database;
    target: Target;
    relation: RelationRef[Source, Target]): QuerySet[Source] =
  mixin nimOrmPrimaryKey
  result = Source.objects(db)
  result.predicate = SqlExpression(
    kind: ekCompare,
    columnName: relation.columnName,
    compareOperator: coEqual,
    values: @[nimOrmPrimaryKey(target)])

proc relatedOneOrNone*[Source, Target](
    db: Database;
    target: Target;
    relation: RelationRef[Source, Target]): Option[Source] =
  if not relation.oneToOne:
    raise newException(ValueError,
      relation.name & ": relation is not one-to-one")
  db.related(target, relation).firstOrNone()
