import unittest
import pattern_matching

suite "AS-Pattern Tests":
  test "should handle binding patterns with .to()":
    let result = match 2:
      (1 | 2).to(n) => "Got " & $n
      _ => "other"
    check(result == "Got 2")

    let result2 = match 99:
      _.to(n) => "The number is " & $n
    check(result2 == "The number is 99")
