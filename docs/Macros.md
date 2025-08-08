# Macros

Description: Macros and Templates for Nim programing language

&nbsp;

- Comments begin with `#` character

&nbsp;

```
import std/macros

macro debug(args: varargs[untyped]): untyped = 
  result = newNimNode(nnkStmtList, args)
  for a in args:
    result.add newCall("write", ident"stdout", toStrLit(a))
    result.add newCall("write", ident"stdout", newLit(": "))
    result.add newCall("writeLine", ident"stdout", a)

var 
  a: array[0..10, int] 
  x = "some string"

a[0] = 42
a[1] = 45
debug(a[0], a[1], x)

# toStrLit(a) - je ustvari - a[0], ili x
# newLit(":") - da ispisemo obicni karakter
# Output ovog debug je:
#   a[0]: 42
#   a[1]: 45
#   x: some string
#####################
# So basicaly it expands to
# write(stdout, "a[0]")
# write(stdout, ": ")
# writeLine(stdout, a[0]) 

```

## BindSym

```
import macros

macro debug(n: varargs[typed]): untyped =
  result = newNimNode(nnkStmtList, n)
  for x in n:
    # we can bind symbols in scope via 'bindSym':
    result.add newCall(bindSym"write", bindSym"stdout", toStrLit(x))
    result.add newCall(bindSym"write", bindSym"stdout", newStrLitNode": ")
    result.add newCall(bindSym"writeLine", bindSym"stdout", x)
    
var
  a: array[0..10,int]
  x = "some string"

a[0] = 42
a[1] = 45

debug(a[0], a[1], x)

# Output
# a[0]: 42
# a[1]: 45
# x: some string

```

## Difference between bindSym"name" and ident"name"

- This is valid code

```
import macros

macro m(a: string): untyped =
  proc helper(a: string) = echo a

  result = newCall(bindSym"helper", a)

m "abc"
# will expand to 
# echo "abc" and output will be "abc"
```

- And this is invalid code:

```
import macros

macro m(a: string): untyped =
 proc helper(a: string) = echo a

  result = newCall(ident"helper", a)

m "abc"
#THIS WILL NOT WORK
```

- Note that in both cases `helper` is local to the macro m and invisible outside of `m`'s body.

&nbsp;

* * *

## For loop macros

```
macro example(loop: ForLoopStmt) =
    result = newTree(nnkForStmt) # Create a new loop
    result.add loop[^3]          # This is item
    result.add loop[^2][^1] 	 # This is "[1, 2, 3]"
    result.add newCall(bindSym"echo", loop[0])

for item in example([1,2,3]): discard

# Expands to
# for item in items([1,2,3]):
# 	echo item
```

```Nim
import macros

macro enumerate(x: ForLoopStmt): untyped =
    expectKind x, nnkForStmt
    #check if the starting count is specified
    var countStart = if x[^2].len: newLit(0) else: x[^2][1]
    result = newStmtList()
    #we strip off the first for loop variable
    # and use it as an integer counter
    result.add newVarStmt(x[0], countStart)
    var body = x[^1]
    if body.kind != nnkStmtList:
        body = newTree(nnkStmtList, body)
    body.add newCall(bindSym"inc", x[0])
    var newFor = newTree(nnkForStmt)
    for i in 1..x.len-3:
        newFor.add x[i]
    # transform enumerate(x) to "x":
    newFor.add x[^2][^1]
    newFor.add body
    result.add newFor
    #wrap the whole macro in a block to create a new scope:
    result = newTree(nnBlockExpr, newEmptyNode(), result)

for a,b in enumerate(items([1,2,3])):
    echo a, " ", b

# without wrapping the macro in black, we need to chose different
# names for 'a', and 'b' here to avoid redefinition errors

for a, b in enumerate(10, [1,2,3,5]):
    echo a, " ", b
    

```

* * *

# Mastering Macros

## AST introspection

The mapping from Nim's syntax to syntax trees is rather subtle. While the syntax is optimized for readability and conciseness the syntax trees are designed for ease of construction and traversal.  
Like in Lisp the tree consists of nested nodes where each node is of a certain "kind" such as "if statement"  
(nnkIfStmt) or "routine call" (nnkCall).

The mapping can easily be seen with treeRepr:

```Nim
import macros

macro investigate(body: untyped) =
 echo treeRepr body

investigate:
 if undeclaredIdentifier == 3:
   echo "3"
 else:
  echo "not 3"

## This is the output
# Because macro expansion happens at compile time this program produces at compile time:
#.......................................................................
#StmtList
#  IfStmt
#    ElifBranch
#      Infix
#        Ident "=="
#        Ident "undeclaredIdentifier"
#        IntLit 3
#      StmtList
#        Command
#          Ident "echo"
#          StrLit "3"
#    Else
#      StmtList
#        Command
#          Ident "echo"
#          StrLit "not 3"
```

- Declares a macro called investigate that works on untyped trees
- Calls treeRepr which produces a debug string of body.

We can see that a list of statements StmtList is passed to investigate. In order to create a StmtList one can use newTree(nnkStmtList, <children here="">).</children>

## 33.1. Typed vs untyped ASTs

The difference between typed and untyped parameters is important for templates and it is even more important for macros.  
The AST that is passed to a typed macro parameter can differ significantly from an AST that is passed to an untyped macro parameter.

For example:

```
import macros

macro investigateTyped (body: typed) =
    echo treeRepr body

var needsToBeDeclaredIdentifier = 0
investigateTyped:
    if needsToBeDeclaredIdentifier == 3:
        echo "3"
    else:
        echo "not 3"
```

This program produces at compile time:

```
StmtList
    IfStmt
        ElifBranch
            Infix
                Sym "=="！
                Sym "needsToBeDeclaredIdentifier"
                IntLit 3
            Command
                Sym "echo"
                HiddenStdConv
                    Empty
                    Bracket
                        Strlit "3"
        Else
            Command
                Sym "echo"
                HiddenStdConv
                    Empty
                    Bracket
                    StrLit "not 3"
```

Note how symbol lookups happened producing nnkSym nodes and the echo calls have mysterious hidden conversion nodes containing an nnkBracket node.  
In other words, echo "3" was transformed into echo \["3"\] because echo uses a varargs parameter.  
Many details like these have to be understood before one can write a macro operating on typed ASTs.  
For this reason most of the following examples operate on untyped ASTs.

## Chapter 34. AST creation

An AST can be created in different ways and these ways can all be combined freely.  
But one of the easiest ways is to use quote do.  
For example, an operator `==~` that checks if two floating point values almost equal can be written as a template:

```
template '==~'(x, y: float): bool = abs (x - y) < 1e-9
```

Or it can be written as a macro that uses quote do:

```
import macros

macro '==~' (x, y: float): bool =
    result = quote do:
    abs ('x' - 'y') < 1e-9
```

quote do turns a pattern of code into a `NiNode`.  
Inside the pattern backticks can be used to access symbols from the macro's scope.  
The `==~` macro can also be written as:

```
import macros

macro '==~' (x, y: float): bool =
    result = newCall(bindSym"<",
        newCall(bindSym"abs", newCall(bindSym"-", x, y)),
        newLit(1e-9))
```

In my opinion this more imperative style of AST creation is easier to understand for beginners and so it is what is used in the following more complex examples.

## Chapter 35. Collect macro

As our first complex example we will look at how Nim's collect macro can be implemented.  
The standard library already contains `collect`, it can be found in `std/sugar`. `collect` is the preferred method of turning a potentially nested loop construct from a statement to an expression.

Instead of:

```
import std/tables

const Data = toTable({"a": 1, "b": 2, "с": 3})

var s = newSeq[string]()
for k, v in Data.pairs:
    if v mod 2 == 0:
        s.add k
```

One can use the more declarative:

```
import std/[tables, sugar]

const Data = toTable({"a": 1, "b": 2, "с": 3})

let s = collect(newSeq):
    for k, v in Data.pairs:
        if v mod 2 == 0: k
```

An an exercise we will reimplement collect. For a beginner, writing a macro is usually a hard task.  
As the first step we postulate the code pattern that the macro needs to expand to: `collect(constructorCall): body` should be translated into something like:

```
block:
    var tmp = constructorCall[type0f(body)]()
    sinkInto (body, tmp.add)
    tmp
```

where sinkInto(body, tmp.add) describes the AST where the final expression x of body is replaced by tmp.add x. We have to walk if-expressions, loops and  
"statement list expressions" to arrive at the "final expression" which is the part of the body that produces the value:

```Nim
import macros

proc sinkInto(n, fullBody, res, bracketExpr: NimNode): NimNode = 
    case n.kind
    of nnkStmtList, nnkStmtListExpr, nnkBlockStmt, nnkBlockExpr,
       nnkWhiteStmt, nnkForStmt, nnkElifBranch, nnkElse, nnkElifExpr,
       nnkOfBranch, nnkExceptBranch:
        result = copyNimTree(n)
        if n.len >= 1:
            result[^1] = sinkInto(n[^1], fullBody, res, bracketExpr)
    of nnkIfExpr, nnkIfStmt, nnkTryStmt:
        result = copyNimTree(n)
        for i in 0..< n.len:
            result[i] = sinkInto(n[i], fullBody, res, bracketExpr)
    of nnkCaseStmt:
        result = copyNimTree(n)
        for i in 1..< n.len:
        result[i] = sinkInto(n[i], fullBody, res, bracketExpr)
    else:
        if bracketExpr.len == 1:
            bracketExpr.add(newCall(bindSym"typeof", fullBody))
        result = newCall(bindSym"add", res, n)

macro collect*(init, body: untyped): untyped =
    let res = genSym(nskVar, "collectResult")
    let bracketExpr = newTree(nnkBracketExpr, init)
    let transformedBody = sinkInto(body, body, res, bracketExpr)
    let call = newTree(nnkCall, bracketExpr)
    result = newTree(nnkStmtListExpr, newVarStmt(res, call), transformedBody, res)
```

- Traverses n recursively and produces a copy of n except that the value producing subexpression x is replaced by add (res, x).  
    `fullBody` is the full body and it is used for producing `init[typeof(body)]()` which is accomplished by modifying bracketExpr
- For `nnkStmtListExpr` and the like we only follow the last child. The last  
    child can be accessed via `n[^1]`.
