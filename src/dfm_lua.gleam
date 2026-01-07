import deser
import gleam/bool
import gleam/dict
import gleam/list
import gleam/pair
import gleam/result
import glua
import json_value

pub type DfmActor {
  DfmActor(
    initial: glua.Lua,
    state: json_value.JsonValue,
    router: glua.Function,
    commands: List(glua.Function),
  )
}

fn deser_error(lua, list) {
  #(lua, list.map(list, deser.error_to_string))
}

fn parse_json() {
  glua.function(fn(lua, args) {
    use str <- result.try(
      deser.run_list(lua, args, deser.at([glua.int(1)], deser.string))
      |> result.map_error(deser_error(lua, _)),
    )
    use val <- result.try(
      json_value.parse(str) |> result.replace_error(#(lua, ["ParseError"])),
    )
    let #(lua, val) = json_value_to_lua(lua, val)
    Ok(#(lua, [val]))
  })
  |> glua.func_to_val
}

fn json_value_to_lua(
  lua: glua.Lua,
  val: json_value.JsonValue,
) -> #(glua.Lua, glua.Value) {
  case val {
    json_value.Object(obj) -> {
      let #(lua, tbl) =
        dict.to_list(obj)
        |> list.map_fold(lua, fn(lua, pair) {
          let #(lua, val) = json_value_to_lua(lua, pair.1)
          #(lua, #(glua.string(pair.0), val))
        })
      glua.table(lua, tbl)
    }

    json_value.Array(arr) -> {
      let #(lua, arr) =
        list.map_fold(arr, lua, fn(lua, it) { json_value_to_lua(lua, it) })
      glua.table_list(lua, arr)
    }

    json_value.Bool(bool) -> #(lua, glua.bool(bool))
    json_value.Float(float) -> #(lua, glua.float(float))
    json_value.Int(int) -> #(lua, glua.int(int))
    json_value.String(str) -> #(lua, glua.string(str))
    json_value.Null -> #(lua, glua.nil())
  }
}

fn serialize_json() {
  glua.function(fn(lua, args) {
    use json <- result.try(
      deser.run_list(lua, args, deser.at([glua.int(1)], serialize()))
      |> result.map_error(deser_error(lua, _)),
    )
    let str =
      json_value.to_string(json)
      |> glua.string()

    #(lua, [str]) |> Ok
  })
  |> glua.func_to_val
}

fn serialize() {
  deser.one_of(deser.string |> deser.map(json_value.String), [
    deser.bool |> deser.map(json_value.Bool),
    deser.int |> deser.map(json_value.Int),
    deser.number |> deser.map(json_value.Float),
    deser.optional(deser.int) |> deser.map(fn(_) { json_value.Null }),
    {
      use lua, table <- deser.then(deser.raw)

      case glua.call_function_by_name(lua, ["_G", "getmetatable"], [table]) {
        Ok(#(lua, [metatable])) -> {
          let is_list =
            deser.run(
              lua,
              metatable,
              deser.at([glua.string("dfm_list")], deser.bool),
            )
            |> result.unwrap(False)

          use <- bool.guard(
            !is_list,
            deser.failure(json_value.Null, "Empty List"),
          )
          deser.success(json_value.Array([]))
        }
        _ -> deser.failure(json_value.Null, "Empty list")
      }
    },
    deser.list(deser.recursive(serialize))
      |> deser.map(json_value.Array),
    deser.dict(deser.string, deser.recursive(serialize))
      |> deser.map(json_value.Object),
  ])
}

fn empty_list() {
  glua.function(fn(lua, args) {
    let raw_decoder = {
      use _lua, list <- deser.then(deser.raw)
      case deser.classify(list) {
        "Table" -> deser.success(list)
        _ -> deser.failure(list, "Table")
      }
    }
    use table <- result.try(
      deser.run_list(lua, args, deser.at([glua.int(1)], raw_decoder))
      |> result.map_error(deser_error(lua, _)),
    )
    let #(lua, metatable) =
      glua.table(lua, [#(glua.string("dfm_list"), glua.bool(True))])
    use #(lua, _table) <- result.try(
      glua.call_function_by_name(lua, ["setmetatable"], [table, metatable])
      |> result.replace_error(#(lua, ["setmetatable failed"])),
    )
    Ok(#(lua, [table]))
  })
  |> glua.func_to_val
}

const api_version = "0.1.0"

pub fn init(state lua: glua.Lua) -> glua.Lua {
  let #(lua, table) =
    glua.table(
      lua,
      [
        #("parse_json", parse_json()),
        #("stringify_json", serialize_json()),
        #("implementation", glua.string("gleam")),
        #("version", glua.string(api_version)),
        #("make_list", empty_list()),
      ]
        |> list.map(pair.map_first(_, glua.string)),
    )

  let assert Ok(lua) = glua.set(lua, ["dfm"], table)
  lua
}
