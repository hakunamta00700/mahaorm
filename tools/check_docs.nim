import std/[os, strutils]

proc linkTarget(line: string; start: var int): string =
  let marker = line.find("](", start)
  if marker < 0:
    start = line.len
    return ""
  let closing = line.find(')', marker + 2)
  if closing < 0:
    start = line.len
    return ""
  result = line[marker + 2 ..< closing].strip(chars = {'<', '>'})
  start = closing + 1

proc isExternal(target: string): bool =
  target.startsWith("http://") or
    target.startsWith("https://") or
    target.startsWith("mailto:") or
    target.startsWith("#")

proc checkedPath(markdownPath, target: string): string =
  let anchor = target.find('#')
  let pathPart =
    if anchor >= 0: target[0 ..< anchor]
    else: target
  if pathPart.len == 0:
    return ""
  normalizedPath(markdownPath.parentDir / pathPart)

proc main() =
  var markdownCount = 0
  var problems: seq[string]
  for markdownPath in walkDirRec("."):
    if not markdownPath.endsWith(".md") or
        markdownPath.startsWith(".git" & $DirSep):
      continue
    inc markdownCount
    var insideFence = false
    var lineNumber = 0
    for line in markdownPath.lines:
      inc lineNumber
      if line.strip.startsWith("```"):
        insideFence = not insideFence
        continue
      if insideFence:
        continue
      var start = 0
      while start < line.len:
        let target = line.linkTarget(start)
        if target.len == 0:
          break
        if target.isExternal:
          continue
        let path = checkedPath(markdownPath, target)
        if path.len > 0 and not fileExists(path) and not dirExists(path):
          problems.add(markdownPath & ":" & $lineNumber &
            ": missing local link target " & target)

  if problems.len > 0:
    for problem in problems:
      stderr.writeLine(problem)
    quit(1)
  echo "checked ", markdownCount, " Markdown files: local links resolve"

when isMainModule:
  main()
