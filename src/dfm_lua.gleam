import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/pair
import gleam/result
import glua
import json_value

pub fn main() -> Nil {
  let lua = glua.new() |> init()
  let assert Ok(res) =
    glua.eval(
      lua,
      "return dfm.stringify_json {[dfm.empty_list()] = dfm.empty_list()}",
    )
    |> glua.dec(decode.dynamic)
  echo res.1
  Nil
}

fn parse_json() {
  let nil = glua.nil()
  glua.function(fn(lua, args) {
    let result = case args {
      [str, ..] -> {
        use str <- result.try(
          decode.run(str, decode.string)
          |> result.replace_error("ArgType"),
        )
        use val <- result.try(
          json_value.parse(str) |> result.replace_error("ParseError"),
        )
        json_value_to_lua(val) |> Ok
      }
      [] -> {
        Error("NoArgs")
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

fn serialize_json() {
  glua.function(fn(lua, args) {
    let result = case args {
      [it, ..] -> {
        use json <- result.try(
          decode.run(it, serialize())
          |> result.replace_error("InvalidData"),
        )
        json_value.to_string(json)
        |> glua.string
        |> Ok
      }
      [] -> {
        Error("NoArgs")
      }
    }
    case result {
      Ok(res) -> {
        #(lua, [res, glua.nil()])
      }
      Error(str) -> {
        #(lua, [glua.nil(), glua.string(str)])
      }
    }
  })
}

@external(erlang, "gleam@function", "identity")
fn coerce_dyn(a: anything) -> dynamic.Dynamic

fn serialize() {
  decode.one_of(decode.string |> decode.map(json_value.String), [
    decode.bool |> decode.map(json_value.Bool),
    decode.int |> decode.map(json_value.Int),
    decode.float |> decode.map(json_value.Float),
    decode.dict(decode.string, decode.recursive(serialize))
      |> decode.map(json_value.Object),
    glua.decode_table_list(decode.recursive(serialize))
      |> decode.map(json_value.Array),
    decode.optional(decode.int) |> decode.map(fn(_) { json_value.Null }),
    {
      use then <- decode.then(decode.dynamic)
      case then == coerce_dyn(empty_list_data()) {
        True -> decode.success(json_value.Array([]))
        False -> decode.failure(json_value.Null, "Empty list")
      }
    },
  ])
}

type EmptyList {
  EmptyList(id: Int)
}

/// An empty list
/// Contains random bytes to discourage manual construction
const raw_empty_list = EmptyList(0xb150c8b3e22d339b0661d1d03c2)

pub fn empty_list_data() {
  glua.userdata(raw_empty_list)
}

fn empty_list() {
  glua.function(fn(lua, _args) { #(lua, [empty_list_data()]) })
}

const api_version = "0.1.0"

pub fn init(state lua: glua.Lua) -> glua.Lua {
  let table =
    glua.table(
      [
        #("parse_json", parse_json()),
        #("stringify_json", serialize_json()),
        #("implementation", glua.string("gleam")),
        #("version", glua.string(api_version)),
        #("empty_list", empty_list()),
      ]
      |> list.map(pair.map_first(_, glua.string)),
    )

  let assert Ok(lua) = glua.set(lua, ["dfm"], table)
  lua
}
