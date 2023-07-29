import unittest
import javaclass

suite "parsing and generating":
  test "empty class":
    let
      rawClass = readFile("tests/Foo.class")
      parsed = rawClass.toClassFile()
      generated = parsed.fromClassFile()
    check rawClass == generated