- For if expressions and the like we follow all possible branches. This allows for code like `if cond: a else: b` to be transformed into: `if cond: add (tmp, a) else: add(tmp, b)`.
- A case expression is just like an if expression except that we start from 1 here in order to skip the selection expression which is not the value producing expression that we are interested in.
- If the `bracketExpr` is still the init expression, add `typeof (body)` to it producing `init[typeof (body)]`
- We arrived at the value producing expression. Transform it to `add(res, value)`.
- We create a `(var res = init[typeof(body)]; transformedBody; res)`  
    construct which is called an `nnkStmtListExpr` tree. `res` is a fresh variable produced from `macros. genSym`.
- The construct `init[T]` is generated as an `nnkBracketExpr`.
- Let `sinkInto` perform the recursive traversal.
- We transform `init[T]` to `init[T]()`.
- The result of the macro is this `(var res = init[typeof(body)]; transformedBody; res)` construct.

Note that this is a simplified implementation, the standard library's collect macro implements more features and is more flexible.

## Chapter 36. strformat

Macros can be used to translate mini languages embedded inside string literals into Nim code. A good example for this is the standard library's strformat module.  
Instead of `a & " " & $b & " " & c` you can write `fmt"{a} {b} {c}"`. Inside the string literal, curly braces enclose a Nim expression. The expression is turned into a string via $. The standard library's fmt supports many features for formatting strings, integers and floats, their precision and alignment.  
However, in our reimplementation we keep things simple: We only support curly braces and use `macros.parseExpr` to do the hard part of parsing the Nim subexpressions into Nim's AST.  
It is good style to split up the tasks "parsing" and "synthesis" into different routines. Only the synthesis uses Nim's AST API. The parser/tokenizer is implemented as an iterator:

```
type TokenKind = enum
    Literal 
    NimExpr

iterator tokenize(s: string): (TokenKind, string) = 
    var i = 0
    var tok = Literal
    while i < s.len:
        let start = i
        case tok of Literal:
            while i < s.len and s[i] != '{': inc i
        of NimExpr:
            while i < s.len and s[i]!= '}': inc i
        yield (tok, s.substr(start, i-1))
        tok = if tok == Literal: NimExpr else: Literal
        inc i
```

- The tokenizer distinguishes only between two kinds of tokens.
- A `Literal` token means it should be interpreted literally. For example, the "abc" part from "{x}abc".
- A `NimExpr` needs to be parsed as a Nim expression. For example, the "x" part from "{x}abc".
- `tokenize` yields the determined tokens. A token is a pair of `(TokenKind, string)`.
- The tokenizer starts in the state `Literal`
- If the tokenizer is in the state `Literal` it needs to proceed until either the end of the string is reached or until a '{' is found.
- If the tokenizer is in the state `NimExpr` it needs to proceed until either the end of the string is reached or until a '}' is found.
- After a Literal token a `NimExpr` token must follow and vice versa.

The `fmt` macro uses this `tokenize` iterator:

```
import macros

macro fmt*(pattern: static[string]): string = 
    var args = newTree(nnkBracket)
    for (k, s) in tokenize(pattern):
        case k
        of Literal:
            if s != "":
            args.add newLit(s)
        of NimExpr:
            args.add newCall(bindSym"$", parseExpr(s))
        if args.len == 0:
            result = newLit("")
        else:
            result = nestList(bindSym"&", args)

var x = 0.9
var y = "abc"

echo fmt"{x} {y}"

```

- `fmt` takes a `static[string]` as input. This means that inside the macro body pattern really is of type string and not of `NiNode` making the data easier to access.
- `args` collects all the arguments that we pass to the `&`operator
- We use the tokenize iterator and unpack the token tuple into `k` and `s`.
- If the token is a `Literal` and not the empty string, we can append s to args. But we need to convert s to a `NimNode` first via `newLit(s)`.
- If the token is a `NimExpr` we use `macros. parseExpr` to parse it into a `NimNode`.  
    We then wrap the node and use it as an argument to a call of the `$` operator. Thus `fmt` supports any expression that can be turned into a string via `$`.
- For a call like `fmt""` it is possible that args remains empty. We map this case to the empty string literal ""
- Else we call the concatenation operator `&` with `args`. However `&` only accepts two arguments so we need to turn `&[a, b, c]` to `(a & b) & c`. This nesting of arguments is performed by `macros.nestList`.
- Produces the output: "0.9 abc".

## Chapter 37. strscans

The `tokenize` iterator, as it was implemented in the previous chapter, is straight-forward but imperative code, and the task of parsing comes up frequently in day to day programming. Ideally we want to program in a declarative way; only describing how to extract the desired data via patterns and not how to advance any required auxiliary cursors, for example.  
The standard library offers the relatively unknown module `strscans` that helps with this task.  
`strscans.scanTuple` can be used to extract data into a custom tuple type. The tuple type depends on the pattern that is tried to match. For example:

```
import std/strscans

const InputData = "1000-01-01 00:00:00"

let (ok, year, month, day, time) = scanTuple(InputData, "$i-$i-$i$s$+")

if ok:
    assert year == 1000
    assert month == 1
    assert day == 1
    assert time == "00:00:00"
```

- `InputData` contains a date a clock time that we seek to parse.
    
- The string `"$i-$i-$i$s$"` is a description of how to extract the data. Characters are matched verbatim except for substrings starting with  
    `$` .`$i` means to expect a string substring that can be parsed into an 'int'. `$5` means to skip optional whitespace. '$ matches the rest of the input.
    
- year is inferred to be of type int because it corresponds to the first `$i` pattern. For `InputData` its value is 1000.
    
- `month` is inferred to be of type `int` because it corresponds to the second `$i` pattern. For `InputData` its value is `1`.
    
- `day` is inferred to be of type `int` because it corresponds to the third `$i` pattern. For `InputData` its value is 1.
    
- `time` is inferred to be of type string because it corresponds to the `$+` pattern. For `InputData` its value is `"00:00:00"`
    
- `scanTuple` needs to produce a tuple of variable length depending on the pattern that we pass to it. The first component of the tuple is always of type `bool` and contains the information if the parse was successful.  
    In order to simplify the task that scanTuple has to do, we first create a couple of helper routines operating on a parsing `State`:
    

```
import std/parseutils

type
    State = object
        i: int
        err: bool

proc matchChar(s: string; c: var State; ch: char) =
    if not c.err:
        if c.i < s.len and s[c.i] == ch:
            inc c.i
        else:
            c.err = true

proc skipWhitespace(s: string; c: var State) =
    if not c.err:
        while c.¡ < s.len and s[c.i] in e {' ', '\t', '\n', '\r'}: inc c.i

proc matchInt(s: string; res: var int; c: var State) =
    if not c.err:
        let span = parseInt(s, res, c.i)
        if span > 0:
            inc c.i, span
        else:
            c.err = true

proc matchRest(s: string; res: var string; c: var State) = 
    if not c.err:
        res = s. substr(c.i)
```

The parsing State consists of the current parsing position i and an error flag called err. Once err is true, it is never reset to false.

- `matchChar` tries to match a single character ch.
- `skipWhitespace` skips optional whitespace.
- `matchInt` tries to match the input at position c.i against an integer. It does so with the help of the standard library’s parseutils.parseInt function.
- `matchRest` matches the rest of the input string and stores it into `res`. This design with an explicit error state allows us to emit sequential code rather than (potentially deeply) nested if statements:

```Nim
macro scanTuple*(input: string; pattern: static[string]): untyped = 
    var i = 0
    var body = newTree(nnkStmtList) 
    var tup = newTree(nnkTupleConstr)
    tup.add newLit(true)
    let stateVar = genSym(nskVar, "stateVar")
    let res = genSym(nskVar, "scanResult")
    while i < pattern.len:
        if pattern[i] == '$':
            inc i
            case pattern[i]
            of 'i':
                body.add newCall(bindSym"matchInt", input,
                    newTree(nnkBracketExpr, res, newLit(tup.len)), stateVar)
                    tup.add newlit(0)
            of 's':
                body.add newCall(bindSym"skipWhitespace", input, stateVar)
            of '+':
                body.add newCall(bindSym"matchRest", input,
                    newTree(nnkBracketExpr, res, newLit(tup.len)), stateVar)
                    tup.add newlit("')
            else:
                error "invalid pattern"
            inc i
        else:
            body. add newCall(bindSym"matchChar", input, stateVar, newLit(pattern[i]))
            inc i
        result = newTree(nnkStmtListExpr, 
            newVarStmt(res, tup),
            newVarStmt(stateVar, newTree(nnkObjConstr, bindSym"State")) ,
            body,
            newAssignment(newTree(nnkBracketExpr, res, newLit(0)),
                newCall (bindSym"not", newDotExpr(stateVar, ident"err"))),
            res)

when defined(debugScanTuple):
    echo repr result
```

- Because the exact return tuple type depends on pattern, only untyped can be used as the return type.
- body collects the list of statements that contains the calls to the helpers matchChar, skipWhitespace, matchInt, and matchRest.
- tup collects the resulting tuple value (not the tuple type!).
- We map the pattern $i to a call to matchInt.
- We map the pattern $s to a call to skipWhitespace.
- We map the pattern $ to a call to matchRest.
- Every other character in pattern is mapped to matchChar.
- The result of scanTuple is a statement list expression roughly like (var scanResult = (false, …); var stateVar = State(); body; scanResult\[0\] = not stateVar.err; scanResult).
- The when … section allows us to inspect the produced code easily. If we compile the program with the switch --define:debugScanTuple it enables the line echo repr result so at compile-time the produced AST is written to standard output:

```
var scanResult_123 = (true, 0, 0, 0,"")
var stateVar_456 = State()
matchInt(InputData, scanResult_123[1], stateVar_456)
matchChar(InputData, stateVar_456, '-')
matchInt(InputData, scanResult_123[2], stateVar_456)
matchChar(InputData, stateVar_456, '-')
matchInt(InputData, scanResult_123[3], stateVar_456)
skipWhitespace(InputData, stateVar_456)
matchRest(InputData, scanResult_123[4], stateVar_456)
scanResult_123[0] = not(stateVar_456.err)
scanResult_123
```

- `echo repr result` is an idiom worth remembering; it is important for debugging macro code and also allows for an easier development process.

## Chapter 38. HTML trees

Embedding mini languages within string literals is often not the best way to model a problem domain.  
An alternative is to leverage the full power of Nim’s syntax. A templating system for convenient HTML tree generation is a good example here.  
But before we can outline the macro’s design we need to model the HTML tree:

