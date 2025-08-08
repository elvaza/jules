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
      # Basic validation for OR-patterns.
      if isOrPattern and p.kind == nnkIdent:
        if p.strVal == "_" or not compiles(p.repr):
          error("Variable bindings and wildcards are not permitted inside OR-patterns.", p)

      expandedArms.add((p, body))

  if expandedArms.len == 0:
    error("Match expression must have at least one arm.", patterns)

  return expandedArms

proc genPatternCode(pattern, input: NimNode): (NimNode, NimNode) =
  ## Recursively generates the code for a given pattern.
  ## Returns a tuple of (condition, bindings).
  var bindings = newStmtList()
  var condition: NimNode

  case pattern.kind
  of nnkIntLit..nnkUInt64Lit, nnkFloatLit..nnkFloat64Lit,
     nnkStrLit..nnkTripleStrLit, nnkCharLit, nnkDotExpr:
    condition = quote do: `input` == `pattern`

  of nnkIdent:
    let s = pattern.strVal
    if s == "_":
      condition = newIdentNode("true")
    elif s in ["true", "false"]:
      condition = quote do: `input` == `pattern`
    else:
      condition = quote do:
        when compiles(`pattern`):
          `input` == `pattern`
        else:
          true

      bindings.add(quote do:
        when not compiles(`pattern`):
          let `pattern` {.inject.} = `input`)

  of nnkBracket: # Sequence or Array Pattern
    let patternLen = newLit(pattern.len)
    condition = quote do: `input`.len == `patternLen`

    for i, subPattern in pattern:
      let subInput = quote do: `input`[`i`]
      let (subCond, subBinds) = genPatternCode(subPattern, subInput)
      condition = quote do: `condition` and `subCond`
      for b in subBinds: bindings.add(b)

  of nnkPar, nnkTupleConstr: # Tuple Pattern
    condition = newIdentNode("true") # Assume length is correct for now

    for i, subPattern in pattern:
      let subInput = quote do: `input`[`i`]
      let (subCond, subBinds) = genPatternCode(subPattern, subInput)
      condition = quote do: `condition` and `subCond`
      for b in subBinds: bindings.add(b)

  else:
    error("Unsupported pattern type: " & pattern.repr, pattern)

  return (condition, bindings)

proc buildConditionalChain(arms: seq[(NimNode, NimNode)], tmpVar: NimNode): NimNode =
  ## Constructs the if/elif/else chain from the match arms.
  result = newTree(nnkIfStmt)
  var hasElse = false

  for (pattern, body) in arms:
    if pattern.kind == nnkIdent and pattern.strVal == "_":
      if hasElse: error("Cannot have multiple wildcard/else branches.", pattern)
      result.add(newTree(nnkElse, body))
      hasElse = true
      continue

    let (condition, bindings) = genPatternCode(pattern, tmpVar)
    let branchBody = if bindings.len > 0: newStmtList(bindings, body) else: body
    result.add(newTree(nnkElifBranch, condition, branchBody))

  if not hasElse:
    let msg = newLit("Non-exhaustive pattern match. No branch was taken.")
    let exception = newCall(bindSym"newException", ident("Defect"), msg)
    let raiseStmt = newTree(nnkRaiseStmt, exception)
    result.add(newTree(nnkElse, raiseStmt))

  return result

macro `match`*(scrutinee: typed, patterns: untyped): untyped =
  ## The main match macro.

  let arms = validateAndExtractArms(patterns)
  let tmpVar = genSym(nskLet, "tmp")
  let conditionalChain = buildConditionalChain(arms, tmpVar)

  result = quote do:
    block:
      let `tmpVar` = `scrutinee`
      `conditionalChain`
