import std/macros

## # Pattern Matching Library
##
## This library provides a `match` macro for pattern matching in Nim.

proc validateAndExtractArms(patterns: NimNode): seq[(NimNode, NimNode)] =
  ## Parses, validates, and expands the arms of a match expression.
  if patterns.kind != nnkStmtList:
    error("Match arms must be provided as a statement list.", patterns)

  var expandedArms: seq[(NimNode, NimNode)] = @[]

  proc flatten(p: NimNode): seq[NimNode] =
    if p.kind == nnkInfix and p.len == 3 and p[0].kind == nnkIdent and p[0].strVal == "|":
      return flatten(p[1]) & flatten(p[2])
    else:
      return @[p]

  for i in 0..<patterns.len:
    let arm = patterns[i]

    if arm.kind in {nnkEmpty, nnkCommentStmt}: continue

    if arm.kind != nnkInfix or arm.len != 3 or arm[0].kind != nnkIdent or arm[0].strVal != "=>":
      error("Expected 'pattern => body', but got: " & arm.repr, arm)

    let pattern = arm[1]
    let body = arm[2]

    if pattern.kind == nnkEmpty: error("Pattern cannot be empty.", arm)
    if body.kind == nnkEmpty: error("Body cannot be empty.", arm)

    let subPatterns = flatten(pattern)
    let isOrPattern = subPatterns.len > 1

    for p in subPatterns:
      if isOrPattern and p.kind == nnkIdent:
        if p.strVal == "_" or not compiles(p.repr):
          error("Variable bindings and wildcards are not permitted inside OR-patterns.", p)

      expandedArms.add((p, body))

  if expandedArms.len == 0:
    error("Match expression must have at least one arm.", patterns)

  return expandedArms

proc buildConditionalChain(arms: seq[(NimNode, NimNode)], tmpVar: NimNode): NimNode =
  ## Constructs the if/elif/else chain from the match arms.
  result = newTree(nnkIfStmt)
  var hasElse = false

  for (pattern, body) in arms:
    var condition: NimNode
    var branchBody = body

    case pattern.kind
    of nnkIntLit..nnkUInt64Lit, nnkFloatLit..nnkFloat64Lit,
       nnkStrLit..nnkTripleStrLit, nnkCharLit, nnkDotExpr:
      condition = quote do: `tmpVar` == `pattern`

    of nnkIdent:
      let s = pattern.strVal
      if s == "_":
        if hasElse: error("Cannot have multiple wildcard/else branches.", pattern)
        result.add(newTree(nnkElse, body))
        hasElse = true
        continue
      elif s in ["true", "false"]:
        condition = quote do: `tmpVar` == `pattern`
      else:
        condition = quote do:
          when compiles(`pattern`):
            `tmpVar` == `pattern`
          else:
            true

        branchBody = quote do:
          when not compiles(`pattern`):
            let `pattern` {.inject.} = `tmpVar`
          `body`

    else:
      error("Unsupported pattern type: " & pattern.repr, pattern)

    result.add(newTree(nnkElifBranch, condition, branchBody))

  if not hasElse:
    let msg = newLit("Non-exhaustive pattern match. No branch was taken.")
    let exception = newCall(bindSym"newException", ident("Defect"), msg)
    let raiseStmt = newTree(nnkRaiseStmt, exception)
    result.add(newTree(nnkElse, raiseStmt))

  return result

macro `match`*(scrutinee: typed, patterns: untyped): untyped =
  ## The main match macro.
  ##
  ## Usage:
  ##   match value:
  ##     pattern1 => body1
  ##     pattern2 => body2
  ##     _ => defaultBody

  let arms = validateAndExtractArms(patterns)
  let tmpVar = genSym(nskLet, "tmp")
  let conditionalChain = buildConditionalChain(arms, tmpVar)

  result = quote do:
    block:
      let `tmpVar` = `scrutinee`
      `conditionalChain`