```Nim
type
    Tag* = enum
        text, html, head, body, table, tr, th, td
    TagWithKids = range[html..high(Tag)]
    HtmlNode* = ref object
        case tag: Tag
        of text:
            s: string
        else:
            kids: seq[HtmlNode]

proc newTextNode*(s: sink string): HtmlNode =
    HtmlNode (tag: text, s: s)

proc newTree*(tag: TagWithKids; kids: varargs[HtmlNode]): HtmlNode = 
    HtmlNode(tag: tag, kids: @kids)

proc add*(parent: HtmlNode; kid: sink HtmlNode) = parent.kids.add kid

from std/mitree import addEscaped

proc toString(n: HtmlNode; result: var string) = 
    case n. tag
    of text:
        result.addEscaped n.s
    else:
        result.add "<" & $n.tag
        if n.kids.len == 0:
            result.add " />"
        else:  result.add ">\n"
        for k in items(n.kids): toString(k, result)
        result.add "\n</" & $n.tag & ">"

proc `$`*(n: HtmlNode): string =
    result = newStringOfCap(1000)
    toString n, result
```

- Reduced list of possible HTML tags.
- A subtype of Tag that covers the tags that have kids.
- A tree of HTML modelled via a case object.
- newTextNode constructs a single text node.
- newTree constructs a node with a variable number of children.
- toString is recursive and uses a var string parameter as its buffer to write to. This var parameter is crucial for efficiency.
- For convenience a dollar operator is provided that allocates a large buffer and then calls toString to make effective use of this buffer. newTextNode, newTree, and add are good enough to produce complex HTML tables:

```Nim
proc toTable(headers: openArray[string]; data: seq[seq[int]]): HtmlNode =
    assert headers.len == data.len
    var tab = newTree(table)
    for i in 0..<data.len:
        var row = newTree(tr, newTree(th, newTextNode(headers[i])))
        for col in data[i]:
            row.add newTree(td, newTextNode($col))
        tab.add row
    result = newTree(html, newTree(body, tab))

```

- toTable produces a 2 dimensional HTML table from headers and data.
- We require that every column has a corresponding header.
- We must not forget to append the temporary row to tab.
- The table is wrapped inside….

This style of programming is low level and error prone; it is easy to forget to append row to tab, for example. Instead we would like to write the following:

```Nim
proc toTable(headers: openArray[string]; data: seq[seq[int]]): HtmlNode =
    assert headers.len == data.len
    result = buildHtml:
        body:
            table:
                for i in 0..<data.len:
                    tr:
                        th:
                            text headers[i]
                        for col in data[i]:
                            td:
                                text $col
```

The domain specific language should compose with ordinary Nim code, we want to be able to use ordinary if and for statements inside the HTML templating system.

The required buildHtml macro needs to walk the passed AST recursively and introduce temporary variables for each if and for statement.  
Every enum value of TagWithKids is translated to a newTree call, a call to text is translated to newTextNode:

```Nim
import macros

proc whichTag(n: NimNode): Tag =
    for e in low(TagWithKids)..high(TagWithKids):
        if n. eqIdent($e): return e
    return text

proc traverse(n, dest: NimNode): NimNode =
    if n.kind in nnkCallKinds:
        if n[0].eqIdent ("text"):
            expectLen n, 2
            result = newCall(bindSym"newTextNode", n[1])
            if dest != nil:
                result = newCall (bindSym"add", dest, result)
        else:
            let tag = whichTag(n[0])
            if tag == text:
                result = copyNimNode(n)
                result.add n[0]
                for i in 1..< n.len:
                    result.add traverse(n[i], nil)
            else:
                let tmpTree = genSym(nskVar, "tmpTree")
                result = newTree(nnkStmtList, newVarStmt (tmpTree, newCall(bindSym"newTree", n[0])))
                for i in 1..<n.len:
                    result.add traverse(n[i], tmpTree)
                if dest != nil:
                    result.add newCall(bindSym"add", dest, tmpTree)
    else:
        result = copyNimNode(n)
        for child in n:
          result.add traverse(child, dest)

macro buildHtml(n: untyped): untyped =
    let tmpTree = genSym(nskVar, "tmpTree")
    var call = newCall(bindSym"newTree", bindSym"html")
    result = newTree(nnkStmtListExpr, newVarStmt(tmpTree, call))
    result.add traverse(n, tmpTree)
    result.add tmpTree

```

- whichTag returns the tag that the call operation corresponds to.
- body: is mapped to Tag.body etc.
- It returns text if it is not any tag.
- traverse does the bulk of the work. It traverses n and produces a modified copy of the AST. dest is the potential destination of where to attach the HtmlNode to.
- If the node is any kind of “call expression” we examine if it is a call to the text operation.
- If so, it translates text x to newTextNode(x). ⑦ If the call is not a call to a tag simply traverse n recursively.
- If the call is a tag transform it into (var tmpTree = newTree(tag); translatedBody; dest.add tmpTree).
- For any node that is not a call expression traverse n recursively.
- buildHtml calls the traverse auxiliary proc.
- buildHtml transforms n into (var tmpTree = newTree(html); traverse(n); tmpTree) which is an nnkStmtListExpr that produces a value of type HtmlNode so that it can be bound to a variable.

## Chapter 39. Advice

The examples we have seen so far do not only show how macros can be implemented; they are also supposed to show good design of domain specific languages (DSL). In general a library that uses macros to good effect focuses on:

1.  Composability. It should be possible to combine different DSLs into a coherent program.
2.  Understandability. Hide the right amount of details but do not hide important aspects of your programs. For example, injecting temporary variables is almost always beneficial and arguably a large part of what drives the distinction between low level and high level programming. On the other hand, hiding control flow can make your programs more brittle. Beware of designs that focus on “single character” DSLs such as regular expressions and what strformat offers; these are inherently not scalable as single characters are hard to remember and it is not obvious how to arrive at a design where optional whitespace can be inserted for better readability.
3.  Documentation. Macros should be documented well. The performed transformations should be outlined and the design ideas behind the DSL should be documented.

## Macros extra

Macros and meta-programming  
Introduction

In computer science, a macro (short for "macro instruction") is a rule or pattern, that specifies how a certain input should be mapped to a replacement output. Meta-programming is a programming technique, in which computer programs have the ability to treat other programs as their data. It means, that a program can read, generate, analyze, or transform other programs, and even modify itself while running.

Legacy programming languages, like C or assembly languages, support already some form of macros, which typically work directly on the textual representation of the source code.

A common use of textual macros in assembly languages was to group sequences of instructions, like reading data from a file or from the keyboard, to make those operations easily accessible. The C programming language uses the #define preprocessor directive to introduce textual macros. Macros in C can be either single-line or multi-line text substitutions, which are processed by a pre-processor program, before the actual compiling process. Some examples of common C macros are

#define PI 3.1415  
#define sqr(x) (x)\*(x)

The basic C macro syntax is, that the first continues character sequence after the #define directive is replaced by the C preprocessor with the rest of that line. The #define directive has some basic parameter support, which was used for the sqr() macro above. C macros have the purpose to support named constants and to allow simple parameterized expressions like the sqr() from above, avoiding the need to create actual functions. The C pre-processor would substitute each occurrence of the symbol PI in the C source file with the float literal 3.1415, and the term sqr(1+2) with (1+2)\*(1+2).

Self-modifying assembly code, which was used in a few games on home computers in the 1980s, computer viruses and related malicious code with the ability to modify themselves at runtime, and JIT-Compilers (Just-In-Time) are a very special variant of metaprogramming. Nim allows the use of macros and metaprogramming only at compile-time, so unpredictable and possibly dangerous code modifications at program runtime can not occur. But as Nim’s macros and metaprogramming capacities are very powerful, they can make it more difficult to understand and reason about the source code. So metaprogramming should be used with some care, and in some very sensitive areas, metaprogramming may be restricted.

A Nim macro is a code block, that is executed at compile-time, and transforms a Nim syntax tree into a different tree. The transformation is supported by Nim’s type introspection abilities, e.g. to examine the type or properties of objects and other entities. This can be used to add custom language features and implement domain-specific languages (DSL). While macros enable advanced compile-time code transformations, they cannot change Nim’s syntax.

The macro keyword is used similarly to proc, func, and template to define a parameterized code block, which is executed at compile-time and consists of ordinary Nim code, and meta-programming instructions. The meta-programming instructions are imported from the macros module and are used to construct an Abstract Syntax Tree (AST) of the Nim language. This AST is created by the macro body at compile time and is returned by the macro as an untyped data type. The parameter list of macros accepts ordinary (static) Nim data types, and additionally the data types typed and untyped, which we already used for templates. We will explain the differences between the various possible data types for macro parameters later in more detail after we have given a first simple macro example. Note, that Nim macros are hygienic by default, that is, symbols defined inside the macro body are local and do not pollute the namespace of the environment. Since macros are executed at compile-time, their use may increase the compile time, but it does not impact the performance of the final executable. In fact, clever use of macros can sometimes improve the performance of the final program.

Macros are by far the most difficult part of the Nim programming language. While in languages like Lisp macros integrate very well into the language, for Nim the meta-programming with macros is very different from the use of the language itself. Nim’s macros are very powerful — the current Nim async implementation is based on Nim macros, and some advanced libraries for threading, parallel processing, or data serialization using JSON or YAML file formats, make heavy use of Nim macros. And many modules of the Nim standard library provide some macros, which extend the power of the Nim core language. The well-known with macro of the eponymous module is just one example of the usefulness of Nim’s macros. And some small, but important, parts of the high-level GTK bindings are created with macros, for example, the code to connect GTK callback functions to GTK signals. However, this does not mean that every Nim user must use macros. For a few use cases, we really need macros; for other use cases, macros may make our code shorter, and possibly even cleaner. However, the use of macros can make the code harder to understand for others, especially when we use exotic or complicated macros of our own. Furthermore, learning advanced Nim macro programming is not that easy. Nim macros have some similarities to the programming language C++: When we follow the explanations in a C++ textbook, then the C++ language seems to be not extremely difficult and even seems to follow a more or less logical design. But then, when we later try to write some actual code in C++, we notice that actually using the languages is hard, as long as we do have not a lot of practice. For Nim macros, it is similar — when we follow a talk of an experienced Nim programmer about macro programming, or when we read the code of an existing macro, written by the Nim core devs, then everything seems to not be that hard. But when we try to create macros of our own for the first time, it can be frustrating. Strange error messages, or even worse, no idea at all how we can solve a concrete task. So maybe the best start with macros is to read the code of existing macros, study the macros module, to see what is available, and maybe follow some of the various tutorials listed at the end of this section. Finally, you might need to ask for help in the Nim forum, on IRC, or through other Nim help channels.

To verify that macros are really executed at compile time, we will start with a tiny macro, that contains only an echo statement in its body:

```Nim
import std/macros

macro m1(s: string): untyped =
  echo s

proc main =
  echo "calling macro m1"
  m1("Macro argument")

main()
```

