import std/macros

## # Pattern Matching Library
##
## This library provides a `match` macro for pattern matching in Nim.

template to*(patt, name: untyped): untyped =
  ## Helper template to create a binding pattern (AS-pattern).
  ## Transforms `pattern.to(name)` into an AST node that `match` can parse.
  nnkInfix.newTree(ident"@", patt, name)

proc validateAndExtractArms(patterns: NimNode): seq[(NimNode, NimNode, NimNode)] =
  ## Parses, validates, and expands the arms of a match expression.
  ## Returns seq of (pattern, guard, body).
  if patterns.kind != nnkStmtList:
    error("Match arms must be provided as a statement list.", patterns)

  var expandedArms: seq[(NimNode, NimNode, NimNode)] = @[]

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

    var pattern = arm[1]
    let body = arm[2]
    var guard: NimNode = nil

    if pattern.kind == nnkInfix and pattern.len == 3 and pattern[0].kind == nnkIdent and pattern[0].strVal == "and":
      guard = pattern[2]
      pattern = pattern[1]

    if pattern.kind == nnkEmpty: error("Pattern cannot be empty.", arm)
    if body.kind == nnkEmpty: error("Body cannot be empty.", arm)

    let subPatterns = flatten(pattern)
    let isOrPattern = subPatterns.len > 1

    for p in subPatterns:
      if isOrPattern and p.kind == nnkIdent:
        if p.strVal == "_" or not compiles(p.repr):
          error("Variable bindings and wildcards are not permitted inside OR-patterns.", p)

      expandedArms.add((p, guard, body))

  if expandedArms.len == 0:
    error("Match expression must have at least one arm.", patterns)

  return expandedArms

proc genPatternCode(pattern, input: NimNode): NimNode =
  ## Recursively generates the condition for a given pattern.
  ## Bindings are generated inside the condition.
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
          block:
            let `pattern` {.inject.} = `input`
            true

  of nnkBracket:
    let patternLen = newLit(pattern.len)
    condition = quote do: `input`.len == `patternLen`
    for i, subPattern in pattern:
      let subInput = quote do: `input`[`i`]
      let subCond = genPatternCode(subPattern, subInput)
      condition = quote do: `condition` and `subCond`

  of nnkPar, nnkTupleConstr:
    condition = newIdentNode("true")
    for i, subPattern in pattern:
      let subInput = quote do: `input`[`i`]
      let subCond = genPatternCode(subPattern, subInput)
      condition = quote do: `condition` and `subCond`

  of nnkCurly, nnkTableConstr:
    condition = newIdentNode("true")
    for pair in pattern:
      if pair.kind != nnkExprColonExpr:
        error("Mapping patterns expect `key: value` pairs.", pair)
      let key = pair[0]
      let valPattern = pair[1]
      let hasKeyCheck = quote do: `input`.haskey(`key`)
      condition = quote do: `condition` and `hasKeyCheck`
      let valInput = quote do: `input`[`key`]
      let subCond = genPatternCode(valPattern, valInput)
      condition = quote do: `condition` and `subCond`

  of nnkCall, nnkObjConstr:
    let objType = pattern[0]
    condition = quote do: `input` is `objType`
    for i in 1..<pattern.len:
      let pair = pattern[i]
      if pair.kind != nnkExprColonExpr:
        error("Class patterns expect `field: value` pairs.", pair)
      let fieldName = pair[0]
      let fieldPattern = pair[1]
      let fieldInput = quote do: `input`.`fieldName`
      let subCond = genPatternCode(fieldPattern, fieldInput)
      condition = quote do: `condition` and `subCond`

  of nnkInfix:
    if pattern.len == 3 and pattern[0].kind == nnkIdent and pattern[0].strVal == "@":
      let p = pattern[1]
      let name = pattern[2]
      let p_cond = genPatternCode(p, input)

      condition = quote do:
        `p_cond` and (block:
          let `name` {.inject.} = `input`
          true)
    else:
      error("Unsupported pattern type: " & pattern.repr, pattern)

  else:
    error("Unsupported pattern type: " & pattern.repr, pattern)

  return condition

proc buildConditionalChain(arms: seq[(NimNode, NimNode, NimNode)], tmpVar: NimNode): NimNode =
  result = newTree(nnkIfStmt)
  var hasElse = false

  for (pattern, guard, body) in arms:
    if pattern.kind == nnkIdent and pattern.strVal == "_":
      if hasElse: error("Cannot have multiple wildcard/else branches.", pattern)
      if guard != nil: error("Wildcard pattern `_` cannot have a guard.", pattern)
      result.add(newTree(nnkElse, body))
      hasElse = true
      continue

    var condition = genPatternCode(pattern, tmpVar)
    if guard != nil:
      condition = quote do: `condition` and `guard`

    result.add(newTree(nnkElifBranch, condition, body))

  if not hasElse:
    let msg = newLit("Non-exhaustive pattern match. No branch was taken.")
    let exception = newCall(bindSym"newException", ident("Defect"), msg)
    let raiseStmt = newTree(nnkRaiseStmt, exception)
    result.add(newTree(nnkElse, raiseStmt))

  return result

macro `match`*(scrutinee: typed, patterns: untyped): untyped =
  let arms = validateAndExtractArms(patterns)
  let tmpVar = genSym(nskLet, "tmp")
  let conditionalChain = buildConditionalChain(arms, tmpVar)

  result = quote do:
    block:
      let `tmpVar` = `scrutinee`
      `conditionalChain`
