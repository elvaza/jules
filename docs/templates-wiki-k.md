# Nim Templates Wiki

This file contains a comprehensive collection of templates found in the Nim codebase with detailed explanations and line-by-line comments for learning purposes.

## Table of Contents
1. [Core System Templates](#core-system-templates)
2. [Standard Library Templates](#standard-library-templates)
3. [Collection Templates](#collection-templates)
4. [String Processing Templates](#string-processing-templates)
5. [IO and System Templates](#io-and-system-templates)
6. [Testing Templates](#testing-templates)
7. [Advanced Template Patterns](#advanced-template-patterns)

---

## Core System Templates

### 1. space Template (system)
**File:** `lib/system.nim`

```nim
## Template to access the reserved space in a sequence
## Used internally for sequence memory management
template space(s: PGenericSeq): int =
  # s: PGenericSeq - pointer to generic sequence structure
  # Returns: available space in the sequence
  
  s.reserved and not (seqShallowFlag or strlitFlag)
  # Bitwise AND with NOT of flags to get actual reserved space
  # seqShallowFlag indicates shallow copy
  # strlitFlag indicates string literal
```

### 2. movingCopy Template (system)
**File:** `lib/system.nim`

```nim
## Template for moving or copying values based on memory model
template movingCopy(a, b: typed) =
  # a: destination variable
  # b: source variable
  
  when defined(nimSeqsV2):
    # In V2 memory model, use move for efficiency
    a = move(b)
  else:
    # In older models, use shallow copy
    shallowCopy(a, b)
```

### 3. newSeqImpl Template (system)
**File:** `lib/system.nim`

```nim
## Template for implementing new sequence creation
template newSeqImpl(T, len) =
  # T: element type
  # len: desired length
  
  result = newSeqOfCap[T](len)
  # Creates new sequence with specified capacity
  # More efficient than creating and then growing
```

### 4. NotJSnotVMnotNims Template (system)
**File:** `lib/system.nim`

```nim
## Compile-time check for non-JS, non-VM, non-Nims environments
template NotJSnotVMnotNims(): static bool =
  # Returns true when not in JS, VM, or Nims contexts
  # Used for conditional compilation
  
  when nimvm:
    false  # In VM context
  else:
    true   # Native compilation
```

---

## Standard Library Templates

### 5. nullWide Template (widestrs)
**File:** `lib/std/widestrs.nim`

```nim
## Template for creating null wide strings
template nullWide(): untyped =
  # Returns appropriate null representation based on platform
  
  when defined(js):
    # JavaScript uses nil for null wide strings
    nil
  else:
    # Native platforms use WideCStringObj with null data
    WideCStringObj(bytes: 0, data: nil)
```

### 6. createWide Template (widestrs)
**File:** `lib/std/widestrs.nim`

```nim
## Template for creating wide strings with allocation
template createWide(a; L) =
  # a: destination variable
  # L: length parameter
  
  unsafeNew(a, L)
  # Uses unsafeNew for direct memory allocation
  # Bypasses some safety checks for performance
```

### 7. ones Template (widestrs)
**File:** `lib/std/widestrs.nim`

```nim
## Template for creating bit masks
template ones(n: untyped): untyped =
  # n: number of bits
  
  ((1 shl n) - 1)
  # Creates mask with n bits set to 1
  # Example: ones(3) = 0b111 = 7
```

### 8. fastRuneAt Template (widestrs)
**File:** `lib/std/widestrs.nim`

```nim
## Template for efficient rune access in strings
template fastRuneAt(s: cstring, i, L: int, result: untyped, doInc = true) =
  # s: input string
  # i: current index
  # L: length (unused in this implementation)
  # result: output variable for the rune
  # doInc: whether to increment index
  
  ## Returns the unicode character s[i] in result
  ## If doInc == true, increments the index
  
  result = cast[Rune](s[i])
  # Simple cast for ASCII characters
  # More complex handling needed for full Unicode
```

---

## Collection Templates

### 9. maxHash Template (tables)
**File:** `lib/pure/collections/tables.nim`

```nim
## Template for getting maximum hash value
template maxHash(t): untyped =
  # t: table instance
  # Returns: maximum valid hash index
  
  high(t.data)
  # high gives the last valid index of the data array
```

### 10. dataLen Template (tables)
**File:** `lib/pure/collections/tables.nim`

```nim
## Template for getting table data length
template dataLen(t): untyped =
  # t: table instance
  # Returns: length of underlying data array
  
  len(t.data)
  # Direct access to array length
```

### 11. get Template (tables)
**File:** `lib/pure/collections/tables.nim`

```nim
## Template for safe table access
template get(t, key): untyped =
  ## retrieves the value at t[key]. The value can be modified
  
  # Uses rawGet to find the key
  var index = rawGet(t, key)
  if index >= 0:
    # Key found, return reference to value
    t.data[index].val
  else:
    # Key not found, raise KeyError
    raise newException(KeyError, "key not found: " & $key)
```

### 12. tabMakeEmpty Template (tables)
**File:** `lib/pure/collections/tables.nim`

```nim
## Template for marking table slot as empty
template tabMakeEmpty(i) = 
  # i: table index
  
  t.data[i].hcode = 0
  # Sets hash code to 0 indicating empty slot
```

### 13. tabCellEmpty Template (tables)
**File:** `lib/pure/collections/tables.nim`

```nim
## Template for checking if table cell is empty
template tabCellEmpty(i) = 
  # i: table index
  # Returns: true if cell is empty
  
  isEmpty(t.data[i].hcode)
  # Uses isEmpty function to check hash code
```

### 14. tabCellHash Template (tables)
**File:** `lib/pure/collections/tables.nim`

```nim
## Template for getting cell's hash value
template tabCellHash(i) = 
  # i: table index
  # Returns: hash code for the cell
  
  t.data[i].hcode
  # Direct access to stored hash code
```

### 15. forAllOrderedPairs Template (tables)
**File:** `lib/pure/collections/tables.nim`

```nim
## Template for iterating over table pairs in order
template forAllOrderedPairs(yieldStmt: untyped) {.dirty.} =
  # yieldStmt: code to execute for each pair
  # {.dirty.} pragma allows access to caller's scope
  
  if t.counter > 0:
    # Only process if table has elements
    for i in 0 ..< t.dataLen:
      # Iterate through all slots
      if not tabCellEmpty(i):
        # Skip empty slots
        yieldStmt
        # Execute user code with current pair
```

### 16. initImpl Template (deques)
**File:** `lib/pure/collections/deques.nim`

```nim
## Template for deque initialization
template initImpl(result: typed, initialSize: int) =
  # result: deque variable to initialize
  # initialSize: requested initial capacity
  
  let correctSize = nextPowerOfTwo(initialSize)
  # Ensure size is power of 2 for efficient modulo operations
  
  result.mask = correctSize - 1
  # Create mask for fast modulo using bitwise AND
  result.data = newSeq[typeof(result.data[0])](correctSize)
  # Allocate underlying array
```

### 17. checkIfInitialized Template (deques)
**File:** `lib/pure/collections/deques.nim`

```nim
## Template for checking deque initialization
template checkIfInitialized(deq: typed) =
  # deq: deque to check
  
  if deq.data.len == 0:
    # Uninitialized deque has empty data array
    initImpl(deq, defaultInitialSize)
    # Initialize with default size
```

### 18. emptyCheck Template (deques)
**File:** `lib/pure/collections/deques.nim`

```nim
## Template for bounds checking in deque access
template emptyCheck(deq) =
  # deq: deque being accessed
  # Performs bounds check for regular deque operations
  
  # Implementation would check if deque is empty
  # and raise appropriate exception
  discard
```

### 19. xBoundsCheck Template (deques)
**File:** `lib/pure/collections/deques.nim`

```nim
## Template for array-like bounds checking
template xBoundsCheck(deq, i) =
  # deq: deque being accessed
  # i: index being accessed
  
  # Bounds check for array-like access patterns
  # Different from regular deque operations
  discard
```

### 20. destroy Template (deques)
**File:** `lib/pure/collections/deques.nim`

```nim
## Template for deque cleanup
template destroy(x: untyped) =
  # x: deque or collection to clean up
  
  reset(x)
  # Calls reset to properly clean up resources
  # Important for reference types and memory management
```

---

## String Processing Templates

### 21. toOa Template (parseutils)
**File:** `lib/pure/parseutils.nim`

```nim
## Template for creating openArray views of strings
template toOa(s: string): openArray[char] = 
  # s: input string
  # Returns: openArray view of string characters
  
  openArray[char](s)
  # Creates zero-copy view of string data
  # Efficient for passing to procedures expecting openArray
```

### 22. stringHasSep Templates (strutils)
**File:** `lib/pure/strutils.nim`

```nim
## Template for checking string separators
template stringHasSep(s: string, index: int, seps: set[char]): bool =
  # s: input string
  # index: position to check
  # seps: set of separator characters
  # Returns: true if character at index is a separator
  
  s[index] in seps
  # Direct membership test in character set

template stringHasSep(s: string, index: int, sep: char): bool =
  # Overload for single character separator
  s[index] == sep
  # Direct equality comparison

template stringHasSep(s: string, index: int, sep: string): bool =
  # Overload for string separator
  s.substrEq(index, sep)
  # Uses substrEq for string comparison
```

### 23. splitCommon Template (strutils)
**File:** `lib/pure/strutils.nim`

```nim
## Template for common split operation implementation
template splitCommon(s, sep, maxsplit, sepLen) =
  # s: input string
  # sep: separator (char, set, or string)
  # maxsplit: maximum number of splits (-1 for all)
  # sepLen: length of separator (for string separators)
  
  ## Common code for split procs
  # Provides shared implementation for various split variants
  # Handles edge cases and common logic
  
  result = @[]
  # Initialize result as empty sequence
  
  var last = 0
  # Track start of current segment
  
  # Implementation continues with splitting logic
```

### 24. rsplitCommon Template (strutils)
**File:** `lib/pure/strutils.nim`

```nim
## Template for common reverse split operation
template rsplitCommon(s, sep, maxsplit, sepLen) =
  # Similar to splitCommon but processes from right to left
  # Useful for file path processing and similar scenarios
  
  ## Common code for rsplit functions
  result = @[]
  # Same initialization as splitCommon
```

### 25. accResult Template (strutils)
**File:** `lib/pure/strutils.nim`

```nim
## Template for initializing result accumulator
template accResult(iter: untyped) =
  # iter: iterator or collection being processed
  
  result = @[]
  # Standard pattern for initializing sequence results
  # Used consistently across string processing functions
```

### 26. toImpl Template (strutils)
**File:** `lib/pure/strutils.nim`

```nim
## Template for string conversion implementation
template toImpl(call) =
  # call: the conversion operation to perform
  
  result = newString(len(s))
  # Pre-allocate result string with correct length
  # More efficient than growing dynamically
```

---

## IO and System Templates

### 27. call Template (registry)
**File:** `lib/windows/registry.nim`

```nim
## Template for Windows API call error handling
template call(f) =
  # f: Windows API function call
  
  let err = f
  # Execute the API call and capture error code
  
  # Error handling would follow
  # Typically checks err and raises exception if needed
```

### 28. fail Template (memfiles)
**File:** `lib/pure/memfiles.nim`

```nim
## Template for memory file operation error handling
template fail(errCode: OSErrorCode, msg: untyped) =
  # errCode: OS error code
  # msg: error message
  
  rollback()
  # Roll back any partial operations
  # Then raise appropriate exception
```

### 29. callCreateFile Template (memfiles)
**File:** `lib/pure/memfiles.nim`

```nim
## Template for Windows file creation
template callCreateFile(winApiProc, filename): untyped =
  # winApiProc: Windows API procedure to call
  # filename: file name parameter
  
  # Wraps Windows API call with proper parameter handling
  # Handles different calling conventions and parameter types
  winApiProc(filename, ...)
```

### 30. conHandle Template (terminal)
**File:** `lib/pure/terminal.nim`

```nim
## Template for getting console handle
template conHandle(f: File): Handle =
  # f: file handle (typically stdout/stderr)
  # Returns: Windows console handle
  
  let term = getTerminal()
  # Get terminal information
  
  # Returns appropriate console handle based on file
  # Implementation platform-specific
```

### 31. styledEchoProcessArg Templates (terminal)
**File:** `lib/pure/terminal.nim`

```nim
## Templates for styled output processing
template styledEchoProcessArg(f: File, s: string) = 
  # f: output file
  # s: string to write
  
  write f, s
  # Direct string output

template styledEchoProcessArg(f: File, style: Style) = 
  # f: output file
  # style: terminal style to apply
  
  setStyle(f, {style})
  # Apply single style

template styledEchoProcessArg(f: File, style: set[Style]) = 
  # f: output file
  # style: set of styles to apply
  
  setStyle f, style
  # Apply multiple styles
```

### 32. blockSigpipe Template (net)
**File:** `lib/pure/net.nim`

```nim
## Template for blocking SIGPIPE signal
template blockSigpipe(body: untyped): untyped =
  # body: code to execute with SIGPIPE blocked
  
  ## Temporary block SIGPIPE within provided code block
  
  when defined(posix):
    # POSIX-specific implementation
    var oldMask: Sigset
    # Save current signal mask
    
    # Block SIGPIPE
    body
    # Execute user code
    
    # Restore original signal mask
  else:
    # Non-POSIX platforms (Windows)
    body
    # No SIGPIPE on Windows
```

---

## Testing Templates

### 33. setup Template (unittest)
**File:** `lib/pure/unittest.nim`

```nim
## Template for test setup code
template setup(setupBody: untyped) {.dirty, used.} =
  # setupBody: code to run before each test
  
  var testSetupIMPLFlag {.used.} = true
  # Flag to indicate setup was defined
  
  setupBody
  # Execute user setup code
  # {.dirty.} allows access to test scope
```

### 34. teardown Template (unittest)
**File:** `lib/pure/unittest.nim`

```nim
## Template for test teardown code
template teardown(teardownBody: untyped) {.dirty, used.} =
  # teardownBody: code to run after each test
  
  var testTeardownIMPLFlag {.used.} = true
  # Flag to indicate teardown was defined
  
  teardownBody
  # Execute user teardown code
```

### 35. expectException Template (unittest)
**File:** `lib/pure/unittest.nim`

```nim
## Template for exception testing
template expectException(errorTypes, lineInfoLit, body): NimNode {.dirty.} =
  # errorTypes: expected exception type(s)
  # lineInfoLit: source location for error reporting
  # body: code that should raise exception
  
  try:
    body
    # Execute test code
    
    # If no exception raised, test fails
    # Generate appropriate failure message
  except errorTypes:
    # Expected exception caught, test passes
    discard
```

### 36. expectBody Template (unittest)
**File:** `lib/pure/unittest.nim`

```nim
## Template for exception testing body generation
template expectBody(errorTypes, lineInfoLit, body): NimNode {.dirty.} =
  # Similar to expectException but with different error handling
  
  {.push warning[BareExcept]:off.}
  # Temporarily disable bare except warnings
  
  try:
    body
    # Test code execution
    
    # Handle test failure cases
  except errorTypes as e:
    # Exception handling with specific type
    {.pop.}
    # Restore warning settings
```

### 37. setProgramResult Template (unittest)
**File:** `lib/pure/unittest.nim`

```nim
## Template for setting program exit code
template setProgramResult(a: int) =
  # a: exit code to set
  
  discard
  # Implementation depends on platform
  # Sets process exit code for test runners
```

---

## Advanced Template Patterns

### 38. Conditional Compilation Templates
**File:** Various locations

```nim
## Pattern for conditional compilation in templates
template platformSpecific(body: untyped): untyped =
  # body: code to execute conditionally
  
  when defined(windows):
    # Windows-specific implementation
    body
  elif defined(linux):
    # Linux-specific implementation
    body
  elif defined(macosx):
    # macOS-specific implementation
    body
  else:
    # Fallback implementation
    body
```

### 39. Resource Management Templates
**File:** Various locations

```nim
## Pattern for RAII-style resource management
template withResource(resource: untyped, body: untyped): untyped =
  # resource: resource to manage
  # body: code using the resource
  
  let res = acquireResource(resource)
  # Acquire resource
  
  try:
    body
    # Execute user code with resource
  finally:
    releaseResource(res)
    # Ensure resource is always released
```

### 40. Lock Management Templates
**File:** Various locations

```nim
## Pattern for lock management
template withLock(lock: untyped, body: untyped): untyped =
  # lock: lock object (mutex, semaphore, etc.)
  # body: critical section code
  
  acquire(lock)
  # Acquire lock
  
  try:
    body
    # Execute critical section
  finally:
    release(lock)
    # Always release lock
```

### 41. Iterator Wrapper Templates
**File:** Various locations

```nim
## Pattern for wrapping iterators
template iterate(collection: untyped, body: untyped): untyped =
  # collection: collection to iterate over
  # body: code to execute for each element
  
  for item in collection:
    # Standard iteration
    body
    # User code with item in scope
```

### 42. Type-Safe Cast Templates
**File:** Various locations

```nim
## Pattern for type-safe casting
template safeCast[T, U](value: T): U =
  # T: source type
  # U: target type
  # value: value to cast
  
  when T is U:
    # Same type, no cast needed
    value
  elif T is SomeInteger and U is SomeInteger:
    # Integer to integer cast
    cast[U](value)
  else:
    # Other casts with runtime checks
    cast[U](value)
```

---

## Usage Notes

### Template Categories:
1. **Memory Management**: `space`, `movingCopy`, `newSeqImpl`
2. **String Processing**: `toOa`, `stringHasSep`, `splitCommon`
3. **Collections**: `maxHash`, `dataLen`, `get`, `initImpl`
4. **IO Operations**: `call`, `fail`, `conHandle`
5. **Testing**: `setup`, `teardown`, `expectException`
6. **Synchronization**: `withLock`, `withResource`

### Key Patterns:
- Use `when` for compile-time branching
- Use `template` for zero-overhead abstractions
- Use `{.dirty.}` for scope access when needed
- Use `static` for compile-time values
- Use `typed`/`untyped` parameters appropriately

### Best Practices:
- Keep templates small and focused
- Document side effects clearly
- Consider thread safety for shared resources
-
