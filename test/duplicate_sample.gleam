// Test file with duplicate translation strings
import kielet.{gettext, ngettext, pgettext}
import kielet/context.{type Context}

pub fn test1(ctx: Context) {
  // First occurrence of "Hello"
  gettext(ctx, "Hello")
}

pub fn test2(ctx: Context) {
  // Second occurrence of "Hello" - should be deduplicated
  gettext(ctx, "Hello")
}

pub fn test3(ctx: Context) {
  // Third occurrence of "Hello" - should also be deduplicated
  gettext(ctx, "Hello")
}

pub fn test4(ctx: Context) {
  // A different message
  gettext(ctx, "Goodbye")
}

pub fn test5(ctx: Context) {
  // First occurrence of ngettext
  ngettext(ctx, "One item", "Many items", 1)
}

pub fn test6(ctx: Context) {
  // Same ngettext - should be deduplicated
  ngettext(ctx, "One item", "Many items", 2)
}

pub fn test7(ctx: Context) {
  // pgettext with duplicate
  pgettext(ctx, "Navigation menu", "File")
}

pub fn test8(ctx: Context) {
  // Same pgettext - should be deduplicated
  pgettext(ctx, "Navigation menu", "File")
}
