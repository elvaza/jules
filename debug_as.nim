import std/macros

macro miniMatch*(scrutinee: typed, arms: untyped): untyped =
  let tmpVar = genSym(nskLet, "tmp")

  let arm = arms[0] # The block is a StmtList, get the first arm

  # Simplified unwrapping for `p as n`
  var p = arm[1]
  var n: NimNode
  if p.kind == nnkInfix and p[0].strVal == "as":
    n = p[2]
    p = p[1]

  var bindings = newStmtList()
  if n != nil:
    let isVarDef = false # always let for this test
    bindings.add(quote do:
      when not `isVarDef`:
        let `n` {.inject.} = `tmpVar`
    )

  let body = arm[2]

  let branchBody = if bindings.len > 0:
    quote do:
      block:
        `bindings`
        `body`
  else:
    body

  result = quote do:
    let `tmpVar` = `scrutinee`
    if true:
      `branchBody`
    else:
      discard

when isMainModule:
  let x = 99
  echo "Running minimal test..."
  let y = miniMatch x:
    _ as z => z

  echo "Result: ", y
  assert y == 99
  echo "Minimal test passed."
