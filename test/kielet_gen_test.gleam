import glance
import gleam/list
import gleam/string
import gleeunit
import kielet_gen/coder
import kielet_gen/parser
import simplifile

pub fn main() {
  gleeunit.main()
}

/// Tests that the coder generates an output file and that it is valid Gleam
/// code by parsing it with glance.
pub fn coder_test() {
  coder.code_files("test/output/lang.gleam", ["test/nl.mo"])
  let assert Ok(f) = simplifile.read("test/output/lang.gleam")
  let assert Ok(m) = glance.module(f)

  // Check there are at least 3 imports (gleam/bit_array, kielet/database, kielet/language)
  assert m.imports |> list.length >= 3
  // Check that the "database" function exists
  assert list.filter(m.functions, fn(def) { def.definition.name == "database" })
    |> list.length
    >= 1
}

pub fn parser_test() {
  parser.parse_files("test/output/generated.pot", ["test/sample.gleam"])

  let assert Ok(pot) = simplifile.read("test/output/generated.pot")

  assert string.contains(pot, "msgid \"Hello\"")
  assert string.contains(pot, "msgid \"That's better than a rabbit\"")
  assert string.contains(pot, "msgctxt \"Lead (the element)\"")
  assert string.contains(pot, "msgctxt \"A physical sign with text on it\"")
}
