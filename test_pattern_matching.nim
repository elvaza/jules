import unittest
import pattern_matching

const MyConst = "a_constant_value"

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

  test "should handle binding patterns":
    let result = match 2:
      (1 | 2).to(n) => "Got " & $n
      _ => "other"
    check(result == "Got 2")

    let result2 = match 99:
      _.to(n) => "The number is " & $n
    check(result2 == "The number is 99")

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

  test "match should work as an expression":
    let result = match 1:
      1 => "one"
      2 => "two"
      _ => "other"
    check(result == "one")
