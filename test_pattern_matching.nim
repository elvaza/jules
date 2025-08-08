import unittest
import pattern_matching
import std/tables

const MyConst = "a_constant_value"

type
  Person = object
    name: string
    age: int

suite "Pattern Matching Tests":

  test "should match integer literals":
    let result = match 42:
      10 => "ten"
      42 => "forty-two"
      _  => "other"
    check(result == "forty-two")

  test "should match string literals":
    let result = match "nim":
      "rust" => "crab"
      "nim"  => "crown"
      _      => "unknown"
    check(result == "crown")

  test "should match boolean literals":
    let result = match true:
      false => "is false"
      true  => "is true"
    check(result == "is true")

  test "should use wildcard for unmatched cases":
    let result = match 100:
      1 => "one"
      2 => "two"
      _ => "something else"
    check(result == "something else")

  test "should bind value to a variable":
    let result = match 123:
      42 => -1
      y  => y
    check(result == 123)

  test "should handle mixed patterns correctly":
    let result = match "test":
      "hello" => "greeting"
      s       => "bound: " & s
    check(result == "bound: test")

  test "should handle variable hygiene":
    let result = match 10:
      x => x
    let finalResult = match 20:
      x => x + result
    check(finalResult == 30)

  test "should handle OR-patterns with literals":
    let result = match 2:
      1 | 2 | 3 => "small number"
      4 | 5     => "medium number"
      _         => "large number"
    check(result == "small number")

    let result2 = match 5:
      1 | 2 | 3 => "small number"
      4 | 5     => "medium number"
      _         => "large number"
    check(result2 == "medium number")

  test "should match against declared constants":
    let result = match "a_constant_value":
      MyConst => "matched the constant"
      _       => "did not match"
    check(result == "matched the constant")

    let result2 = match "another_value":
      MyConst => "fail"
      x       => x
    check(result2 == "another_value")

  test "should handle sequence patterns":
    let s = @[1, 2, 3]
    let result = match s:
      [1, 2, 4] => "no"
      [1, x, y] => $x & $y
      _ => "fail"
    check(result == "23")

  test "should handle tuple patterns":
    let t = (1, "hello")
    let result = match t:
      (1, "world") => "no"
      (x, y) => "yes: " & $x & ", " & y
      _ => "fail"
    check(result == "yes: 1, hello")

  test "should handle mapping patterns":
    var t1 = initTable[string, int]()
    t1["name"] = 100
    t1["age"] = 1
    let result = match t1:
      {"name": 100, "age": x} => x
      _ => -1
    check(result == 1)

    var t2 = initTable[string, string]()
    t2["name"] = "jules"
    let result2 = match t2:
      {"name": "not-jules"} => "no"
      {"name": n} => "name is " & n
      _ => "fail"
    check(result2 == "name is jules")

  test "should handle class patterns":
    let p = Person(name: "jules", age: 1)
    let result = match p:
      Person(name: "dave", age: _) => "dave"
      Person(name: n, age: 1) => "jules is 1"
      _ => "fail"
    check(result == "jules is 1")

    let result2 = match p:
      Person(name: "jules", age: a) => a
      _ => -1
    check(result2 == 1)

  test "match should work as an expression":
    let result = match 1:
      1 => "one"
      2 => "two"
      _ => "other"
    check(result == "one")
