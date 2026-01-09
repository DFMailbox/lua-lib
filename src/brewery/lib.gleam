import deser
import gleam/bool
import gleam/dict
import gleam/list
import gleam/pair
import gleam/result
import glua
import json_value

fn deser_error(lua, list) {
  #(lua, list.map(list, deser.error_to_string))
}

fn parse_json(context: Context) {
  glua.function(fn(lua, args) {
    use str <- result.try(
      deser.run_multi(lua, args, {
        use str <- deser.item(1, deser.string)
        deser.success(str)
      })
      |> result.map_error(deser_error(lua, _)),
    )
    use val <- result.try(
      json_value.parse(str) |> result.replace_error(#(lua, ["ParseError"])),
    )
    let #(lua, val) = json_value_to_lua(lua, val, context)
    Ok(#(lua, [val]))
  })
  |> glua.func_to_val
}

pub fn json_value_to_lua(
  lua: glua.Lua,
  val: json_value.JsonValue,
  context: Context,
) -> #(glua.Lua, glua.Value) {
  case val {
    json_value.Object(obj) -> {
      let #(lua, tbl) =
        dict.to_list(obj)
        |> list.map_fold(lua, fn(lua, pair) {
          let #(lua, val) = json_value_to_lua(lua, pair.1, context)
          #(lua, #(glua.string(pair.0), val))
        })
      glua.table(lua, tbl)
    }

    json_value.Array(arr) -> {
      let #(lua, arr) =
        list.map_fold(arr, lua, fn(lua, it) {
          json_value_to_lua(lua, it, context)
        })
      let #(lua, arr) = glua.table_list(lua, arr)
      let assert Ok(#(lua, [arr])) =
        glua.call_function(lua, context.make_list, [arr])
      #(lua, arr)
    }

    json_value.Bool(bool) -> #(lua, glua.bool(bool))
    json_value.Float(float) -> #(lua, glua.float(float))
    json_value.Int(int) -> #(lua, glua.int(int))
    json_value.String(str) -> #(lua, glua.string(str))
    json_value.Null -> #(lua, glua.nil())
  }
}

fn serialize_json(context: Context) {
  glua.function(fn(lua, args) {
    use json <- result.try(
      deser.run_multi(lua, args, {
        use json <- deser.item(1, serialize(context))
        deser.success(json)
      })
      |> result.map_error(deser_error(lua, _)),
    )
    let str =
      json_value.to_string(json)
      |> glua.string()

    #(lua, [str]) |> Ok
  })
  |> glua.func_to_val
}

pub fn serialize(context: Context) {
  deser.one_of(deser.string |> deser.map(json_value.String), [
    deser.bool |> deser.map(json_value.Bool),
    deser.int |> deser.map(json_value.Int),
    deser.number |> deser.map(json_value.Float),
    deser.optional(deser.int) |> deser.map(fn(_) { json_value.Null }),
    {
      use lua, table <- deser.then(deser.raw)

      case glua.call_function(lua, context.getmetatable, [table]) {
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
    deser.dict(deser.string, deser.recursive(fn() { serialize(context) }))
      |> deser.map(json_value.Object),
  ])
}

fn empty_list(setmetatable: glua.Function) {
  glua.function(fn(lua, args) {
    let raw_decoder = {
      use _lua, list <- deser.then(deser.raw)
      case deser.classify(list) {
        "Table" -> deser.success(list)
        _ -> deser.failure(list, "Table")
      }
    }
    use table <- result.try(
      deser.run_multi(lua, args, {
        use raw <- deser.item(1, raw_decoder)
        deser.success(raw)
      })
      |> result.map_error(deser_error(lua, _)),
    )
    let #(lua, metatable) =
      glua.table(lua, [#(glua.string("dfm_list"), glua.bool(True))])
    let assert Ok(#(lua, _table)) =
      glua.call_function(lua, setmetatable, [table, metatable])
    Ok(#(lua, [table]))
  })
}

const api_version = "0.1.0"

pub fn util_lib(lua: glua.Lua) -> #(glua.Lua, glua.Value, Context) {
  let context = {
    let assert Ok(setmetatable) = glua.get(lua, ["setmetatable"])
    let assert Ok(setmetatable) = deser.run(lua, setmetatable, deser.function)
    let assert Ok(getmetatable) = glua.get(lua, ["getmetatable"])
    let assert Ok(getmetatable) = deser.run(lua, getmetatable, deser.function)
    let make_list = empty_list(setmetatable)
    Context(make_list:, setmetatable:, getmetatable:)
  }
  let #(lua, table) =
    glua.table(
      lua,
      [
        #("version", glua.string(api_version)),
        #("make_list", glua.func_to_val(context.make_list)),
        #("parse_json", parse_json(context)),
        #("stringify_json", serialize_json(context)),
      ]
        |> list.map(pair.map_first(_, glua.string)),
    )
  #(lua, table, context)
}

pub type Context {
  Context(
    make_list: glua.Function,
    setmetatable: glua.Function,
    getmetatable: glua.Function,
  )
}
