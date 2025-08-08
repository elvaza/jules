# Nim Match Macro Implementation Research

## 1. Patterns Block AST Shape

### Understanding the Macro Input Structure

When you define a match macro like this:
```nim
match v:
  p1 => body1
  p2 => body2
```

The second parameter (patterns block) arrives as an `nnkStmtList` containing multiple children. Each pattern-body pair becomes an `nnkInfix` node with the operator identifier "=>".

### Concrete AST Structure Examples

For a single arm:
```nim
# Input: match v: 42 => "found"
# patterns parameter structure:
nnkStmtList(
  nnkInfix(
    ident("=>"),          # operator
    nnkIntLit(42),        # pattern (left operand)
    nnkStrLit("found")    # body (right operand)
  )
)
```

For multiple arms:
```nim
# Input: match v: 1 => "one"; 2 => "two"; _ => "other"
# patterns parameter structure:
nnkStmtList(
  nnkInfix(ident("=>"), nnkIntLit(1), nnkStrLit("one")),
  nnkInfix(ident("=>"), nnkIntLit(2), nnkStrLit("two")),
  nnkInfix(ident("=>"), ident("_"), nnkStrLit("other"))
)
```

### Defensive Traversal Pattern

To avoid "cannot get child of node kind: nnkEmpty" errors, use this defensive iteration approach:

```nim
macro match(scrutinee: typed, patterns: untyped): untyped =
  # Generate unique temporary variable
  let tmpVar = genSym(nskVar, "tmp")
  
  # Validate patterns is statement list
  if patterns.kind != nnkStmtList:
    error("Expected statement list after colon", patterns)
  
  var arms: seq[(NimNode, NimNode)] = @[]
  
  # Defensive iteration over arms
  for i in 0..<patterns.len:
    let arm = patterns[i]
    
    # Skip empty nodes and comments
    if arm.kind in {nnkEmpty, nnkCommentStmt}:
      continue
      
    # Validate arm structure
    if arm.kind != nnkInfix or arm.len != 3:
      error("Expected pattern => body, got: " & arm.repr, arm)
      
    if arm[0].kind != nnkIdent or arm[0].strVal != "=>":
      error("Expected '=>' operator", arm[0])
    
    let pattern = arm[1]
    let body = arm[2]
    
    # Ensure pattern and body are non-empty
    if pattern.kind == nnkEmpty:
      error("Pattern cannot be empty", arm)
    if body.kind == nnkEmpty:
      error("Body cannot be empty", arm)
    
    arms.add((pattern, body))
```

## 2. Detecting Pattern Kinds

### Literal Patterns

Different literal types have distinct node kinds:
- **Integers**: `nnkIntLit`, `nnkInt8Lit`, `nnkInt16Lit`, `nnkInt32Lit`, `nnkInt64Lit`, `nnkUIntLit` (and unsigned variants)
- **Floats**: `nnkFloatLit`, `nnkFloat32Lit`, `nnkFloat64Lit`
- **Strings**: `nnkStrLit`, `nnkRStrLit`, `nnkTripleStrLit`
- **Characters**: `nnkCharLit`

### Boolean Literal Detection

