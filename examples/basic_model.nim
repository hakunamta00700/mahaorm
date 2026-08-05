import nimorm

model Post:
  title = stringField(
    maxLength = 200,
    verboseName = "Title"
  )

  body = textField(
    verboseName = "Body"
  )

  meta:
    tableName = "posts"
    verboseName = "Post"

var post = Post(
  title: "Nim ORM",
  body: "Nim macro based ORM"
)

echo post.title
echo tableName(Post)
echo getModelMeta(Post)
