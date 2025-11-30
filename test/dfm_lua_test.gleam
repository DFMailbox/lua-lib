import dfm_lua
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleeunit
import glua

pub fn main() -> Nil {
  gleeunit.main()
}

type Person {
  Person(name: String, age: Int, children: List(Person))
}

fn person_to_json(person: Person) -> json.Json {
  let Person(name:, age:, children:) = person
  json.object([
    #("name", json.string(name)),
    #("age", json.int(age)),
    #("children", json.array(children, person_to_json)),
  ])
}

fn person_decoder() {
  use name <- decode.field("name", decode.string)
  use age <- decode.field("age", decode.int)

  use children <- decode.field("children", decode.list(person_decoder()))
  decode.success(Person(name:, age:, children: children))
}

pub fn json_parse_test() {
  let lua =
    glua.new()
    |> dfm_lua.init()

  let person =
    Person(name: "John", age: 82, children: [
      Person(name: "Jacob", age: 42, children: []),
      Person(name: "Jane", age: 39, children: [
        Person(name: "Jack", age: 10, children: []),
      ]),
    ])

  let #(lua, str) =
    person |> person_to_json |> json.to_string |> glua.string(lua, _)

  let assert Ok(#(_lua, [res, _nil])) =
    glua.call_function_by_name(
      lua,
      ["dfm", "parse_json"],
      [str],
      using: decode.dynamic,
    )
  // TODO: Test this later, I am going to crash out if I keep doing this
  Nil
}

fn decode_pair_properties() {
  use pair_list <- decode.then(decode.list(decode_pair()))
  pair_list |> dynamic.properties |> decode.success
}

fn decode_pair() {
  use a <- decode.field(0, decode.dynamic)
  use b <- decode.field(1, decode.dynamic)
  decode.success(#(a, b))
}

// gleeunit test functions end in `_test`
pub fn hello_world_test() {
  let name = "Joe"
  let greeting = "Hello, " <> name <> "!"

  assert greeting == "Hello, Joe!"
}
