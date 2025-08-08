import std/macros

## # Pattern Matching Library
##
## This library provides a `match` macro for pattern matching in Nim.

template to*(patt, name: untyped): untyped =
  ## Helper template to create a binding pattern (AS-pattern).
  ## Transforms `pattern.to(name)` into an AST node that `match` can parse.
  nnkInfix.newTree(ident"@", patt, name)

proc validateAndExtractArms(patterns: NimNode): seq[(NimNode, NimNode, seq[NimNode])] =
  ## Parses, validates, and expands the arms of a match expression.
  ## Returns seq of (pattern, body, as-names).
  if patterns.kind != nnkStmtList:
    error("Match arms must be provided as a statement list.", patterns)

  var expandedArms: seq[(NimNode, NimNode, seq[NimNode])] = @[]

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

    var currentPattern = arm[1]
    let body = arm[2]
    var asNames: seq[NimNode] = @[]

    while currentPattern.kind == nnkInfix and currentPattern.len == 3 and currentPattern[0].strVal == "@":
      let boundName = currentPattern[2]
      if boundName.kind != nnkIdent:
        error("Binding pattern requires a variable name.", boundName)
      asNames.add(boundName)
      currentPattern = currentPattern[1]

    if currentPattern.kind == nnkEmpty: error("Pattern cannot be empty.", arm)
    if body.kind == nnkEmpty: error("Body cannot be empty.", arm)

    let subPatterns = flatten(currentPattern)
    let isOrPattern = subPatterns.len > 1

    for p in subPatterns:
      if isOrPattern and p.kind == nnkIdent:
        if p.strVal == "_" or not compiles(p.repr):
          error("Variable bindings and wildcards are not permitted inside OR-patterns.", p)

      expandedArms.add((p, body, asNames))

  if expandedArms.len == 0:
    error("Match expression must have at least one arm.", patterns)

  return expandedArms

proc buildConditionalChain(arms: seq[(NimNode, NimNode, seq[NimNode])], tmpVar: NimNode): NimNode =
  ## Constructs the if/elif/else chain from the match arms.
  result = newTree(nnkIfStmt)
  var hasElse = false

  for (pattern, body, asNames) in arms:
    var condition: NimNode

    var bindings = newStmtList()
    for name in asNames:
      bindings.add(quote do: let `name` {.inject.} = `tmpVar`)

    case pattern.kind
    of nnkIntLit..nnkUInt64Lit, nnkFloatLit..nnkFloat64Lit,
       nnkStrLit..nnkTripleStrLit, nnkCharLit, nnkDotExpr:

      let comp = quote do: `tmpVar` == `pattern`
      if bindings.len > 0:
        condition = quote do:
          block:
            `bindings`
            `comp`
      else:
        condition = comp

    of nnkIdent:
      let s = pattern.strVal
      if s == "_":
        if hasElse: error("Cannot have multiple wildcard/else branches.", pattern)
        let elseBody = if bindings.len > 0: quote do: block: `bindings`; `body` else: body
        result.add(newTree(nnkElse, elseBody))
        hasElse = true
        continue
      elif s in ["true", "false"]:
        let comp = quote do: `tmpVar` == `pattern`
        if bindings.len > 0:
          condition = quote do: block: `bindings`; `comp`
        else:
          condition = comp
      else:
        let captureBinding = quote do:
          when not compiles(`pattern`):
            let `pattern` {.inject.} = `tmpVar`
        bindings.add(captureBinding)

        condition = quote do:
          block:
            `bindings`
            when compiles(`pattern`):
              `tmpVar` == `pattern`
            else:
              true

    else:
      error("Unsupported pattern type: " & pattern.repr, pattern)

    result.add(newTree(nnkElifBranch, condition, body))

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
