// this file is just here to make test/sample.gleam compile
import kielet.{type Database}

pub fn database() -> Database {
  kielet.new_database()
}
