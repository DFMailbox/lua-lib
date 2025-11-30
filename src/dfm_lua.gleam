import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/result
import glua
import json_value

pub fn main() -> Nil {
  let lua = glua.new() |> init()
  Nil
}

fn parse_json(lua: glua.Lua) {
  let #(lua, nil) = glua.nil(lua)
  glua.function(lua, fn(lua, args) {
    let result = case args {
      [str, ..] -> {
        use str <- result.try(
          decode.run(str, decode.string)
          |> result.replace_error("Argument is not string"),
        )
        use val <- result.try(
          json_value.parse(str) |> result.replace_error("Parse error"),
        )
        json_value_to_lua(lua, val) |> Ok
      }
      [] -> {
        Error("No string passed in")
      }
    }
    case result {
      Ok(#(lua, res)) -> {
        #(lua, [res, nil])
      }
      Error(str) -> {
        let #(lua, err) = glua.string(lua, str)
        #(lua, [nil, err])
      }
    }
  })
}

fn json_value_to_lua(lua: glua.Lua, val: json_value.JsonValue) {
  case val {
    json_value.Object(obj) ->
      glua.table(lua, #(glua.string, json_value_to_lua), dict.to_list(obj))

    json_value.Array(arr) -> {
      glua.table(
        lua,
        #(glua.int, json_value_to_lua),
        list.map_fold(arr, 1, fn(acc, it) { #(acc + 1, #(acc, it)) }).1,
      )
    }

    json_value.Bool(bool) -> glua.bool(lua, bool)
    json_value.Float(float) -> glua.float(lua, float)
    json_value.Int(int) -> glua.int(lua, int)
    json_value.String(str) -> glua.string(lua, str)
    json_value.Null -> glua.nil(lua)
  }
}

pub fn init(state lua: glua.Lua) -> glua.Lua {
  let #(lua, parse_json) = parse_json(lua)
  let assert Ok(lua) = glua.set(lua, ["dfm", "parse_json"], parse_json)
  // let #(lua, proxy) = make_immutable(lua, table)
  lua
}

fn lua_identity(lua: glua.Lua, value: glua.Value) {
  #(lua, value)
}

pub fn make_immutable(
  lua: glua.Lua,
  table: glua.Value,
) -> #(glua.Lua, glua.Value) {
  let #(lua, modify_table_error) =
    glua.function(lua, fn(lua, _args) {
      let #(lua, read_only_str) =
        glua.string(lua, "Attempt to modify read-only table")
      let assert Ok(#(lua, _)) =
        glua.call_function_by_name(
          lua,
          ["error"],
          [read_only_str],
          decode.dynamic,
        )
      #(lua, [])
    })

  let #(lua, lua_false) = glua.bool(lua, False)
  let #(lua, metatable) =
    glua.table(lua, #(glua.string, lua_identity), [
      #("__index", table),
      #("__newindex", modify_table_error),
      #("__metatable", lua_false),
    ])

  let #(lua, proxy) = glua.table(lua, #(glua.string, glua.string), [])
  let assert Ok(#(lua, _)) =
    glua.ref_call_function_by_name(state: lua, keys: ["setmetatable"], args: [
      proxy,
      metatable,
    ])
  #(lua, proxy)
}
