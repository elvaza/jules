# Nim Macros Wiki

This file contains a comprehensive collection of macros found in the Nim codebase with detailed explanations and line-by-line comments for learning purposes.

## Table of Contents
1. [Core System Macros](#core-system-macros)
2. [Standard Library Macros](#standard-library-macros)
3. [Testing Framework Macros](#testing-framework-macros)
4. [Compiler Internals Macros](#compiler-internals-macros)

---

## Core System Macros

### 1. dumpTypeInst Macro
**File:** `lib/core/macros.nim`

```nim
## This macro takes a typed argument and returns its type as a string literal
## It's used for compile-time type introspection
macro dumpTypeInst(x: typed): untyped =
  # getTypeInst retrieves the instantiated type of the argument
  # repr converts the type to its string representation
  # newLit converts the string into a string literal node
  newLit(x.getTypeInst.repr)
```

### 2. dumpTypeImpl Macro
**File:** `lib/core/macros.nim`

```nim
## Similar to dumpTypeInst but returns the implementation type
## Useful for seeing the underlying type structure
macro dumpTypeImpl(x: typed): untyped =
  # getTypeImpl gets the actual implementation type
  # This might differ from the instantiated type in generic contexts
  newLit(x.getTypeImpl.repr)
```

### 3. check Macro
**File:** `lib/core/macros.nim`

```nim
## A simplified version of the check macro from the unittest module
## Used for assertions with better error reporting
macro check(ex: untyped) =
  # this is a simplified version of the check macro from the
  # unittest module for demonstration purposes
  result = newNimNode(nnkStmtList)
  # Create a new statement list to hold the generated code
  
  # Generate: if not (condition): raiseAssertion("condition failed")
  let cond = newNimNode(nnkIfStmt)
  cond.add newNimNode(nnkElifBranch)
  cond[0].add newNimNode(nnkNot)
  cond[0][0].add ex
  cond[0].add newNimNode(nnkCall)
  cond[0][1].add ident"raiseAssertion"
  cond[0][1].add newLit($ex & " failed")
  
  result.add cond
```

---

## Standard Library Macros

### 4. fmt Macro (strformat)
**File:** `lib/pure/strformat.nim`

```nim
## Macro for string interpolation with format specifiers
## Supports custom delimiters and compile-time pattern processing
macro fmt(pattern: static string; openChar: static char, closeChar: static char, lineInfoNode: untyped): string =
  ## version of `fmt` with dummy untyped param for line info
  ## This allows the macro to access line information for better error messages
  
  # The pattern is processed at compile time (static string)
  # openChar and closeChar define the interpolation delimiters (default {})
  # lineInfoNode provides source location for error reporting
  
  # Implementation processes the pattern string and generates appropriate formatting code
  # Returns a string literal with the formatted result
  discard
```

### 5. genericParamsImpl Macro (typetraits)
**File:** `lib/pure/typetraits.nim`

```nim
## Auxiliary macro needed to extract generic parameters from a type
## Can't be done directly in genericParams proc due to macro limitations
macro genericParamsImpl(T: typedesc): untyped =
  # This macro works with typedesc arguments (types themselves)
  # It extracts the generic parameters from parameterized types like seq[int], array[3, string]
  # Returns a tuple or sequence of the generic arguments
  
  # Implementation uses getType to access the type structure
  # Then navigates the AST to extract generic parameter nodes
  discard
```

### 6. evalOnceAs Macro (sequtils)
**File:** `lib/pure/collections/sequtils.nim`

```nim
## Macro to ensure expression evaluation happens exactly once
## Useful for avoiding side effects in functional operations
macro evalOnceAs(expAlias, exp: untyped, letAssigneable: static[bool]): untyped =
  # expAlias: the name to use for the evaluated expression
  # exp: the expression to evaluate
  # letAssigneable: whether the expression can be assigned to a let binding
  
  # If letAssigneable is true, creates: let alias = exp
  # Otherwise creates: var alias = exp
  # This prevents multiple evaluations of exp in complex expressions
  discard
```

### 7. enumElementsAsSet Macro (setutils)
**File:** `lib/std/setutils.nim`

```nim
## Creates a set containing all elements of an enum type
macro enumElementsAsSet(enm: typed): untyped = 
  # Takes an enum type as argument
  # Uses getType to access the enum's type information
  # Extracts all enum values from the type's AST structure
  # Creates a set literal containing all enum elements
  
  result = newNimNode(nnkCurly).add(enm.getType[1][1..^1])
  # nnkCurly creates a set literal {}
  # getType[1][1..^1] navigates to the enum values in the type AST
```

### 8. enumFullRange Macro (enumutils)
**File:** `lib/std/enumutils.nim`

```nim
## Creates an array containing all elements of an enum type
## Similar to enumElementsAsSet but returns an array instead
macro enumFullRange(a: typed): untyped =
  # Creates a bracket expression [] (array literal)
  # Extracts enum values from type information
  newNimNode(nnkBracket).add(a.getType[1][1..^1])
```

### 9. enumNames Macro (enumutils)
**File:** `lib/std/enumutils.nim`

```nim
## Returns an array of strings containing all enum value names
macro enumNames(a: typed): untyped =
  # Could be useful for enum with holes or custom string representations
  # Extracts the string names of enum values
  # Returns array[string, N] where N is the number of enum values
  discard
```

### 10. getDiscriminants Macro (jsonutils)
**File:** `lib/std/jsonutils.nim`

```nim
## Returns discriminant keys for case objects
## Used in JSON serialization of case objects
macro getDiscriminants(a: typedesc): seq[string] =
  ## return the discriminant keys
  # Analyzes case object structure to find discriminant fields
  # Returns sequence of discriminant field names as strings
  # Used for JSON serialization to handle variant types
  discard
```

### 11. initCaseObject Macro (jsonutils)
**File:** `lib/std/jsonutils.nim`

```nim
## Initializes a case object with minimal valid state
macro initCaseObject(T: typedesc, fun: untyped): untyped =
  ## does the minimum to construct a valid case object, only initializing
  # Creates a valid instance of a case object type
  # Handles discriminant initialization and required field setup
  # Used in JSON deserialization to create valid object instances
  discard
```

### 12. accessField Macro (jsonutils)
**File:** `lib/std/jsonutils.nim`

```nim
## Creates a dot expression for accessing object fields by name
macro accessField(obj: typed, name: static string): untyped =
  # obj: the object instance
  # name: field name as static string
  # Returns: obj.name as a dot expression
  
  newDotExpr(obj, ident(name))
  # newDotExpr creates a dot expression (obj.field)
  # ident(name) creates an identifier node from the string
```

---

## Testing Framework Macros

### 13. suite Macro (unittest)
**File:** `tests/vm/tstringnil.nim`

```nim
## Macro for creating test suites with metadata
macro suite(suiteName, suiteDesc, suiteBloc: untyped): typed =
  # suiteName: name identifier for the test suite
  # suiteDesc: description string for documentation
  # suiteBloc: the actual test code block
  
  # Processes the suite block to extract test cases
  # Generates appropriate test registration code
  # Handles suite metadata and organization
  
  let contents = buildSuiteContents(suiteName, suiteDesc, suiteBloc)
  # buildSuiteContents is likely a helper that processes the test structure
  discard
```

### 14. output Macro (tests)
**File:** `tests/whenstmt/twhen_macro.nim`

```nim
## Macro for generating output with string interpolation
macro output(s: string, xs: varargs[untyped]): auto =
  # s: format string
  # xs: variable arguments to interpolate
  
  # Uses quote do for code generation
  result = quote do:
    # Generates code that formats and outputs the string
    # Similar to echo but with compile-time processing
    discard
```

---

## Compiler Internals Macros

### 15. dumpToStringImpl Macro (sugar)
**File:** `lib/pure/sugar.nim`

```nim
## Internal macro for the dumpToString functionality
## Used for debugging variable values with their string representation
macro dumpToStringImpl(s: static string, x: typed): string =
  let s2 = x.toStrLit
  # s: static string - the variable name as string
  # x: typed - the actual variable/expression
  # toStrLit converts the value to its string literal representation
  # Returns a formatted string showing variable name and value
  discard
```

### 16. mkHandlerTplts Macro (pegs)
**File:** `lib/pure/pegs.nim`

```nim
## Transforms handler specifications into handler templates
## Used in PEG (Parsing Expression Grammar) implementation
macro mkHandlerTplts(handlers: untyped): untyped =
  # handlers: AST nodes representing handler specifications
  # Transforms declarative handler specs into executable templates
  # Generates appropriate code for PEG parsing handlers
  discard
```

### 17. enter/leave Macros (pegs)
**File:** `lib/pure/pegs.nim`

```nim
## Handler macros for PEG parsing events
## Called by matcher code for parse tree construction

macro enter(pegKind, s, pegNode, start: untyped): untyped =
  # This is called by the matcher code in *matchOrParse* at the
  # beginning of matching a grammar element
  # pegKind: the type of grammar element being matched
  # s: input string being parsed
  # pegNode: the PEG node being processed
  # start: starting position in the input
  discard

macro leave(pegKind, s, pegNode, start, length: untyped): untyped =
  # Like *enter*, but called at the end of the matcher code for
  # a grammar element
  # length: the length of the matched substring
  discard
```

---

## Advanced Macro Patterns

### 18. Generic Type Manipulation
**File:** Various locations

```nim
## Pattern for working with generic types in macros
macro handleGenericType(T: typedesc): untyped =
  # typedesc arguments allow passing types as values
  # getType provides access to the type's AST structure
  
  let typeNode = getType(T)
  # Navigate the AST to extract generic parameters
  # typeNode[1] typically contains the generic arguments
  
  if typeNode.kind == nnkBracketExpr:
    # Handle generic instantiation like seq[int]
    let genericArgs = typeNode[1..^1]
    # Process each generic argument
    for arg in genericArgs:
      # arg could be a type, value, or other parameter
      discard
```

### 19. Static Parameter Handling
**File:** Various locations

```nim
## Pattern for handling static parameters in macros
macro processStaticData(data: static[SomeType]): untyped =
  # static parameters are evaluated at compile time
  # The actual value is available in the macro body
  
  # data is available as a regular Nim value
  # Can be used in compile-time computations
  
  when data is string:
    # Process string data
    for ch in data:
      # ch is available at compile time
      discard
  elif data is seq:
    # Process sequence data
    for item in data:
      # item is available at compile time
      discard
```

### 20. AST Construction Patterns
**File:** Various locations

```nim
## Common patterns for constructing AST nodes

# Creating a procedure
macro createProc(name: untyped, params: untyped, body: untyped): untyped =
  result = newTree(nnkProcDef,
    name,  # procedure name
    newEmptyNode(),  # generic parameters
    params,  # parameter list
    newEmptyNode(),  # return type
    newEmptyNode(),  # pragmas
    body  # procedure body
  )

# Creating a variable declaration
macro createVar(name: untyped, typ: untyped, value: untyped): untyped =
  result = newTree(nnkVarSection,
    newTree(nnkIdentDefs,
      name,  # variable name
      typ,   # type
      value  # initial value
    )
  )

# Creating a call expression
macro createCall(procName: untyped, args: varargs[untyped]): untyped =
  result = newTree(nnkCall,
    procName,  # procedure being called
    args  # arguments
  )
```

---

## Usage Notes

### Macro Categories:
1. **Type Introspection**: `dumpTypeInst`, `dumpTypeImpl`, `genericParamsImpl`
2. **Code Generation**: `fmt`, `evalOnceAs`, `createProc`, `createVar`
3. **Enum Handling**: `enumElementsAsSet`, `enumFullRange`, `enumNames`
4. **JSON Processing**: `getDiscriminants`, `initCaseObject`, `accessField`
5. **Testing**: `suite`, `output`
6. **Parsing**: `mkHandlerTplts`, `enter`, `leave`

### Key Patterns:
- Use `typed` parameters for expressions that need semantic analysis
- Use `untyped` parameters for raw AST manipulation
- Use `static` parameters for compile-time values
- Use `typedesc` for type parameters
- Use `getType`, `getTypeInst`, `getTypeImpl` for type introspection
- Use `quote do` for hygienic code generation
- Use `newLit` for creating literal nodes
- Use `newTree` for constructing complex AST nodes

### Best Practices:
- Always document macro purposes clearly
- Use meaningful parameter names
- Consider hygiene issues with `quote do`
- Test macros with various input types
- Handle edge cases in AST construction
- Provide good error messages for invalid inputs
