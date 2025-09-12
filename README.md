# kielet-gen

A command-line tool for Gleam that helps manage internationalization (i18n) by parsing Gleam source files for translation function calls and generating helper code for the [kielet](https://hex.pm/packages/kielet) internationalization library.

## Features

### Parse Mode
Extracts translatable strings from Gleam source files and generates POT (Portable Object Template) files for translation:

- **`kielet.gettext`** - Simple string translation
- **`kielet.ngettext`** - Plural form translation
- **`kielet.pgettext`** - Context-aware translation
- **`kielet.npgettext`** - Context-aware plural translation

### Code Generation Mode
Generates Gleam helper functions that embed compiled translation files (MO format) directly into your application, eliminating the need for external file loading at runtime.

## Installation

Add `kielet_gen` to your Gleam project:

```sh
gleam add kielet_gen --dev
```

## Usage

### Extract Translatable Strings

Parse Gleam files and generate a POT file for translation:

```bash
gleam run -m kielet/gen parse [--output translations/generated.pot] src/**/*.gleam
```

This will:
- Scan the specified Gleam files for calls to `kielet.gettext`, `kielet.ngettext`, `kielet.pgettext`, and `kielet.npgettext`
- Extract translatable strings with their source file locations and line numbers
- Generate a POT file that can be used by translation tools like Poedit

### Generate Language Helper Code

Generate Gleam code that embeds compiled MO translation files:

```bash
gleam run -m kielet/gen code [--output src/lang.gleam] translations/*.mo
```

This will:
- Read compiled MO translation files
- Embed them as base64-encoded data in generated Gleam code
- Create a `database()` function that returns a pre-loaded `kielet.Database` with all translations

## Example

Given a Gleam source file using kielet:

```gleam
import kielet.{gettext as g_, ngettext as n_, pgettext as p_}
import kielet/context.{Context}

pub fn greet(ctx: Context, count: Int) {
  // Simple translation
  io.println(g_(ctx, "Hello"))

  // Plural translation
  let message = n_(ctx, "You have 1 message", "You have %s messages", count)
  io.println(string.replace(message, "%s", int.to_string(count)))

  // Context-aware translation
  io.println(p_(ctx, "Menu item", "File"))
}
```

Running the parser will generate a POT file like:

```pot
#.src/greet.gleam:6
msgid "Hello"
msgstr "Hello"

#.src/greet.gleam:9
msgid "You have 1 message"
msgid_plural ""
msgstr[0] "You have 1 message"
msgstr[1] "You have %s messages"

#.src/greet.gleam:13
msgctxt "Menu item"
msgid "File"
msgstr "File"
```

After translating the POT file to MO files, the code generator creates a helper module:

```gleam
// Generated automatically for use by kielet
import gleam/bit_array
import kielet/database
import kielet/language

pub fn database() -> database.Database {
  let db = database.new()

  // Load language from nl.mo as base64 encoded MO data
  let assert Ok(mo_data) = bit_array.base64_decode("3hIElQAAAAA...")
  let assert Ok(lang) = language.load("nl", mo_data)
  let db = db |> database.add_language(lang)

  db
}
```
