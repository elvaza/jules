import unittest
import pattern_matching

suite "Guard Scoping Test":
  test "should handle guard with capture variable":
    let commands = ["help", "exit"]
    let result = match "help":
      cmd and cmd in commands => "known"
      _ => "unknown"
    check(result == "known")
