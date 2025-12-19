import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/pair
import gleam/result
import glua
import json_value

pub fn main() -> Nil {
  let lua = glua.new() |> init()
  let assert Ok(#(_lua, res)) =
    glua.eval(lua, "return dfm.implementation", decode.dynamic)
  echo res
  Nil
}

fn parse_json() {
  let nil = glua.nil()
  glua.function(fn(lua, args) {
    let result = case args {
      [str, ..] -> {
        use str <- result.try(
          decode.run(str, decode.string)
          |> result.replace_error("Argument is not string"),
        )
        use val <- result.try(
          json_value.parse(str) |> result.replace_error("Parse error"),
        )
        json_value_to_lua(val) |> Ok
      }
      [] -> {
        Error("No string passed in")
      }
    }
    case result {
      Ok(res) -> {
        #(lua, [res, nil])
      }
      Error(str) -> {
        #(lua, [nil, glua.string(str)])
      }
    }
  })
}

fn json_value_to_lua(val: json_value.JsonValue) {
  case val {
    json_value.Object(obj) ->
      dict.to_list(obj)
      |> list.map(fn(val) {
        let #(k, v) = val
        #(glua.string(k), json_value_to_lua(v))
      })
      |> glua.table()

    json_value.Array(arr) -> {
      list.map_fold(arr, 1, fn(acc, it) {
        #(acc + 1, #(glua.int(acc), json_value_to_lua(it)))
      }).1
      |> glua.table()
    }

    json_value.Bool(bool) -> glua.bool(bool)
    json_value.Float(float) -> glua.float(float)
    json_value.Int(int) -> glua.int(int)
    json_value.String(str) -> glua.string(str)
    json_value.Null -> glua.nil()
  }
}

const api_version = "0.1.0"

pub fn init(state lua: glua.Lua) -> glua.Lua {
  let impl = glua.string("gleam")
  let api_version = glua.string(api_version)
  let parse_json = parse_json()
  let table =
    glua.table(
      [
        #("parse_json", parse_json),
        #("implementation", impl),
        #("version", api_version),
      ]
      |> list.map(pair.map_first(_, glua.string)),
    )

  let assert Ok(lua) = glua.set(lua, ["dfm"], table)
  lua
}
