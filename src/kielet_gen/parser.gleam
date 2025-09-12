import glance
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/string
import simplifile

pub fn parse_files(to: String, files: List(String)) -> Nil {
  let path = string.split(to, "/")
  let directory =
    path
    |> list.take(list.length(path) - 1)
    |> string.join("/")
  let assert Ok(_) = simplifile.create_directory_all(directory)
    as "cannot create directory for output"
  let assert Ok(_) = simplifile.write(to: to, contents: "")
    as "cannot write to output file"

  list.map(files, fn(file) { parse_file(to, file) })

  Nil
}

pub fn parse_file(to: String, file: String) -> Nil {
  // Implement parsing logic here
  io.println("Parsing file: " <> file)
  let assert Ok(contents) = simplifile.read(file) as "cannot read file"
  let assert Ok(m) = glance.module(contents)

  let imports_map = collect_imports(m.imports)
  let calls = collect_calls(m)
  list.each(calls, fn(call) {
    case analyze_call(call, imports_map, contents) {
      option.Some(tuple) -> {
        case tuple {
          #(nr, "kielet.gettext", args) -> output_gettext(to, file, nr, args)
          #(nr, "kielet.ngettext", args) -> output_ngettext(to, file, nr, args)
          #(nr, "kielet.pgettext", args) -> output_pgettext(to, file, nr, args)
          #(nr, "kielet.npgettext", args) ->
            output_npgettext(to, file, nr, args)
          #(_, _, _) -> Nil
        }
      }
      option.None -> Nil
    }
  })
  Nil
}

fn output_gettext(to: String, file: String, nr: Int, args: List(String)) -> Nil {
  let assert [_, a] = args as "gettext expects two arguments"
  let contents = [
    "#." <> file <> ":" <> int.to_string(nr),
    "msgid " <> a,
    "msgstr " <> a,
    "",
    "",
  ]
  let assert Ok(_) = simplifile.append(to, string.join(contents, "\n"))
    as "cannot write to output file"

  Nil
}

fn output_ngettext(to: String, file: String, nr: Int, args: List(String)) -> Nil {
  let assert [_, a, b, _] = args as "ngettext expects four arguments"
  let contents = [
    "#." <> file <> ":" <> int.to_string(nr),
    "msgid " <> a,
    "msgid_plural \"\"",
    "msgstr[0] " <> a,
    "msgstr[1] " <> b,
    "",
    "",
  ]
  let assert Ok(_) = simplifile.append(to, string.join(contents, "\n"))
    as "cannot write to output file"

  Nil
}

fn output_pgettext(to: String, file: String, nr: Int, args: List(String)) -> Nil {
  let assert [_, a, b] = args as "pgettext expects three arguments"
  let contents = [
    "#." <> file <> ":" <> int.to_string(nr),
    "msgctxt " <> a,
    "msgid " <> b,
    "msgstr " <> b,
    "",
    "",
  ]
  let assert Ok(_) = simplifile.append(to, string.join(contents, "\n"))
    as "cannot write to output file"

  Nil
}

fn output_npgettext(
  to: String,
  file: String,
  nr: Int,
  args: List(String),
) -> Nil {
  let assert [_, a, b, c, _] = args as "npgettext expects four arguments"
  let contents = [
    "#." <> file <> ":" <> int.to_string(nr),
    "msgctxt " <> a,
    "msgid " <> b,
    "msgid_plural \"\"",
    "msgstr[0] " <> b,
    "msgstr[1] " <> c,
    "",
    "",
  ]
  let assert Ok(_) = simplifile.append(to, string.join(contents, "\n"))
    as "cannot write to output file"

  Nil
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
    glance.Echo(_, expression) ->
      option.map(expression, collect_expression) |> option.unwrap([])
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
    glance.LabelledField(_, item) -> collect_expression(item)
    glance.ShorthandField(_) -> []
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
    glance.LabelledField(label, expr) ->
      label <> ": " <> stringify_expr(imports, expr)
    glance.ShorthandField(label) -> label
    glance.UnlabelledField(expr) -> stringify_expr(imports, expr)
  }
}

fn get_line_number(source: String, pos: Int) -> Int {
  let before = string.drop_end(source, string.length(source) - pos)
  let lines = string.split(before, "\n")
  list.length(lines)
}
