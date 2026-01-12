import glance
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/string
import simplifile

// Type to represent a unique translation entry
pub type EntryKey {
  GettextEntry(msgid: String)
  NGettextEntry(msgid: String, msgid_plural: String)
  PGettextEntry(msgctxt: String, msgid: String)
  NPGettextEntry(msgctxt: String, msgid: String, msgid_plural: String)
}

// Data for a translation entry including all source locations
pub type EntryData {
  EntryData(key: EntryKey, locations: List(#(String, Int)))
}

// Convert an EntryKey to a string for use as Dict key
fn entry_key_to_string(key: EntryKey) -> String {
  case key {
    GettextEntry(msgid) -> "gettext:" <> msgid
    NGettextEntry(msgid, msgid_plural) ->
      "ngettext:" <> msgid <> "|" <> msgid_plural
    PGettextEntry(msgctxt, msgid) -> "pgettext:" <> msgctxt <> "|" <> msgid
    NPGettextEntry(msgctxt, msgid, msgid_plural) ->
      "npgettext:" <> msgctxt <> "|" <> msgid <> "|" <> msgid_plural
  }
}

// Deduplicate entries by merging locations for identical keys
fn deduplicate_entries(entries: List(EntryData)) -> List(EntryData) {
  // Build a dict with all entries
  let entries_dict =
    list.fold(entries, dict.new(), fn(acc, entry) {
      let key_str = entry_key_to_string(entry.key)
      case dict.get(acc, key_str) {
        Ok(existing_entry) -> {
          // Merge locations
          let EntryData(existing_key, existing_locations) = existing_entry
          let merged =
            EntryData(
              key: existing_key,
              locations: list.append(existing_locations, entry.locations),
            )
          dict.insert(acc, key_str, merged)
        }
        Error(_) -> dict.insert(acc, key_str, entry)
      }
    })

  // Convert back to list
  dict.values(entries_dict)
}

// Write deduplicated entries to a .pot file
fn write_pot_file(to: String, entries: List(EntryData)) -> Nil {
  let contents =
    entries
    |> list.map(entry_to_pot_string)
    |> string.join("\n")

  let assert Ok(_) = simplifile.write(to: to, contents: contents)
    as "cannot write to output file"

  Nil
}

// Convert a single entry to its .pot file string representation
fn entry_to_pot_string(entry: EntryData) -> String {
  // Generate location comments
  let location_comments =
    entry.locations
    |> list.map(fn(loc) { "#. " <> loc.0 <> ":" <> int.to_string(loc.1) })
    |> string.join("\n")

  // Generate entry content based on type
  let entry_content = case entry.key {
    GettextEntry(msgid) -> {
      ["msgid " <> msgid, "msgstr " <> msgid] |> string.join("\n")
    }
    NGettextEntry(msgid, msgid_plural) -> {
      [
        "msgid " <> msgid,
        "msgid_plural " <> msgid_plural,
        "msgstr[0] \"\"",
        "msgstr[1] \"\"",
      ]
      |> string.join("\n")
    }
    PGettextEntry(msgctxt, msgid) -> {
      ["msgctxt " <> msgctxt, "msgid " <> msgid, "msgstr " <> msgid]
      |> string.join("\n")
    }
    NPGettextEntry(msgctxt, msgid, msgid_plural) -> {
      [
        "msgctxt " <> msgctxt,
        "msgid " <> msgid,
        "msgid_plural " <> msgid_plural,
        "msgstr[0] \"\"",
        "msgstr[1] \"\"",
      ]
      |> string.join("\n")
    }
  }

  // Combine location comments and entry content with blank lines
  [location_comments, entry_content, "", ""] |> string.join("\n")
}

pub fn parse_files(to: String, files: List(String)) -> Nil {
  let path = string.split(to, "/")
  let directory =
    path
    |> list.take(list.length(path) - 1)
    |> string.join("/")
  let assert Ok(_) = simplifile.create_directory_all(directory)
    as "cannot create directory for output"

  // Collect all entries from all files
  let all_entries =
    files
    |> list.flat_map(parse_file)

  // Deduplicate entries
  let deduplicated = deduplicate_entries(all_entries)

  // Write the deduplicated entries to the output file
  write_pot_file(to, deduplicated)

  Nil
}

pub fn parse_file(file: String) -> List(EntryData) {
  // Implement parsing logic here
  io.println("Parsing file: " <> file)
  let assert Ok(contents) = simplifile.read(file) as "cannot read file"
  let assert Ok(m) = glance.module(contents)

  let imports_map = collect_imports(m.imports)
  let calls = collect_calls(m)
  list.filter_map(calls, fn(call) {
    case analyze_call(call, imports_map, contents) {
      option.Some(tuple) -> {
        case tuple {
          #(nr, "kielet.gettext", args) ->
            Ok(output_gettext(file, nr, args))
          #(nr, "kielet.ngettext", args) ->
            Ok(output_ngettext(file, nr, args))
          #(nr, "kielet.pgettext", args) ->
            Ok(output_pgettext(file, nr, args))
          #(nr, "kielet.npgettext", args) ->
            Ok(output_npgettext(file, nr, args))
          #(_, _, _) -> Error(Nil)
        }
      }
      option.None -> Error(Nil)
    }
  })
}

fn output_gettext(file: String, nr: Int, args: List(String)) -> EntryData {
  let assert [_, a] = args as "gettext expects two arguments"
  let key = GettextEntry(msgid: a)
  EntryData(key: key, locations: [#(file, nr)])
}

fn output_ngettext(file: String, nr: Int, args: List(String)) -> EntryData {
  let assert [_, a, b, _] = args as "ngettext expects four arguments"
  let key = NGettextEntry(msgid: a, msgid_plural: b)
  EntryData(key: key, locations: [#(file, nr)])
}

fn output_pgettext(file: String, nr: Int, args: List(String)) -> EntryData {
  let assert [_, a, b] = args as "pgettext expects three arguments"
  let key = PGettextEntry(msgctxt: a, msgid: b)
  EntryData(key: key, locations: [#(file, nr)])
}

fn output_npgettext(file: String, nr: Int, args: List(String)) -> EntryData {
  let assert [_, a, b, c, _] = args as "npgettext expects four arguments"
  let key = NPGettextEntry(msgctxt: a, msgid: b, msgid_plural: c)
  EntryData(key: key, locations: [#(file, nr)])
}

// ---------------------------------------------------------------------------
// Internal functions to collect the information we need from the glance
// parsed file.
// ---------------------------------------------------------------------------

fn analyze_call(
  call: glance.Expression,
  imports: List(#(String, String)),
  source: String,
) -> option.Option(#(Int, String, List(String))) {
  case call {
    glance.Call(loc, fun, args) -> {
      case fun {
        glance.FieldAccess(_, container, label) -> {
          case container {
            glance.Variable(_, name) -> {
              let args_str = list.map(args, stringify_field(imports, _))
              let line = get_line_number(source, loc.start)
              option.Some(#(line, name <> "." <> label, args_str))
            }
            _ -> option.None
          }
        }
        glance.Variable(_, called_name) -> {
          case list.find(imports, fn(pair) { pair.0 == called_name }) {
            Ok(#(_, lib_fun)) -> {
              let args_str = list.map(args, stringify_field(imports, _))
              let line = get_line_number(source, loc.start)
              option.Some(#(line, lib_fun, args_str))
            }
            Error(_) -> option.None
          }
        }
        _ -> option.None
      }
    }
    _ -> option.None
  }
}

fn collect_imports(
  imports: List(glance.Definition(glance.Import)),
) -> List(#(String, String)) {
  list.flat_map(imports, fn(def) {
    let imp = def.definition
    let module = imp.module
    list.map(imp.unqualified_values, fn(u) {
      case u {
        glance.UnqualifiedImport(name, alias) -> {
          let called_name = option.unwrap(alias, name)
          let lib_fun = module <> "." <> name
          #(called_name, lib_fun)
        }
      }
    })
  })
}

fn collect_calls(module: glance.Module) -> List(glance.Expression) {
  list.flat_map(module.functions, fn(f) {
    collect_statements(f.definition.body)
  })
}

fn collect_statements(
  statements: List(glance.Statement),
) -> List(glance.Expression) {
  list.flat_map(statements, collect_statement)
}

fn collect_statement(statement: glance.Statement) -> List(glance.Expression) {
  case statement {
    glance.Use(_, _, function) -> collect_expression(function)
    glance.Assignment(_, _, _, _, value) -> collect_expression(value)
    glance.Assert(_, expression, message) -> {
      let expr_calls = collect_expression(expression)
      let msg_calls =
        option.map(message, collect_expression) |> option.unwrap([])
      list.flatten([expr_calls, msg_calls])
    }
    glance.Expression(expr) -> collect_expression(expr)
  }
}

fn collect_expression(expr: glance.Expression) -> List(glance.Expression) {
  case expr {
    glance.Call(loc, fun, args) -> {
      let fun_calls = collect_expression(fun)
      let arg_calls = list.flat_map(args, collect_field_expr)
      list.flatten([[glance.Call(loc, fun, args)], fun_calls, arg_calls])
    }
    glance.FieldAccess(_, container, _) -> collect_expression(container)
    glance.Tuple(_, elements) -> list.flat_map(elements, collect_expression)
    glance.List(_, elements, rest) -> {
      let el_calls = list.flat_map(elements, collect_expression)
      let rest_calls = option.map(rest, collect_expression) |> option.unwrap([])
      list.flatten([el_calls, rest_calls])
    }
    glance.Block(_, statements) -> collect_statements(statements)
    glance.Fn(_, _, _, body) -> collect_statements(body)
    glance.RecordUpdate(_, _, _, record, fields) -> {
      let rec_calls = collect_expression(record)
      let field_calls =
        list.flat_map(fields, fn(field) {
          option.map(field.item, collect_expression) |> option.unwrap([])
        })
      list.flatten([rec_calls, field_calls])
    }
    glance.TupleIndex(_, tuple, _) -> collect_expression(tuple)
    glance.FnCapture(_, _, fun, before, after) -> {
      let f_calls = collect_expression(fun)
      let b_calls = list.flat_map(before, collect_field_expr)
      let a_calls = list.flat_map(after, collect_field_expr)
      list.flatten([f_calls, b_calls, a_calls])
    }
    glance.BitString(_, segments) -> {
      let seg_calls =
        list.flat_map(segments, fn(seg) {
          list.flatten([
            collect_expression(seg.0),
            list.flat_map(seg.1, collect_bit_option),
          ])
        })
      seg_calls
    }
    glance.Case(_, subjects, clauses) -> {
      let subj_calls = list.flat_map(subjects, collect_expression)
      let clause_calls =
        list.flat_map(clauses, fn(clause) {
          let guard_calls =
            option.map(clause.guard, collect_expression) |> option.unwrap([])
          let body_calls = collect_expression(clause.body)
          list.flatten([guard_calls, body_calls])
        })
      list.flatten([subj_calls, clause_calls])
    }
    glance.BinaryOperator(_, _, left, right) ->
      list.flatten([collect_expression(left), collect_expression(right)])
    glance.NegateInt(_, value) -> collect_expression(value)
    glance.NegateBool(_, value) -> collect_expression(value)
    glance.Echo(_, expression, message) -> {
      let expr_calls =
        option.map(expression, collect_expression) |> option.unwrap([])
      let msg_calls =
        option.map(message, collect_expression) |> option.unwrap([])
      list.flatten([expr_calls, msg_calls])
    }
    glance.Panic(_, message) ->
      option.map(message, collect_expression) |> option.unwrap([])
    glance.Todo(_, message) ->
      option.map(message, collect_expression) |> option.unwrap([])
    _ -> []
  }
}

fn collect_field_expr(
  field: glance.Field(glance.Expression),
) -> List(glance.Expression) {
  case field {
    glance.LabelledField(_, _, item) -> collect_expression(item)
    glance.ShorthandField(_, _) -> []
    glance.UnlabelledField(item) -> collect_expression(item)
  }
}

fn collect_bit_option(
  option: glance.BitStringSegmentOption(glance.Expression),
) -> List(glance.Expression) {
  case option {
    glance.SizeValueOption(size_expr) -> collect_expression(size_expr)
    _ -> []
  }
}

fn stringify_expr(
  imports: List(#(String, String)),
  expr: glance.Expression,
) -> String {
  case expr {
    glance.Variable(_, name) -> {
      case list.find(imports, fn(pair) { pair.0 == name }) {
        Ok(#(_, lib_fun)) -> lib_fun
        Error(_) -> name
      }
    }
    glance.String(_, value) -> "\"" <> value <> "\""
    glance.Int(_, value) -> value
    glance.Float(_, value) -> value
    glance.Tuple(_, elements) -> {
      let els = list.map(elements, stringify_expr(imports, _))
      "#(" <> string.join(els, ", ") <> ")"
    }
    glance.List(_, elements, rest) -> {
      let els = list.map(elements, stringify_expr(imports, _))
      let base = "[" <> string.join(els, ", ")
      case rest {
        option.Some(_r) -> base <> ", ..." <> "]"
        option.None -> base <> "]"
      }
    }
    glance.FieldAccess(_, container, label) ->
      stringify_expr(imports, container) <> "." <> label
    glance.Call(_, fun, args) -> {
      stringify_expr(imports, fun)
      <> "("
      <> string.join(list.map(args, stringify_field(imports, _)), ", ")
      <> ")"
    }
    _ -> string.inspect(expr)
  }
}

fn stringify_field(
  imports: List(#(String, String)),
  field: glance.Field(glance.Expression),
) -> String {
  case field {
    glance.LabelledField(label, _, item) ->
      label <> ": " <> stringify_expr(imports, item)
    glance.ShorthandField(label, _) -> label
    glance.UnlabelledField(expr) -> stringify_expr(imports, expr)
  }
}

fn get_line_number(source: String, pos: Int) -> Int {
  let before = string.drop_end(source, string.length(source) - pos)
  let lines = string.split(before, "\n")
  list.length(lines)
}