When we compile the above code, the compiler prints the message "Macro argument" as it processes the macro body. When we run the program, we get only the output "calling macro m1" from the main() proc, as the macro m1() does only return an empty AST. The careful reader may wonder why the echo() statement in the macro body above works at all, since the parameter of macro m1() is specified as an ordinary string, not as a static\[string\]. So the type of s in the macro body should be a NimNode. Well, perhaps an echo() overload exists, that can work with NimNodes, or maybe, as we pass a string constant to macro m1(), in this concrete case s is indeed an ordinary string in the macro body. Possibly we should have used s: static\[string\] as the parameter type, which would give us the exact same results.

We said that macros always have to return an untyped result. This is true, but since untyped is the only possible result type, that type can currently be omitted. So you may see in the code of the Nim standard library a few macros, which seem to return nothing. For our own macros, we really should always use untyped as the result. And sometimes you may even see macros, where for parameters no data type is specified at all. In that case, the data type has the default untyped type.

As macros are executed at compile time, we cannot really pass runtime variables to them. When we try, we would expect a compiler error:

```Nim
import std/macros

macro m1(s: string): untyped =
  echo s

proc main =
  var str = "non static string"
  m1(str)

main()
```

But with the current compiler version 1.5.1, that code compiles and prints the message "str", which is a bit surprising. To fix this, we can change the parameter type to static\[string\], which guarantees that we can indeed pass only compile-time constants.

Now, let us create macros, which actually create an AST, which is returned by the macro and executed when we run our program. For creating an AST in the macro body, we have various options: we can use the parseStmt() function or the "quote do:" notation, to generate the AST from regular program code in text form, or we can create the syntax tree directly with expressions provided by the macros module, e.g. by calls like newTree() or newLit() and such. The latter gives us the best control over the AST generation process, but is not easy for beginners. The good news is that Nim now provides a set of helper functions like dumpTree() or dumpAstGen(), which show us the AST representation of a Nim source code block as well as the commands we can use to create that AST. This makes it much easier for beginners to learn the basic instructions necessary to create valid syntax trees and to create useful macros.

We will start with the simple parseStmt() function, which generates the syntax tree from the source code text string, which we pass as an argument. This seems to be very restricted, and maybe even useless, as we can write the source code just as ordinary program text outside the macro body. That is true, but we can construct the text string argument that we pass to the parseStmt() function with regular Nim code at compile time. That is similar to having one program that generates a new source code string, saves that string to disk, and finally compiles and runs the created program. Let us check with a fully static string, that parseStmt() actually works:

```Nim
import std/macros

macro m1(s: static[string]): untyped =
  result = parseStmt(s)

proc main =

  const str = "echo \"We like Nim\""
  m1(str)

main()
```

When we compile and run the above program, we get the output "We like Nim". The macro m1() is called at compile-time with the static parameter str, and returns an AST which represents the passed program code fragment. That AST is inserted into our program at the location of the macro call, and when we run our program, the compiled AST is executed and produces the output.

Of course, executing a fully static string this way is useless, as we could have used regular program code instead. Now, let us investigate how we can construct some program code at compile time. Let us assume that we have an object with multiple fields, and we want to print the field contents. A sequence of echo() statements would do that for us, or we may use only one echo() statement when we separate the field arguments each by "\\n". The with module may further simplify our task. But as we have to print multiple fields, not an array or a seq, we can not directly iterate over the values to process them. Let us see how a simple text string based macro can solve the task:

```Nim
import std/macros

type
  O = object
    x, y, z: float

macro m1(objName: static[string]; fields: varargs[untyped]): untyped =
  var s: string
  for x in fields:
    s.add("echo " & objName & "." & x.repr & "\n")
  echo s # verify the constructed string
  result = parseStmt(s)

proc main =
  var o = O(x: 1.0, y: 2.0, z: 3.0)
  m1("o", x, y, z)

main()
```

In this example, we pass the name of our object instance as a static string to the macro, while we pass the fields not as a string, but as a list of untyped values. The passed static string is indeed an ordinary Nim string inside the macro, we can apply string operations on it. But the field names passed as untyped parameters appear as so-called NimNodes inside the macro. We can use the repr() function to convert the NimNodes to ordinary strings so that we can use string operations on them. We iterate with a for loop over all the passed field names and generate echo() statements from the object instance name and the field names, each separated by a newline character. Then, all the statements are collected in a multi-line string s and are finally converted to the final AST by the parseStmt() function. In the macro body, we use the echo() statement to verify the content of that string. As the macro is executed during compile-time, we get this output when we compile our program:

```
echo o.x
echo o.y
echo o.z

# And when we run it, we get:
# 1.0
# 2.0
# 3.0
```

Well, not a really great result for this concrete use case: We have replaced three echo() commands with a five-lines macro. But at least, you’ve got a sense of what macros can do for us.

The parseStmt() function is not actually used that often, as string construction is inconvenient, and avoiding issues like namespace collisions can be difficult. In the following sections, we will introduce the quote do: construct and the genast() macro, which allows easier AST generation from textual code blocks. And later, we will learn how we can create macros directly by manually AST manipulation.

### Types of macro parameters

As Nim is a statically typed programming language, all variables and procedure parameters have a well-defined data type. There is some form of exception to this rule for OR-types, object variants, and object references: OR-types are indeed no real exception. Whenever we use an OR-type as the type of a proc parameter, multiple instances of the proc, with different parameter types, are created when necessary. That is very similar to generic procedures. Object variants and object references indeed form some kind of exception, as instances of these types can have different runtime types that we can query with the case or of keyword at runtime. Note that object variants and references (the managed pointers themselves, not the actual data allocated on the heap) always occupy the same amount of RAM, independent of the actual runtime type. (That is why we can store object variants with different content or references to objects of different runtime types using inheritance in arrays and sequences.)

For the C sqr() macro from the beginning of this section, there is no real restriction for the argument data types. The sqr() C macro would work for all numeric types that support the multiply operation, from char data type over various int types to float, double and long double. This behavior is not really surprising, as C macros are only a text substitution. Actually, the C pre-processor would even accept all data types and even undefined symbols for its substitution process. But then the C compiler would complain later.

Nim macros and Nim templates do also some form of code substitution, so it is not really surprising that they accept not only well-defined data types, but also the relaxed types typed and untyped.

As parameters for Nim’s macros, we can use ordinary Nim data types like int or string, compile-time constants denoted with the static keyword like static\[int\], or the typed and untyped data types. When we call macros, then the data types of the parameters are used in the same way for overload resolution as it is done for procedures and templates. For example, if a macro defined as foo(arg: int) is called as foo(x), then x has to be of a type compatible with int.

What may be surprising at first is that inside the macro body, all parameter types do not have the data type of the actual argument we have passed to the macro. Instead, they have the special macro data type NimNode, which is defined in the macros module. The predefined result variable of the macro has the type NimNode as well. The only exceptions are macro parameters which are explicitly marked with the static keyword to be compile-time constants like static\[string\], these parameters are not NimNodes in the macro body but have their ordinary data types in the macro body. Variables, that we define inside the macro body, have exactly the type that we give to them, e.g. when we define a variable as s: string, then this is an ordinary Nim string variable, for which we can use the common string operations. But of course, we have always to remember that macros are executed at compile time, and so the operations on variables defined in the macro body occur at compile time, which may restrict a few operations. Currently, macros are evaluated at compile-time by the Nim compiler in the NimVM (Virtual Machine), and so share all the limitations of the NimVM: Macros have to be implemented in pure Nim code, and can currently not call C functions, except those that are built into the compiler.

In the Nim macros tutorial, the static, typed, and untyped macro parameters are described in some detail. We will follow that description, as it is more detailed than the current description in the Nim language manual. As these descriptions are very abstract, we will give some simple examples later.

### Static macro parameters

Static arguments are a way to pass compile-time constants not as a NimNode, but as an ordinary value to a macro. These values can then be used in the macro body like ordinary Nim variables. For example, when we have a macro defined as m1(num: static\[int\]), then we can pass it constant values compatible with the int data type, and in the macro body, we can use that parameter as an ordinary integer variable.

### Untyped macro parameters

Untyped macro arguments are passed to the macro before they are semantically checked. This means that the syntax tree, that is passed down to the macro, does not need to make sense for the Nim compiler yet, the only limitation is, that it needs to be parsable. Usually, the macro does not check the argument either but uses it in the transformation’s result somehow. The result of a macro expansion is always checked by the compiler, so apart from weird error messages, nothing bad can happen. The downside of an untyped argument is that it does not play well with Nim’s overloading resolution. The upside for untyped arguments is, that the syntax tree is quite predictable and less complex compared to its typed counterpart.\[79\]

### Typed macro parameters

For typed arguments, the semantics checker runs on the argument and does transformations on it before it is passed to the macro. Here identifier nodes are resolved as symbols, implicit type conversions are visible in the tree as calls, templates are expanded, and probably most importantly, nodes have type information. Typed arguments can have the type typed in the arguments list. But all other types, such as int, float, or MyObjectType, are typed arguments as well, and they are passed to the macro as a syntax tree.\[80\]

### Code blocks as arguments

In Nim, it is possible to pass the last argument of a procedure, template, or macro call as an indented code block, following a colon, instead of an ordinary argument enclosed in the parentheses following the function name. For example, instead of echo("1 + 2 = ", 1 + 2), we can also write

```
echo("1 + 2 = "):
  1 + 2
```

For procedures, this notation makes not much sense, but for macros, this notation can be useful, as syntax trees of arbitrary complexity can be passed as arguments.

Now, let us investigate in more detail, which data types a macro accepts. This way we hopefully get more comfortable with all these strange macro stuff. For our test, we create a few tiny macros, each with only one parameter, doing nothing more than printing a short message when we compile our program:

```Nim
import std/macros

macro m1(x: static[int]): untyped =
  echo "executing macro body"

m1(3)
```

This code should compile fine, and print the message "executing macro body" during the compile process, and indeed, it does. The next example is not that easy:

```Nim
import std/macros

macro m1(x: int): untyped =
  echo "executing macro body"
  echo x
  echo x.repr

var y: int
y = 7
m1(y)
```

This compiles, but as the assignment y = 7 is executed at program runtime, while the macro body is already executed at compile-time, we should not expect that the echo() statement in the macro body prints the value 7. Instead, we get just y for both echo() calls. Now, let us investigate what happens when we use typed instead of int for the macro parameter:

```Nim
import std/macros

macro m1(x: typed): untyped =
  echo "executing macro body"
  echo x
  echo x.repr

var y: int
y = 7
m1(y)
```

