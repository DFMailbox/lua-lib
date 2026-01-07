import deser
import dfm_lua
import gleam/dict
import gleam/json
import gleeunit
import glua
import json_value

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
  use name <- deser.field(glua.string("name"), deser.string)
  use age <- deser.field(glua.string("age"), deser.int)

  use children <- deser.field(
    glua.string("children"),
    deser.list(person_decoder()),
  )
  deser.success(Person(name:, age:, children: children))
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

  let str = person |> person_to_json |> json.to_string |> glua.string

  let assert Ok(#(lua, [res])) =
    glua.call_function_by_name(lua, ["dfm", "parse_json"], [str])
  let assert Ok(res) = deser.run(lua, res, person_decoder())
  assert person == res
}

pub fn json_stringifiy_test() {
  let lua =
    glua.new()
    |> dfm_lua.init()
  let assert Ok(#(lua, [res])) =
    glua.eval(
      lua,
      "local list = dfm.make_list({}) 
      return dfm.stringify_json {key = list}",
    )
  let assert Ok(json) = deser.run(lua, res, deser.string)
  let assert Ok(json) = json_value.parse(json)
  assert json
    == json_value.Object([#("key", json_value.Array([]))] |> dict.from_list)
}
