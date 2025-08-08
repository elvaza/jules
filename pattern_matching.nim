import std/macros

## # Pattern Matching Library
##
## This library provides a `match` macro for pattern matching in Nim.

type
  PatternKind = enum
    pkLiteral, pkVariable, pkWildcard, pkUnsupported

proc classifyPattern(n: NimNode): PatternKind =
  ## Classifies a pattern node into Literal, Variable, Wildcard, etc.
  case n.kind
  of nnkIntLit..nnkUInt64Lit, nnkFloatLit..nnkFloat64Lit,
     nnkStrLit..nnkTripleStrLit, nnkCharLit:
    return pkLiteral
  of nnkIdent:
    let s = n.strVal
    if s == "_":
      return pkWildcard
    elif s in ["true", "false"]:
      return pkLiteral
    else:
      return pkVariable
  else:
    return pkUnsupported

# Note: asNames is kept in the tuple for structure, but is unused.
proc validateAndExtractArms(patterns: NimNode): seq[(NimNode, NimNode, seq[NimNode])] =
  ## Parses, validates, and expands the arms of a match expression.
  ## Returns seq of (pattern, body, as-names).
  if patterns.kind != nnkStmtList:
    error("Match arms must be provided as a statement list.", patterns)

  var expandedArms: seq[(NimNode, NimNode, seq[NimNode])] = @[]
  var hasWildcard = false

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
    let asNames: seq[NimNode] = @[] # AS patterns disabled for now

    if currentPattern.kind == nnkEmpty: error("Pattern cannot be empty.", arm)
    if body.kind == nnkEmpty: error("Body cannot be empty.", arm)

    let subPatterns = flatten(currentPattern)
    let isOrPattern = subPatterns.len > 1

    for p in subPatterns:
      let kind = classifyPattern(p)

      if isOrPattern and kind in [pkVariable, pkWildcard]:
        error("Variable bindings and wildcards are not permitted inside OR-patterns.", p)

      if kind == pkWildcard:
        if hasWildcard: error("Multiple wildcard patterns `_` are not allowed.", p)
        hasWildcard = true
      elif kind == pkUnsupported:
        error("Unsupported pattern type: " & p.repr, p)

      expandedArms.add((p, body, asNames))

  if expandedArms.len == 0:
    error("Match expression must have at least one arm.", patterns)

  return expandedArms

proc buildConditionalChain(arms: seq[(NimNode, NimNode, seq[NimNode])], tmpVar: NimNode): NimNode =
  ## Constructs the if/elif/else chain from the match arms.
  result = newTree(nnkIfStmt)
  var wildcardBody: NimNode = nil
  var wildcardAsNames: seq[NimNode] = @[]

  proc createBody(body: NimNode, bindings: NimNode): NimNode =
    if bindings.len == 0:
      return body
    else:
      return quote do:
        block:
          `bindings`
          `body`

  for (pattern, body, asNames) in arms:
    let allBindings = newStmtList() # AS patterns disabled, so this is empty.

    let kind = classifyPattern(pattern)
    case kind
    of pkLiteral:
      let condition = quote do: `tmpVar` == `pattern`
      result.add(newTree(nnkElifBranch, condition, createBody(body, allBindings)))
    of pkVariable:
      let isVarDef = false
      allBindings.add(quote do:
        when not `isVarDef`:
          let `pattern` {.inject.} = `tmpVar`
      )
      let condition = newIdentNode("true")
      result.add(newTree(nnkElifBranch, condition, createBody(body, allBindings)))
    of pkWildcard:
      wildcardBody = body
      wildcardAsNames = asNames
    else:
      error("Internal error: encountered unsupported pattern in builder.", pattern)

  if wildcardBody != nil:
    let allBindings = newStmtList() # AS patterns disabled
    result.add(newTree(nnkElse, createBody(wildcardBody, allBindings)))
  else:
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