**IMPORTANT CORRECTION**: Boolean literals `true` and `false` appear as `nnkIdent` nodes with `strVal` of "true" or "false" when parsed from source (confirmed by Issue #2726), but when using `newLit(true)` they become `nnkIntLit` with values 1 and 0 respectively. For pattern matching from user syntax, they will be `nnkIdent`:

```nim
proc isLiteralPattern(node: NimNode): bool =
  case node.kind:
  of nnkIntLit..nnkUInt64Lit, nnkFloatLit..nnkFloat128Lit, 
     nnkStrLit..nnkTripleStrLit, nnkCharLit:
    true
  of nnkIdent:
    # Boolean literals from parsed source appear as identifiers
    node.strVal in ["true", "false"]
  else:
    false
```

### Wildcard Pattern Detection

Wildcard patterns use the identifier "_" and appear as `nnkIdent` with `strVal` equal to "_":

```nim
proc isWildcardPattern(node: NimNode): bool =
  node.kind == nnkIdent and node.strVal == "_"
```

### Variable Pattern Detection

Any `nnkIdent` that is not a boolean literal or wildcard is treated as a binding variable. This is the safest heuristic for a DSL context:

```nim
proc isVariablePattern(node: NimNode): bool =
  node.kind == nnkIdent and 
  node.strVal notin ["_", "true", "false"]
```

**Important Caveat**: This approach treats any identifier as a binding variable rather than checking for existing symbols. This is appropriate for a pattern matching DSL where you want to create new bindings, but be aware that it won't catch attempts to match against existing constants.

## 3. Hygienic Variable Binding

### Creating Injected Bindings

For variable patterns, you need to create a binding that's visible within the branch body but doesn't leak outside. Use the `{.inject.}` pragma:

```nim
proc createVariableBinding(varName: NimNode, tmpVar: NimNode): NimNode =
  # Create: let `varName` {.inject.} = `tmpVar`
  let letSection = newTree(nnkLetSection,
    newTree(nnkIdentDefs,
      newTree(nnkPragmaExpr,
        varName,
        newTree(nnkPragma, ident("inject"))
      ),
      newEmptyNode(),  # no explicit type
      tmpVar
    )
  )
  
  return letSection
```

### Alternative Quote Syntax

You can also use quote syntax for cleaner code:

```nim
proc createVariableBinding(varName: NimNode, tmpVar: NimNode): NimNode =
  quote do:
    let `varName` {.inject.} = `tmpVar`
```

### Hygiene Strategy

- **Scrutinee temporary**: Use `genSym(nskVar, "tmp")` to create a unique temporary variable for the scrutinee value
- **Bound variables**: Use the original identifier with `{.inject.}` pragma so users see the expected name in their branch bodies
- **Internal helpers**: Use `genSym` for any other temporary variables

## 4. Building If/Elif/Else Chains

### Constructing the Conditional Chain

Here's the idiomatic approach using `newTree`:

```nim
proc buildConditionalChain(arms: seq[(NimNode, NimNode)], tmpVar: NimNode): NimNode =
  var result = newTree(nnkIfStmt)
  var hasWildcard = false
  var wildcardBody: NimNode = nil
  
  for (pattern, body) in arms:
    if isWildcardPattern(pattern):
      if hasWildcard:
        error("Multiple wildcard patterns not allowed")
      hasWildcard = true
      wildcardBody = body
    else:
      let condition = createCondition(pattern, tmpVar)
      let branchBody = if isVariablePattern(pattern):
        newTree(nnkStmtList,
          createVariableBinding(pattern, tmpVar),
          body
        )
      else:
        body
      
      let branch = if result.len == 0:
        newTree(nnkElifBranch, condition, branchBody)
      else:
        newTree(nnkElifBranch, condition, branchBody)
      
      result.add(branch)
  
  # Add else branch for wildcard or error
  if hasWildcard:
    result.add(newTree(nnkElse, wildcardBody))
  else:
    # Generate compile-time error for exhaustiveness
    result.add(newTree(nnkElse,
      newCall(ident("error"), newLit("Non-exhaustive pattern match"))
    ))
  
  return result
```

### Alternative Quote Syntax Approach

```nim
proc buildConditionalChain(arms: seq[(NimNode, NimNode)], tmpVar: NimNode): NimNode =
  var ifStmt = newTree(nnkIfStmt)
  
  for i, (pattern, body) in arms.pairs:
    if isWildcardPattern(pattern):
      ifStmt.add(newTree(nnkElse, body))
    elif isLiteralPattern(pattern):
      let condition = quote do: `tmpVar` == `pattern`
      let branch = if i == 0:
        newTree(nnkElifBranch, condition, body)
      else:
        newTree(nnkElifBranch, condition, body)
      ifStmt.add(branch)
    else: # variable pattern
      let binding = createVariableBinding(pattern, tmpVar)
      let fullBody = quote do:
        `binding`
        `body`
      let condition = quote do: true
      ifStmt.add(newTree(nnkElifBranch, condition, fullBody))
  
  return ifStmt
```

## 5. Comparison Semantics

### Literal Equality Checks

For most literal types, simple equality (`==`) works correctly:
- **Integers**: Direct equality comparison
- **Strings**: Content equality
- **Booleans**: Value equality
- **Characters**: Direct equality

### Float Comparison Considerations

Float equality has the usual IEEE 754 pitfalls. For this implementation, we'll use direct equality but document the limitation. In production code, you might want to consider:
- Using approximate equality for float patterns
- Warning users about float pattern matching pitfalls
- Providing a way to specify tolerance

### Case vs If/Elif Decision

Nim's `case` statements only work with ordinal types (integers, enums, chars, bools). Since our match macro should handle strings and potentially other types, we'll standardize on `if/elif/else` chains for consistency and flexibility.

**Pros of if/elif**:
- Works with any comparable type
- Consistent behavior across all pattern types
- Easier to extend with custom comparison logic

**Cons**:
- Potentially less optimized than case for ordinal types
- More verbose AST generation

## 6. Error Handling and Diagnostics

### Validation Checks

Implement these defensive checks with clear error messages:

```nim
proc validateMatchArms(patterns: NimNode): seq[(NimNode, NimNode)] =
  if patterns.kind != nnkStmtList:
    error("Match arms must be provided as statement list", patterns)
  
  var arms: seq[(NimNode, NimNode)] = @[]
  var wildcardCount = 0
  
  for i in 0..<patterns.len:
    let arm = patterns[i]
    
    # Skip empty nodes and comments
    if arm.kind in {nnkEmpty, nnkCommentStmt}:
      continue
    
    # Validate infix structure
    if arm.kind != nnkInfix:
      error("Expected 'pattern => body', got: " & $arm.kind, arm)
    
    if arm.len != 3:
      error("Malformed infix expression", arm)
    
    if arm[0].kind != nnkIdent or arm[0].strVal != "=>":
      error("Expected '=>' operator, got: " & arm[0].strVal, arm[0])
    
    let pattern = arm[1]
    let body = arm[2]
    
    # Validate pattern and body are not empty
    if pattern.kind == nnkEmpty:
      error("Pattern cannot be empty", arm)
    if body.kind == nnkEmpty:
      error("Body cannot be empty", arm)
    
    # Count wildcards
    if isWildcardPattern(pattern):
      wildcardCount += 1
      if wildcardCount > 1:
        error("Multiple wildcard patterns not allowed", pattern)
    
    arms.add((pattern, body))
  
  if arms.len == 0:
    error("Match expression must have at least one arm", patterns)
  
  return arms
```

### Helpful Error Messages

Generate compile-time errors that guide the user:
- "Expected 'pattern => body', got: nnkCall" (clear format expectation)
- "Multiple wildcard patterns not allowed" (specific constraint violation)
- "Pattern cannot be empty" (specific validation failure)
- "Match expression must have at least one arm" (usage requirement)

## 7. Nested Match Expressions and Hygiene

### Hygiene Model

Each match macro invocation creates its own hygiene scope:
- **Unique temporary variables**: Each match uses `genSym` for its scrutinee temporary, preventing conflicts
- **Scoped bindings**: Variable bindings with `{.inject.}` are only visible within their respective branch
- **No interference**: Nested matches work independently

### Example of Nested Hygiene

```nim
match outer:
  x => 
    match inner:
      y => x + y  # 'x' is from outer match, 'y' from inner
      _ => x
```

Each match creates its own temporary variable (`tmp1`, `tmp2` via `genSym`), and each variable binding is scoped to its branch.

## 8. Complete Implementation Blueprint

### Step-by-Step Transformation Process

1. **Generate scrutinee binding**:
   ```nim
   let tmp = genSym(nskVar, "tmp")
   let scrutineeBinding = quote do:
     let `tmp` = `scrutinee`
   ```

2. **Parse and validate arms**:
   - Iterate through statement list
   - Skip empty nodes and comments
   - Validate infix "=>" structure
   - Extract pattern-body pairs
   - Count wildcards and validate constraints

3. **Generate conditions for each pattern type**:
   - **Literals**: `tmp == literal`
   - **Variables**: `true` (always match) + create injected binding
   - **Wildcards**: Reserved for else clause

4. **Build if/elif/else chain**:
   - First non-wildcard arm becomes if branch
   - Subsequent arms become elif branches
   - Wildcard becomes else branch
   - If no wildcard, generate error in else

5. **Wrap in statement block**:
   ```nim
   result = quote do:
     block:
       let `tmp` = `scrutinee`
       `conditionalChain`
   ```

### TreeRepr Examples

**Input**:
```nim
match x:
  42 => "answer"
  y => "variable: " & $y
  _ => "other"
```

**Generated AST Structure** (conceptual):
```nim
block:
  let tmp_123 = x
  if tmp_123 == 42:
    "answer"
  elif true:
    let y {.inject.} = tmp_123
    "variable: " & $y
  else:
    "other"
```

## 9. Known Pitfalls and Avoidance Strategies

### nnkEmpty Node Handling
- **Problem**: Trailing newlines or comments can create nnkEmpty nodes
- **Solution**: Skip nnkEmpty and nnkCommentStmt when iterating arms

### Variable vs Symbol Resolution
- **Problem**: Distinguishing between variable patterns and existing symbols
- **Solution**: In DSL context, treat all non-reserved identifiers as binding variables

### Wildcard Validation
- **Problem**: Multiple wildcards or no catch-all case
- **Solution**: Count wildcards during parsing, generate error for exhaustiveness

### Float Pattern Matching
- **Problem**: IEEE 754 equality issues
- **Solution**: Document limitation, use direct equality with caveats

### Hygiene Conflicts
- **Problem**: Variable name collisions between nested matches
- **Solution**: Use genSym for temporary variables, {.inject.} for user-visible bindings

## 10. Implementation-Ready Code Snippets

### Core Pattern Detection

```nim
proc classifyPattern(node: NimNode): PatternKind =
  case node.kind:
  of nnkIntLit..nnkUInt64Lit, nnkFloatLit..nnkFloat128Lit,
     nnkStrLit..nnkTripleStrLit, nnkCharLit:
    PatternKind.Literal
  of nnkIdent:
    case node.strVal:
    of "_": PatternKind.Wildcard
    of "true", "false": PatternKind.Literal
    else: PatternKind.Variable
  else:
    error("Unsupported pattern type: " & $node.kind, node)
```

### Condition Generation

```nim
proc createCondition(pattern: NimNode, tmpVar: NimNode): NimNode =
  case classifyPattern(pattern):
  of PatternKind.Literal:
    quote do: `tmpVar` == `pattern`
  of PatternKind.Variable:
    quote do: true
  of PatternKind.Wildcard:
    error("Wildcard should be handled as else case", pattern)
```

This research provides a comprehensive foundation for implementing the match macro with robust error handling, proper hygiene, and clear transformation patterns.