We get the same result again, both echo() statements print y. The advantage of the use of typed here is, that we can change the data type of y from int to float, and our program still compiles. So the typed parameter type just enforces that the parameter has a well-defined type, but it does not restrict the actual data type to a special value. The previous macro, with int parameter type, would obviously not accept a float value.

Now, let us see what happens when we pass an undefined symbol to this macro with typed parameter:

```Nim
import std/macros

macro m1(x: typed): untyped =
  echo "executing macro body"
  echo x
  echo x.repr

m1(y)
```

This will not compile, as the macro expects a parameter with a well-defined type. But we can make it compile by replacing typed with untyped:

```
import std/macros

macro m1(x: untyped): untyped =
  echo "executing macro body"
  echo x
  echo x.repr

m1(y)
```

So untyped macro parameters are not only the most flexible but also the most commonly used. However, in some situations, it is necessary to use typed parameters, e.g., when we need to know the parameter type in the macro body.

### Quote and the quote do: construct

In the section before, we learned about the parseStmt() function, which is used in a macro body to compile Nim code represented as a multi-line string to an abstract syntax tree representation. Macros use as a return type the "untyped" data type, which is compatible with the NimNode type returned by the parseStmt() function.

The quote() function and the quote do: construct have some similarity with the parseStmt() function: They accept an expression or a block of Nim code as an argument and compiles that Nim code to an abstract syntax tree representation. The advantage of quote() is, that the passed Nim code can contain NimNode expressions from the surrounding scope. The NimNode expressions have to be quoted using backticks.

As a first very simple example for the use of the quote do: construct, we will present a way to print some debugging output.

Assume we have a larger Nim program, which works not in the way that we expected, so we would add some echo() statements like

```
var currentSpeed: float = calcSpeed(t)
echo "currentSpeed: ", currentSpeed
```

Instead of the echo() statement, we would like to just write show(currentSpeed) to get exactly the same output. For that, we need access not only to the actual value of a variable, but also to its name. Nim macros can give us this information, and by using the quote do: construct, it is very easy to create our desired showMe() macro:

```Nim
import std/macros

macro show(x: untyped): untyped =
  let n = x.toStrLit
  result = quote do:
    echo `n`,": ", `x`

import std/math
var a = 7.0
var b = 9.0
show(a * sqrt(b))
```

When we compile and run that code, we get:

a \* sqrt(b): 21.0

In the macro body, we use the proc toStrLit() from the macros module, which is described with this comment: "Converts the AST n to the concrete Nim code and wraps that in a string literal node" So our local variable n in the macro body is a NimNode, that now contains the string representation of the macro argument x. We use the NimNode n enclosed with backticks in the quote do: construct. It seems, that writing this macro was indeed not that difficult, but actually, it was only that easy because we have basically copied the dump() macro from the sugar module of Nim’s standard library.

Let us investigate our show() macro in some more detail, to learn more about the inner working of Nim macros. First, recall that macros always have a return value of data type untyped, which is actually a NimNode. The quote do: construct gives us a result which we can use as the return value of our macro. Sometimes, we may see macros with no result type at all, which is currently identical to the untyped result type. As the macro body is executed at compile-time, the quote do: construct is executed at compile-time as well, that is that the code block which we pass to the quote do: construct is processed at compile-time and the quoted NimNodes in the block are interpolated at compile-time. For our program from above, the actual echo() statement in the block is then finally executed at program runtime. To prove how this final echo() statement looks, we may add as the last line of our macro the statement "echo result.repr" and we would then get the string "echo "a \* sqrt(b)", ": ", a \* sqrt(b)", when we compile our program again.

You may wonder why the construct "quote do:" is used instead of only "quote:". The "do notation" is an overloaded feature of the Nim language and offers two things:\[81\]

- A different way to pass anonymous procs/closures to a procedure
- A way to pass two code blocks to a template.

We will not try to explain the magic of "do" here in more detail, because there have been suggestions to modify its use and meaning, and because modern Nim provides the new genAst() macro, which can replace "quote do" and is preferred by many people now. We will present that macro in the next section. When you are really interested in the details of the "do" notation, you may read these two forum posts:

- https://forum.nim-lang.org/t/8259#53154
- https://forum.nim-lang.org/t/8279#53301

### The genast() macro as a replacement for quote do:

The genasts module provides the genAstOpt() macro and the genAst() template as a drop-in replacement for the "quote do:" construct. Like quote do:, genAst() accepts an expression or a code block and returns the AST that represents it. Within the quoted AST, we are able to interpolate NimNode expressions from the surrounding scope. While for quote do: quoting is done using backticks (or other user-defined delimiters), we pass to genAst() a list of the variables to capture, and can then use these variables in the body of genAst() without explicit quoting. Using genAst(), our show() macro from above becomes:

```Nim
import std/[macros, genasts]

macro show(x: untyped): untyped =
  let n = x.toStrLit
  genAst(x, n):
    echo n, ": ", x

import std/math
var a = 7.0
var b = 9.0
show(a * sqrt(b))
```

GenAst() captures (interpolates) parameters of the surrounding macro and local macro variables when we specify them as parameters to genAst(). A macro local procedure is automatically captured and does not have to be included in the capture list explicitly. This behavior can be modified, when instead of the plain genAst(), the genAstOpt() macro is used, which has a set of options as a first parameter. You can find some more details about the genasts module and two larger examples for its use in the API documentation of that module.

References:

- https://nim-lang.github.io/Nim/genasts.html
- https://github.com/nim-lang/Nim/pull/17426

### Building the AST manually

In the three sections before we used the functions parseStmt(), quote() and genAst() to build the AST from a textual representation of Nim code. That can be convenient, but is not very flexible. In this section, we will learn how we can build a valid AST from scratch by calling functions of the macros module. That is not that easy, but this way we have the full power of the Nim meta-programming available.

Luckily, the macros module provides some macros like dumpTree() and dumpAstGen(), which can help us get started. We will create again a macro similar to the show() macro, that we created before with the quote do: construct, but now with elementary instructions from the macros module. This may look a bit boring, but this plain example is already complicated enough for the beginning, and it shows us the basics to construct much more powerful macros later.

The core code of our debug() macro would look in textual representation like:

```
var a, b:int
echo "a + b", ": ", a + b
```

That is for debugging we would like to print an expression first in its string representation, and separated by a colon, the evaluated expression. The dumpTree() macro can show us how the Nim syntax tree for such a print debug statement should look:

```Nim
import std/macros

var a, b: int

dumptree:
  echo "a + b", ": ", a + b
```

When we compile this code, we get as output:

```
StmtList
  Command
    Ident "echo"
    StrLit "a + b"
    StrLit ": "
    Infix
      Ident "+"
      Ident "a"
      Ident "b"
```

The Nim syntax tree for the previously mentioned echo() statement is a statement list consisting of an echo() command with two string literal arguments and a last argument which is built with the infix + operator and the two arguments a and b. We can see how the AST, which we would have to construct, should look, but we still do not know how we could construct such an AST in detail. Well, the macros module would contain the functions that we need for that, but it is not easy to find the right functions there. The dumpAstGen() macro can list us exactly the needed functions:

```
mport std/macros

var a, b: int

dumpAstGen:
  echo "a + b", ": ", a + b
```

```nim
Compiling that code gives us:

 nnkStmtList.newTree(
  nnkCommand.newTree(
    newIdentNode("echo"),
    newLit("a + b"),
    newLit(": "),
    nnkInfix.newTree(
      newIdentNode("+"),
      newIdentNode("a"),
      newIdentNode("b")
    )
  )
)

```

This is a nested construct. The most outer instruction constructs a new tree of Nim Nodes with the node type statement list. The next construct creates a tree with node kind command, which again contains the ident node with name echo, which again contains two literals and the infix + operator.

We can use the output of the dumpAstGen() macro directly to create a working Nim program:

```Nim
import std/macros

var a, b: int

#dumpAstGen:
#  echo "a + b", ": ", a + b

macro m(): untyped =
  nnkStmtList.newTree(
    nnkCommand.newTree(
      newIdentNode("echo"),
      newLit("a + b"),
      newLit(": "),
      nnkInfix.newTree(
        newIdentNode("+"),
        newIdentNode("a"),
        newIdentNode("b")
      )
    )
  )
m()
```

When we compile and run that code, we get the output:  
`a + b: 0`

So the AST from above is fully equivalent to the one-line echo() statement. But now we would have to investigate how we can pass an actual expression to our macro, and how we can use that passed argument in the macro body — first, print its textual form, and then the evaluated value, separated by a colon. There is one more problem: the previously mentioned nested macro body is not really useful for our final dump() macro, as we would like to be able to construct the NimNode that is returned by the dump() macro step by step: Add the echo() command, then the passed expression in string form, and finally the evaluated expression. So let us first rewrite the above macro in a form where the AST is constructed step by step. That may look difficult, but when we know that we can call the newTree() function with only one node kind parameter to create an empty tree of that kind and that we can later use the overloaded add() proc to add new nodes to that tree, then it is easy to guess how we can construct the macro body:

```Nim
import std/macros

var a, b: int

#dumpAstGen:
#  echo "a + b", ": ", a + b

macro m(): untyped =
  nnkStmtList.newTree(
    nnkCommand.newTree(
      newIdentNode("echo"),
      newLit("a + b"),
      newLit(": "),
      nnkInfix.newTree(
        newIdentNode("+"),
        newIdentNode("a"),
        newIdentNode("b")
      )
    )
  )

macro m2(): untyped =
  result = nnkStmtList.newTree()
  let c = nnkCommand.newTree()
  let i = nnkInfix.newTree()
  i.add(newIdentNode("+"))
  i.add(newIdentNode("a"))
  i.add(newIdentNode("b"))
  c.add(newIdentNode("echo"))
  c.add(newLit("a + b"))
  c.add(newLit(": "))
  c.add(i)
  result.add(c)

m2()
```

First, we create the three empty tree structures of node kinds statement list, command, and infix operator. Then we use the overloaded add() proc to populate the trees, using procs like newIdentNode() or newLit() to create the nodes of matching types as before. When we run our program with the modified macro version m2(), we get again the same output:  
`a + b: 0`

The next step to create our actual dump() macro is again easy — we pass the expression to dump() as an untyped parameter to the macro, convert it to a NimNode of string type, and use that instead of the previously mentioned newLit("a + b"). In our second macro, where we used the quote do: construct, we applied already toStrLit() on an untyped macro parameter, so we should be able to reuse that to get the string NimNode. Instead, we would have to apply the stringify operator additionally on that value. But a simpler way is to just apply repr() on the untyped macro argument to get a NimNode of string type. And finally, to get the value of the evaluated expression in our dump() macro, we add() the untyped macro parameter directly in the command three — that value is evaluated when we run the macro generated code.

