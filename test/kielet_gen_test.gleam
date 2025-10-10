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

/// Tests that duplicate translation strings are properly deduplicated
/// and all source locations are preserved in the output
pub fn parser_deduplication_test() {
  parser.parse_files("test/output/duplicates.pot", [
    "test/duplicate_sample.gleam",
  ])

  let assert Ok(pot) = simplifile.read("test/output/duplicates.pot")

  // Check that "Hello" appears only once
  let hello_count =
    pot
    |> string.split("msgid \"Hello\"")
    |> list.length
  assert hello_count == 2
  // Split returns n+1 parts for n occurrences, so 2 means it appears once

  // Check that all three source locations for "Hello" are present
  assert string.contains(pot, "test/duplicate_sample.gleam:7")
  assert string.contains(pot, "test/duplicate_sample.gleam:12")
  assert string.contains(pot, "test/duplicate_sample.gleam:17")

  // Check that "One item" ngettext appears only once
  let one_item_count =
    pot
    |> string.split("msgid \"One item\"")
    |> list.length
  assert one_item_count == 2

  // Check that both source locations for ngettext are present
  assert string.contains(pot, "test/duplicate_sample.gleam:27")
  assert string.contains(pot, "test/duplicate_sample.gleam:32")

  // Check that pgettext with context "Navigation menu" appears only once
  let file_pgettext_count =
    pot
    |> string.split("msgctxt \"Navigation menu\"")
    |> list.length
  assert file_pgettext_count == 2

  // Check that both source locations for pgettext are present
  assert string.contains(pot, "test/duplicate_sample.gleam:37")
  assert string.contains(pot, "test/duplicate_sample.gleam:42")

  // Check that "Goodbye" appears (single occurrence)
  assert string.contains(pot, "msgid \"Goodbye\"")
  assert string.contains(pot, "test/duplicate_sample.gleam:22")
}

/// Tests deduplication across multiple files
pub fn parser_multi_file_deduplication_test() {
  parser.parse_files("test/output/multi_file.pot", [
    "test/sample.gleam",
    "test/duplicate_sample.gleam",
  ])

  let assert Ok(pot) = simplifile.read("test/output/multi_file.pot")

  // "Hello" appears in both sample.gleam and duplicate_sample.gleam
  // It should be deduplicated with all source locations
  let hello_count =
    pot
    |> string.split("msgid \"Hello\"")
    |> list.length
  assert hello_count == 2
  // Should appear only once

  // Check for locations from both files
  assert string.contains(pot, "test/sample.gleam:13")
  assert string.contains(pot, "test/duplicate_sample.gleam:7")
  assert string.contains(pot, "test/duplicate_sample.gleam:12")
  assert string.contains(pot, "test/duplicate_sample.gleam:17")
}
