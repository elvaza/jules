import unittest
import pattern_matching

suite "Pattern Matching Tests":

  test "should match integer literals":
    let x = 42
    let result = match x:
      10 => "ten"
      42 => "forty-two"
      _  => "other"
    check(result == "forty-two")

  test "should match string literals":
    let s = "nim"
    let result = match s:
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
    let x = 100
    let result = match x:
      1 => "one"
      2 => "two"
      _ => "something else"
    check(result == "something else")

  test "should bind value to a variable":
    let x = 123
    let boundValue = match x:
      42 => -1 # This arm will not be taken
      y  => y  # y is bound to the value of x
    check(boundValue == 123)

  test "should handle mixed patterns correctly":
    let val = "test"
    let result = match val:
      "hello" => "greeting"
      s       => "bound: " & s
    check(result == "bound: test")

  test "should handle variable hygiene":
    let result = match 10:
      x => x
    let finalResult = match 20:
      x => x + result # `x` is bound to 20, `result` is 10 from the outer scope
    check(finalResult == 30)

  # test "should handle AS-patterns":
  #   let value = 2
  #   let result = match value:
  #     1 | 2 as n => "Got " & $n
  #     _ => "other"
  #   check(result == "Got 2")

  #   let result2 = match 99:
  #     _ as n => "The number is " & $n
  #   check(result2 == "The number is 99")

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

  test "match should work as an expression":
    let x = 1
    let result = match x:
      1 => "one"
      2 => "two"
      _ => "other"
    check(result == "one")
