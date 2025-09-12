import argv
import gleam/io
import gleam/list
import gleam/string
import glint
import kielet_gen/coder.{code_files}
import kielet_gen/parser.{parse_files}
import snag

// MAIN ------------------------------------------------------------------------

/// The `main` function is used as the entry point for kielet gen tools.
/// To see what the dev tools can do, run:
///
/// ```
/// gleam run -m kielet/gen -- --help
/// ```
///
pub fn main() {
  glint.new()
  |> glint.as_module
  |> glint.with_name("kielet/gen")
  |> glint.add(at: ["parse"], do: parse_command())
  |> glint.add(at: ["code"], do: code_command())
  |> glint.run(argv.load().arguments)
}

fn output_flag(default: String) -> glint.Flag(String) {
  glint.string_flag("output")
  |> glint.flag_help("the path to the output file, e.g. " <> default)
  |> glint.flag_default(default)
  |> glint.flag_constraint(fn(s) {
    case string.split(s, "/") |> list.length > 1 {
      True -> Ok(s)
      False ->
        snag.error(
          "invalid output path, needs at least one directory and filename",
        )
    }
  })
}

fn parse_command() -> glint.Command(Nil) {
  // set the help text for the hello command
  use <- glint.command_help(
    "parses the supplied .gleam files to extract translations into a .pot file",
  )
  use output <- glint.flag(output_flag("translations/generated.pot"))
  use _, args, flags <- glint.command()

  // There's a default so this should always succeed
  let assert Ok(output) = output(flags)
  io.println("outputting to: " <> output)
  case args {
    [] -> io.println_error("No files provided, nothing to parse")
    ls -> parse_files(output, ls)
  }

  Nil
}

fn code_command() -> glint.Command(Nil) {
  // set the help text for the hello command
  use <- glint.command_help(
    "generates language helper functions for kielet for the supplied .mo files",
  )
  use output <- glint.flag(output_flag("src/lang.gleam"))
  use _, args, flags <- glint.command()

  // There's a default so this should always succeed
  let assert Ok(output) = output(flags)
  io.println("outputting to: " <> output)
  case args {
    [] -> io.println_error("No files provided, no languages to process")
    ls -> code_files(output, ls)
  }
}
