// this file is just here as a sample for the kielet_gen_test tests
import gleam/int
import gleam/io
import gleam/string
import kielet.{gettext as g_, ngettext as n_, npgettext as np_, pgettext as p_}
import kielet/context.{Context}
import lang

pub fn lang_test() {
  let db = lang.database()
  let ctx = Context(db, "nl")

  io.println(g_(ctx, "Hello"))
  io.println(string.replace(
    n_(ctx, "That's better than a rabbit", "That's better than %s rabbits", 5),
    "%s",
    int.to_string(5),
  ))
  io.println(p_(ctx, "Lead (the element)", "Lead"))
  io.println(string.replace(
    np_(ctx, "A physical sign with text on it", "A sign", "%s signs", 5),
    "%s",
    int.to_string(5),
  ))
}