```Nim
import std/macros

var a, b: int

macro m2(x: untyped): untyped =
  var s = x.toStrLit
  result = nnkStmtList.newTree()
  let c = nnkCommand.newTree()
  c.add(newIdentNode("echo"))
  c.add(newLit(x.repr))
  #c.add(newLit($s))
  c.add(newLit(": "))
  c.add(x)
  result.add(c)

m2(a + b)


```

Again, we get the desired output:  
`a + b: 0`

So, our dump() macro, still referred to as m2(), is complete and can be used to debug arbitrary expressions. Note, that this macro works for arbitrary expressions, not only for numerical ones. We may use it like

```
m2(a + b)
let what = "macros"
m2("Nim " & what & " are not that easy")
```

and get the output

```
a + b: 0
"Nim " & what & " are not that easy": Nim macros are not that easy
```

Now, let’s extend our debug() macro so that it can accept multiple arguments. The needed modifications are minimal; we simply pass an argument of type varargs\[untyped\] to the debug macro instead of a single untyped argument, and iterate in the macro body with a for loop over the varargs argument:

```Nim
import std/macros

macro m2(args: varargs[untyped]): untyped =
  result = nnkStmtList.newTree()
  for x in args:
    let c = nnkCommand.newTree()
    c.add(newIdentNode("echo"))
    c.add(newLit(x.repr))
    c.add(newLit(": "))
    c.add(x)
    result.add(c)

var
  a = 2
  b = 3
m2(a + b, a * b)

```

When we compile and run that code, we get:

```
a + b: 5
a * b: 6
```

### The assert macro

As one more simple example, we will show how we can create our own assert() macro. The assert() has only one argument, which is an expression with a boolean result. If the expression evaluates to true at program runtime, then the assert() macro should do nothing. But when the expression evaluates to false, then this indicates a serious error and the macro shall print the expression which evaluated to false and then terminate the program execution. This is basically what the assert() macro in the Nim standard library already does, and the official Nim macros tutorial contains such an assert() macro as well.

Arguments for our assert() macro may look like "x == 1 + 2", containing one infix operator, and one left-hand, and one right-hand operand. We will show how we can use subscript \[\] operators on the NimNode argument to access each operand.

As a first step, we use the treeRepr() function from the macros module, to show us the Nim tree structure of a boolean expression with an infix operator:

```Nim
import std/macros

macro myAssert(arg: untyped): untyped =
  echo arg.treeRepr

let a = 1
let b = 2

myAssert(a != b)
```

When we compile that program, the output of the treeRepr() function shows us that we have passed an infix operator with two operands at index positions 1 and 2 as an argument.

```
Infix
  Ident "!="
  Ident "a"
  Ident "b"
```

Now, let us create an assert() macro, which accepts such a boolean expression with an infix operator and two operands:

```Nim
import std/macros

macro myAssert(arg: untyped): untyped =
  arg.expectKind(nnkInfix) # NimNodeKind enum value
  arg.expectLen(3)
  let op = newLit(" " & arg[0].repr & " ") # operator as string literal NimNode
  let lhs = arg[1] # left hand side as NimNode
  let rhs = arg[2] # right hand side as NimNode
  result = quote do:
    if not `arg`:
      raise newException(AssertionDefect,$`lhs` & `op` & $`rhs`)

let a = 1
let b = 2

myAssert(a != b)
myAssert(a == b)
```

The first two function calls, expectKind() and expectLen(), verify that the macro argument is indeed an infix operator with two operands, that is, the total length of the argument is 3. The symbol nnkInfix is an enum value of the NimNodeKind data type defined in the macros module — that module follows the convention to prepend enum values with a prefix, which is nnk for NimNodeType in this case. In the macro body, we use the subscript operator \[0\] to access the operator and then apply repr() on it to get its string representation. Further, we use the subscript operators \[1\] and \[2\] to extract the two operands from the macro argument and store the result each in a NimNode lhs and rhs. Finally, we create the quote do: construct with its indented multi-line string argument and the interpolated NimNode values enclosed in backticks. The block after the quote do: construct checks, if the passed arg macro argument evaluates to false at runtime, and raises an exception, in that case, displaying the reconstructed argument.

We have to admit that this macro is not really useful in real life, as it is restricted to simple boolean expressions with a single infix operator. And what it does in its body doesn’t make much sense: The original macro argument is split into three parts, the infix operator and the two operands, which are then just joined again to show the exception message. But at least we have learned how we can access the various parts of a macro argument by using subscript operators, how we can use the treeRepr() function from the macros module to inspect a macros argument, and how we can ensure that the macro argument has the right shape for our actual macro by applying functions like expectKind() and expectLen() early in the macro body.

### Pragma macros

All macros and templates can also be used as pragmas. They can be attached to routines (procedures, iterators, etc.), type names, or type expressions. In this section, we will show a small example, of how a proc pragma can be used to print the proc name whenever a procedure annotated with that pragma is called:

```Nim
import std/macros

dumpAstGen: # let us see how the NimNode for an echo statement has to look
  proc test(i: int) =
    var thisProcName = "test"
    echo thisProcname
    echo 2 * i

macro pm(arg: untyped): untyped = # a pragma macro
  expectKind(arg, nnkProcDef) # assert that macro is applied on a proc
  let node = nnkCommand.newTree(newIdentNode("echo"), newLit($name(arg)))
  insert(body(arg), 0, node)
  result = arg

proc myProc(i: int) {.pm.} =
  echo 2 * i

proc main =
  myProc(7)

main()
```

We start with the dumpAstGen() macro applied to a test() proc, which contains an echo() statement. So when we compile that code, we get an initial idea of how a NimNode, which should print the proc name, should look. To use pragma macros, we annotate the proc with the macro name enclosed in the pragma symbols {..}. The annotated procedure is then passed to the pragma with that name in the form of a syntax tree. Our goal is to add a NimNode to this tree, which prints the procedure name of the passed AST. To do that, we have to know two important points: For the proc that is passed as an untyped data type to our macro, we can use the function body() to get the AST representation of the body of the passed proc, and we can use name() to get the name of that proc. The functions body() and name() are provided by the macros module of Nim’s standard library. In our macro pm(), we first verify that the passed argument is really of node kind ProcDef. Then we create a new NimNode, which calls the echo() function with the procedure name as a parameter. And we insert that node at position 0 into the body of the passed proc. Finally, we return the modified AST.

When we run our program, we get this output in the terminal window:

```
$ ./t
myProc
14
```

### Pragma macros for iterators

Let’s assume we have an object type with some fields, all of which are sequences with the same base type, and we need an iterator to iterate over all the container elements. Indeed, this may happen when the different seqs contain subclasses of the same parent class, as in

```Nim
type
  Group = ref object of Element
    lines: seq[Line]
    circs: seq[Circ]
    texts: seq[Text]
    rects: seq[Rect]
    pads: seq[Pad]
    holes: seq[Hole]
    paths: seq[Path]
    pins: seq[Pin]
    traces: seq[Trace]

iterator items(g: Group): Element =
  for el in g.lines:
    yield el
  for el in g.rects:
    yield el
  for el in g.circs:
    yield el
```

Perhaps we do not want to write all the for loops in the iterator body manually. One solution is to create a pragma macro, which creates the for loops in the iterator body for us:

```Nim
import std/macros

type
  O = object
    a, b, c: seq[int]

macro addItFields(o: untyped): untyped =
  const fields = ["a", "b", "c"]
  expectKind(o, nnkIteratorDef)
  # echo o.treeRepr
  # echo o.params.treeRepr
  let objName = o.params[1][0]
  for f in fields:
    let node =
      nnkStmtList.newTree(
        nnkForStmt.newTree(
          newIdentNode("el"),
          nnkDotExpr.newTree(
            #newIdentNode("o"),
            newIdentNode($objName),
            # newIdentNode("b")
            newIdentNode(f)
          ),
          nnkStmtList.newTree(
            nnkYieldStmt.newTree(
              newIdentNode("el")
            )
          )
        )
      )
    insert(body(o), body(o).len, node)
  result = o
  #echo result.repr

iterator items(o: O): int {.addItFields.} =
  discard

#dumpAstGen:
#  iterator xitems(o: O): int =
#    for el in o.a:
#      yield el

var ox: O
ox.a.add(1)
ox.b.add(2)
ox.c = @[5, 7, 11, 13]

for l in ox.items:
  echo l
```

We start again with a dumpAstGen() call, which shows us the shape of the for loop node. In that node, we only have to replace two newIdentNode() calls so that the field names can be provided by iterating over an array of strings, and the object name is taken from the iterator parameter. To get the object name, we first use o.treeRepr, to see the whole parameter structure, and then params.treeRepr, to get the structure of the parameters passed to our iterator. Using subscript operators, we get the actual object name. We insert each new node, that we create in the for loop with a call of insert(body(o), body(o).len, node), as the new last node in the body of the iterator. We can create a more flexible variant of our above macro when we pass the actual field names as additional parameters to the pragma macro:

```Nim
import std/macros

type
  O = object
    a, b, c: seq[int]

macro addItFields(fields: openArray[string]; o: untyped): untyped =
  expectKind(o, nnkIteratorDef)
  let objName = o.params[1][0]
  for f in fields:
    let node =
      nnkStmtList.newTree(nnkForStmt.newTree(newIdentNode("el"),
          nnkDotExpr.newTree(newIdentNode($objName),newIdentNode($f)),
          nnkStmtList.newTree(nnkYieldStmt.newTree(newIdentNode("el")))))
    insert(body(o), body(o).len, node)
  result = o

iterator items(o: O): int {.addItFields(["a", "b", "c"]).} =
  discard

var ox: O
ox.a.add(1)
ox.b.add(2)
ox.c = @[5, 7, 11, 13]

for l in ox.items:
  stdout.write l, ' '

# When we run this macro or the one before, we get
# 1 2 5 7 11 13
```

### Macros for generating data types

As one more exercise for the use of macros, we will create some data types in this section. In the previous section, we had a data type like

```
type
  Group = ref object of Element
    lines: seq[Line]
    circs: seq[Circ]
    texts: seq[Text]
    rects: seq[Rect]
    pads: seq[Pad]
    holes: seq[Hole]
    paths: seq[Path]
    pins: seq[Pin]
    traces: seq[Trace]
```

