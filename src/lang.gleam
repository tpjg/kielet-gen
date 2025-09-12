// this file is just here to make test/sample.gleam compile
import kielet/database.{type Database}

pub fn database() -> Database {
  database.new()
}