Here, the individual fields have a well-defined shape — all members are sequences of other data types, and the field names are derived from the type names. We may wonder if creating the fields with some form of a macro would make sense. Let’s investigate this.\[82\] Let us assume that we need a reference object with some fields that are sequences of the base types int, float, and string. Again, we start by using the dumpAstGen() macro. We don’t have to understand its output in detail. It is enough to recognize that each of the three actual fields of our ref object was created by a nnkIdentDefs.newTree() statement, and that these three statements are surrounded by a nnkRecList.newTree() call. So we start by producing an empty RecList with a call of nnkRecList.newTree(), and then iterate over an array with the three type names, create the IdentDefs with nnkIdentDefs.newTree() and add them to the RecList. Finally, we call nnkStmtList.newTree() passing our RecList as a parameter. Mostly this is just copy&paste, with the only exception that we have to remember that our rfn variable, which we use to iterate over the type names, is not a string, but a NimNode inside the macro, so we have to apply the stringify operator $ on it when we pass it as an argument to newIdentNode():

```Nim
type
  O = ref object of RootRef
    ints: seq[int]
    floats: seq[float]
    strings: seq[string]

import std/macros
#[
dumpAstGen:
  type
    O1 = ref object of RootRef
      ints: seq[int]
      floats: seq[float]
      strings: seq[string]
]#

#[
nnkStmtList.newTree(
  nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      newIdentNode("O1"),
      newEmptyNode(),
      nnkRefTy.newTree(
        nnkObjectTy.newTree(
          newEmptyNode(),
          nnkOfInherit.newTree(
            newIdentNode("RootRef")
          ),
          nnkRecList.newTree(
            nnkIdentDefs.newTree(
              newIdentNode("ints"),
              nnkBracketExpr.newTree(
                newIdentNode("seq"),
                newIdentNode("int")
              ),
              newEmptyNode()
            ),
            nnkIdentDefs.newTree(
              newIdentNode("floats"),
              nnkBracketExpr.newTree(
                newIdentNode("seq"),
                newIdentNode("float")
              ),
              newEmptyNode()
            ),
            nnkIdentDefs.newTree(
              newIdentNode("strings"),
              nnkBracketExpr.newTree(
                newIdentNode("seq"),
                newIdentNode("string")
              ),
              newEmptyNode()
            )
          )
        )
      )
    )
  )
)
]#

const RecFieldNames = ["int", "float", "string"]
macro genO1(): untyped =
  var recList = nnkRecList.newTree()
  for rfn in RecFieldNames:

    recList.add(nnkIdentDefs.newTree(newIdentNode($rfn & 's'),
      nnkBracketExpr.newTree(newIdentNode("seq"),
      newIdentNode($rfn)), newEmptyNode()))

  result = nnkStmtList.newTree(nnkTypeSection.newTree(nnkTypeDef.newTree(newIdentNode("O1"),
    newEmptyNode(), nnkRefTy.newTree(nnkObjectTy.newTree(newEmptyNode(),
    nnkOfInherit.newTree(newIdentNode("RootRef")), nnkRecList.newTree(recList))))))

genO1()

var o1 = O1(ints: @[1, 2, 3], floats: @[0.1, 0.2, 0.3], strings: @["seems", "to", "work"])
echo o1.ints
echo o1.floats
echo o1.strings
```

When we compile and run the above code, we get an output that seems to make some sense. But can we really trust our macro? Well, we can replace var o1 = O1 with var o1 = O and compile and run again: At least we get the same file size, and the same output, so our macro should be fine.

### Macros to generate new operator symbols

Earlier in the book, we have already learned how we can define new procs and templates, which can be used as operators. In this section, we will learn how we can create a macro that does not only create an operator that can work on existing variables, but also can be used to create new variables. In Nim, we use the var or let keyword to create new variables. Some other languages allow creating new variables on the fly by using just "=", ":=", or "!=" for the assignment.

```Nim
import std/macros

dumpAstGen:
  var xxx: float

macro `!=`(n, t: untyped): untyped =
  let nn = n.repr
  let tt = t.repr
  nnkStmtList.newTree(
    nnkVarSection.newTree(
      nnkIdentDefs.newTree(
        # newIdentNode("xxx"),
        newIdentNode(nn),
        # newIdentNode("float"),
        newIdentNode(tt),
        newEmptyNode()
      )
    )
  )

proc main =
  myVar != int
  myVar = 13
  echo myVar, " ", typeof(myVar)

main()
```

Again, dumpAstGen() shows us the structure of the needed AST. We use repr() to get the string representation of the two macro arguments, and in the dumpAstGen() output, we replace the arguments of the newIdentNode() calls with those values. When we compile and run the above program, we get

```
$ ./t 
13 int
```

In the case that we should really intend to use such a macro in our own code, we should of course add some code to the macro, to check that the passed arguments have the correct content.

References:

- https://nim-lang.org/docs/manual.html#macros
- https://nim-lang.org/docs/tut3.html
- https://nim-by-example.github.io/macros/
- https://hookrace.net/blog/introduction-to-metaprogramming-in-nim/
- https://flenniken.net/blog/nim-macros/
- https://dev.to/beef331/demystification-of-macros-in-nim-13n8

# Templates

Nim templates are very different from C++ templates! In C++ templates are used for generic programming — a style of computer programming in which algorithms are written in terms of types to-be-specified-later that are then instantiated when needed for specific types provided as parameters.[62] This is referred to as generics in Nim and other programming languages. We learned about Nim’s generics earlier in this book.

Nim templates are a simple, parameterized code substitution mechanism, and are used similarly as procedures. The syntax to invoke a template is the same as calling a procedure. However, while procedures build a single block of code that is then called multiple times, templates work more like C macros, performing a (textual) code substitution. Wherever we invoke a template, the template source code is inserted at the call site. In this way, Nim templates have indeed some similarities to C macros. But while C macros are executed by the C pre-processor and can do only plain source text substitutions, Nim templates operate on Nim’s abstract syntax trees, are processed in the semantics pass of the compiler, integrate well with the rest of the language, and share none of C’s preprocessor macros flaws.

In some way, Nim templates are a simplified application of Nim’s powerful macro and meta-programming system, which we will discuss in detail in Part VI of the book.

In C we could use the "#define" preprocessor directive to define two simple C macros.

```
#define PI 3.1416
#define SQR(x) (x)*(x)
```

The C pre-processor would then replace the symbol PI in the C source code with the float literal 3.1416 before the code is processed by the C compiler. And as the C pre-processor can recognize some simple form of parameters, it would replace SQR(a + b) with (a+b)*(a+b).

In Nim we would define a const for PI and use a generic proc or a template for SQR():

```
const PI = 3.1416
proc sqr1[T](x: T): T = x * x
template sqr2(x: typed): typed = x * x
```

Here the sqr2() template uses the special typed parameter, which specifies that the parameter has a well-defined type in the template body, but that arbitrary data types are accepted. So sqr1() and sqr2() would work for all numeric types and also for other data types for which we have defined a * operation. When there is no * operator defined for the passed data type, the compiler will give an error message.



Nim templates, like procs, accept all of Nim’s ordinary data types, in addition to the abstract meta-types typed and untyped. The abstract data types typed and untyped can be used only for the types of template and macro parameters, but not for parameters of procedures, functions, iterators, or to define variables.

We will explain the differences between typed and untyped in detail later in this section. The short version of the explanation is that typed template parameters must have a well-defined data type when we pass them to the template, while untyped parameters can also be passed as undefined symbolic names.

So we can in principle replace each procedure or function definition with a template. The important difference between procs and templates is that ordinary procs are instantiated only once, generic procs are instantiated for each data type with which they are used, while templates are instantiated for each invocation of the template. The compiler creates for each defined proc some machine code, which is executed whenever the procedure is called. But for templates, the compiler does some code substitution — the source code of the template is inserted where the template is invoked. This avoids the need for an actual jump to a different machine code block when a procedure is called but increases the total code size for each use of a template. So we would typically avoid frequently used templates that contain a lot of code.

For each ordinary proc, one block of machine code instructions is generated, and when the proc is called, program execution has to jump to this block, and back when the procedure execution is done. This jumping involves some minimal overhead, which is noticeable for tiny procs called frequently. To avoid this overhead, we may either use a templates or inlined procs, which we discussed in the previous section. The proc inlining can be done automatically by the compiler when the procedure is defined in the source code file where it is used, or when we mark the proc with the inline pragma. Additionally, when we compile our program with -d:lto, the compiler can inline all procedures and functions. Generally, the compiler should know well when inlining makes sense, so in most cases, it doesn’t make much sense to just use templates instead of (small) procs merely to avoid the [proc} call overhead.

Templates can be used as a form of alias. Sometimes we have nested data structures, and would like to have a shorter alias for the access of fields:

```
type
  Point = object
    x, y: int

  Circle = object
    center: Point

template x(c: Circle): int = c.center.x

template `x=`(c: var Circle; v: int) = c.center.x = v

var a, b: Circle

a.center.x = 7
echo a.center.x

b.x = 7
echo b.x
```

The two templates simplify the access of field x, and as templates are pure code substitution, their use costs no performance. Since version 1.6, Nim also has the with macro, which can be used to save some typing. Note that in the second template, we have called the second int parameter v — calling them x would give some trouble:

Error: in expression 'b.center.7': identifier expected, but found '7'

Nim’s system module uses templates to define some operators like

```
template `!=` (a, b: untyped): untyped =
  not (a == b)
```

This way != is always the opposite of ==, so when we define the == operator for our own custom data types, != is available for free.

In some situations, using templates instead of procs can avoid some overhead. Let us investigate a log() template that can print messages to stdout when a global boolean constant is set to true:

```
const
  debug = true

template log(msg: string) =
  if debug: stdout.writeLine(msg)

var
  x = 4
log("x has the value: " & $x)
```

Here, log() is called with the constructed argument ("x has the value: " & $x), which implies a string concatenation operation at runtime. As we use a template, the invocation of log("x has the value: " & $x) is actually replaced by the compiler with code like

```
  if debug: stdout.writeLine("x has the value: " & $x)
```

So, when debug is set to false, absolutely no code is generated. For an ordinary, non-inlined procedure, the situation is different: the expensive string concatenation operation would always have to be performed, but the log() proc would immediately return if debug is false. What exactly would happen when log() is an inlined procedure may depend on the actually used compiler backend. You may wonder if, inside our template from above, we should have used "when" instead of "if". The use of "when" should be possible, as debug is a compile-time constant, but we assume that the use of "if" generates the same machine code for this use case.

Note that the delayed (lazy) parameter evaluation for template parameters can have disadvantages. When we modify the log() template like this:

```
template log(msg: string) =
  for i in 0 .. 2:
    stdout.writeLine(msg)

var x = 4
log("x has the value: " & $x)
```

the expensive string concatenation operation would be done in principle three times in the template body.[63] In contrast, for a procedure, the already evaluated parameter would be passed. So, when we access a parameter multiple times inside a template, it can make sense to assign the parameter to a local variable and then use only that variable.

Templates can inject entities defined in the template body into the surrounding scope. By default, variables defined in the template body are not injected in the surrounding scope, but procs are:

```
template gen =
  var a: int
  proc maxx(a, b: int): int =
    if a > b: a else: b

gen()
echo maxx(2, 3)
# echo a
```

The call echo maxx(2, 3) compiles and works, while echo a complains about an undefined symbol.

A very special property of templates and macros is that we can pass code blocks to them when we use untyped for the type of the last parameter.

```
template withFile(f: untyped; filename: string; actions: untyped) =
  var f: File
  if open(f, filename, fmWrite):
      actions
      close(f)

withFile(myTextFile, "thisIsReallyNotAnExistingFileWithImportantContent.txt"):
  myTextFile.writeLine("line 1")
  myTextFile.writeLine("line 2")
```

The template withFile() from the above example has three parameters — a parameter f of untyped type, a filename of string type, and as the last parameter one more untyped parameter, which we called actions. For this last untyped actions parameter, we can pass an indented code block.

When we invoke the withFile() template, we pass the first two parameters in the well-known way by putting them in a parameter list enclosed in round brackets. However, instead of also passing the final actions parameter in this manner, we put a colon after the parameter list and pass the following indented code block as the last untyped parameter. In the body of the above template, we have an open() call which opens a file with the specified filename and the fmWrite mode. The template then executes the passed code block and finally closes the file. The first parameter of our withFile() template has also a special property: As we use untyped for the f parameter, we can pass the still undefined symbol myTextFile to the template. In the template body, this symbol is used as a variable name, and our two writeLine() proc calls can use it to refer to the file variable.

As Nim templates are hygienic, the instance of the file variable created in the body of our template can be used by the passed code block, but it actually exists only in the template and does not pollute the global namespace of our program.

By passing an integer and a code block to a template, we can easily create a function similar to the times() construct known from Ruby, to execute a code block n times:

```
template times(n: int; actions: untyped) =
  var i = n
  while i > 0:
    dec(i)
    actions

var x = 0.0
3.times:
  x += 2.0
  echo x, " ", x * x
```

Of course, instead of 3.times:, we could have simply used for _ in 1 .. 3:.

We can also use templates to create new procs. An example is lifting procedures like math.sqrt() that accepts a scalar parameter and returns a scalar value, to work with arrays and sequences. The following example is taken from the official tut2 tutorial:

```
from std/math import sqrt

template liftScalarProc(fname) =
  proc fname[T](x: openarray[T]): auto =
    var temp: T
    type outType = typeof(fname(temp))
    result = newSeq[outType](x.len)
    for i in 0 .. x.high:
      result[i] = fname(x[i])

liftScalarProc(sqrt)   # make sqrt() work for sequences
echo sqrt(@[4.0, 16.0, 25.0, 36.0])   # => @[2.0, 4.0, 5.0, 6.0]
```

The template called liftScalarProc() creates a generic proc that accepts an openArray[T] as a parameter and returns a seq[T]. Well, we should be able to understand the basic ideas used in that code, but it is still fascinating that it really works.
Typed vs untyped parameters

Parameters passed to templates can be of any data type that we can use for procs, including special types such as openarray, varargs and typedesc. Additionally, we can use the symbols untyped and typed as parameter types.

The typedesc type can be used to pass type information to the template, e.g. when we want to create a variable of a special data type. The "meta-types" typed and untyped are used when we want to create a form of generic template that can accept different data types. In reality, the distinction between typed and untyped parameters is not as challenging or crucial for templates as it is for macros. In most cases, it’s evident whether we need the typed or untyped parameter type for a template, or if both will work fine. We discuss the differences between typed and untyped in much more detail in Part VI of the book, when we discuss macros and meta-programming.

The following example demonstrates the use of the untyped and the typedesc parameter:

```
template declareInt(n: untyped) =
  var n: int

declareInt(i)
i = 3
echo i

template declareVar(n: untyped; t: typedesc) =
  var n: t

declareVar(x, float)
x = 3.0
echo x
```

Since the parameter n is untyped, the compiler allows us to pass an undefined symbol to the template. If we changed the parameter type to typed, the compiler would complain with a message like "Error: undeclared identifier: i".

For the second template, called declareVar(), we use an additional parameter of typedesc type so that the template can create a variable of the passed data type for us.

Citing the manual: "An untyped parameter means that symbol lookups and type resolution is not performed before the expression is passed to the template. This means that undeclared identifiers, for example, can be passed to the template. A template where every parameter is untyped is called an immediate template. For historical reasons, templates can be explicitly annotated with an immediate pragma and then these templates do not take part in overloading resolution and the parameters' types are ignored by the compiler. Explicit immediate templates are now deprecated. For historical reasons, stmt was an alias for typed and expr was an alias for untyped, but they are removed."

Earlier, we said that Nim’s templates are hygienic, so you may wonder why the variable declared inside of the template is visible outside. Actually, this is only the case because we pass the symbol n as a template parameter. An ordinary declaration like var h: int would create a variable that is only visible inside the template body; it could not be used after invoking the template. We can use the inject pragma to make such ordinary variables visible outside of templates. For more details, please consult the language manual.
Passing a code block to a template

In the withFile() example above, we demonstrated that a block of statements can be passed as the last argument to a template using the special : syntax. To demonstrate the difference between code blocks of typed and untyped data types, we will cite the Nim language manual. See https://nim-lang.org/docs/manual.html#templates-passing-a-code-block-to-a-template:

Usually, to pass a block of code to a template, the parameter that accepts the block needs to be of type untyped. Because symbol lookups are then delayed until template instantiation time:

```
template t(body: typed) =
  proc p = echo "hey"
  block:
    body

t:
  p()  # fails with 'undeclared identifier: p'
```

The above code fails with the error message that p is not declared. The reason for this is that the p() body is type-checked before getting passed to the body parameter, and type-checking in Nim implies symbol lookups. The same code works with untyped as the passed body is not required to be type-checked:

```
template t(body: untyped) =
  proc p = echo "hey"
  block:
    body

t:
  p() # compiles
```

Passing operators to templates

Another use case for templates with untyped parameters involves the generation of math operations for custom data types. Let us assume that we have created a custom Vector object, for which we have to define addition and subtraction operations. Instead of writing code for both cases, we can use a template and pass the actual math operator as untyped parameter:

```
type
  Vector = object
    x, y, z: int

template genOp(op: untyped) =
  proc `op`(a, b: Vector): Vector =
    Vector(x: `op`(a.x, b.x), y: `op`(a.y, b.y), z: `op`(a.z, b.z))

genOp(`+`)
genOp(`-`)

echo `+`(2, 3) # 5

var p = Vector(x: 1, y: 1, z: 1)
var p2 = p + p
echo p2 # (x: 2, y: 2, z: 2)
```

This works because mathematical operations like 1+2 can be written as `+`(1, 2), and such an operator can be passed as an untyped parameter to a template.
Advanced template use

For more advanced template topics, you should consult the Nim language manual.

This includes the symbol binding rules, identifier construction in templates, lookup rules for template parameters, hygiene in templates, use of the inject pragma, and limitations of the method-call-syntax.

All this is explained well in the language manual, so there’s no need to repeat it here. It might be more beneficial to consult the manual when you actually encounter problems with the default behavior of templates in unique situations.


----

The “types” of template parameters can be the symbols untyped, typed or  typedesc. These are “meta types”, they can only be used in certain contexts.  Regular types can be used too; this implies that typed expressions are expected.

Varargs of untyped  In addition to the untyped meta-type that delays type checking, there is also  varargs[untyped] so that not even the number of parameters is fixed:  template hideIdentifiers(x: varargs[untyped]) = discard  hideIdentifiers(undeclared1, undeclared2)  However, since a template cannot iterate over varargs, this feature is  generally much more useful for macros.  27.13. Symbol binding in templates  A template is a hygienic macro and so opens a new scope. The distinction  between open and closed symbols applies to templates as it does apply to  generics:

As in generics, symbol binding can be influenced via mixin or bind  statements.  27.14. Identifier construction  In templates, identifiers can be constructed with the backticks notation:  template typedef(name: untyped, typ: typedesc) =  type  `T name`* {.inject.} = typ  `P name`* {.inject.} = ref `T name`  typedef(myint, int)  var x: PMyInt  In the example, name is instantiated with myint, so T name becomes Tmyint.  27.15. Template parameter lookup rules  A parameter p in a template is even substituted in the expression x.p. Thus,  template arguments can be used as field names and a global symbol can be  shadowed by the same argument name even when fully qualified:

But the global symbol can be captured by a bind statement. Instead of relying on this subtle rule, name your parameters so  that they do not conflict with other names.  27.16. Hygiene in templates  Per default, templates are hygienic: Local identifiers declared in a template  cannot be accessed in the instantiation context.
Every expansion causes a “fresh” set of local variables to be created. These  local variables do not interfere with each other. A template is thus very  similar to an .inline proc or func.
Whether a symbol that is declared in a template is exposed to the  instantiation scope is controlled by the inject and gensym pragmas: gensym'ed  symbols are not exposed but inject'ed symbols are.  The default for symbols of entity type, var, let and const is gensym and for a  routine it is inject. However, if the name of the entity is passed as a template  parameter, it is an inject'ed symbol:  template withFile(f, fn, mode: untyped, actions: untyped): untyped =  block:  var f: File withFile(txt, "ttempl3.txt", fmWrite):  txt.writeLine("line 1")  txt.writeLine("line 2")  The inject and gensym pragmas are second class annotations; they have no  semantics outside of a template definition and cannot be abstracted over:  {.pragma myInject: inject.}  template t() =  var x {.myInject.}: int
To get rid of hygiene in templates, one can use the dirty pragma for a  template. inject and gensym have no effect in dirty templates.  gensym'ed symbols cannot be used as field in the x.field syntax. Nor can they  be used in the ObjectConstruction(field: value) and  namedParameterCall(field = value) syntactic constructs.
27.17. Method call syntax limitations  The expression x in x.f needs to be checked for semantics (that means  symbol lookup and type checking have to be performed) before it can be  decided that it needs to be rewritten to f(x). Therefore the dot syntax has  some limitations when it is used to invoke templates/macros: