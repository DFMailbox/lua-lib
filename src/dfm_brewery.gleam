import brewery/lib
import deser
import filepath
import gleam/erlang/application
import gleam/list
import gleam/result
import glua.{type Lua}
import json_value

// pub fn main() {
// todo as "implement cli"
// }

pub type DfmActor {
  DfmActor(
    /// Do not mutate this
    lua: Lua,
    state: json_value.JsonValue,
    router: glua.Function,
    /// A helper function to mark something as a list
    context: lib.Context,
  )
}

pub type MailboxMessage {
  MailboxMessage(
    data: String,
    timestamp: Int,
    from: Int,
    to_plot_id: Int,
    to_mailbox_id: String,
  )
}

pub type RouteDecision {
  RouteDecision(response: json_value.JsonValue, send: List(DirectMessage))
}

pub type DirectMessage {
  DirectMessage(data: String, mailbox_id: String)
}

pub type ActorError {
  LuaError(glua.LuaError)
  SchemaError(List(deser.DeserializeError))
}

pub fn route_message(
  actor: DfmActor,
  message: MailboxMessage,
) -> Result(#(RouteDecision, json_value.JsonValue), ActorError) {
  let #(lua, msg) =
    glua.table(actor.lua, [
      #(glua.string("data"), glua.string(message.data)),
      #(glua.string("timestamp"), glua.int(message.timestamp)),
      #(glua.string("from"), glua.int(message.from)),
      #(glua.string("to"), glua.int(message.to_plot_id)),
      #(glua.string("to_mailbox"), glua.string(message.to_mailbox_id)),
    ])
  let #(lua, state) = lib.json_value_to_lua(lua, actor.state, actor.context)
  use #(lua, res) <- result.try(
    glua.call_function(lua, actor.router, [msg, state])
    |> result.map_error(LuaError),
  )
  use out <- result.try(
    deser.run_multi(lua, res, {
      use decision <- deser.item(1, {
        use response <- deser.field(
          glua.string("res"),
          lib.serialize(actor.context),
        )
        use send <- deser.optional_field(
          glua.string("send_to"),
          [],
          deser.list({
            use data <- deser.field(glua.string("data"), deser.string)
            use mailbox_id <- deser.field(glua.string("mailbox"), deser.string)
            deser.success(DirectMessage(data:, mailbox_id:))
          }),
        )
        deser.success(RouteDecision(response:, send:))
      })
      use new_state <- deser.item(2, lib.serialize(actor.context))
      deser.success(#(decision, new_state))
    })
    |> result.map_error(SchemaError),
  )
  Ok(out)
}

pub fn initialize_actor(
  user_dir: String,
  initial: json_value.JsonValue,
) -> Result(DfmActor, ActorError) {
  // TODO: DO something about this
  let assert Ok(priv) = application.priv_directory("dfm_brewery")
  let #(lua, context) = init(priv, user_dir)

  use #(lua, res) <- result.try(
    glua.eval_file(lua, filepath.join(user_dir, "init.lua"))
    |> result.map_error(LuaError),
  )
  let deserializer = {
    use router <- deser.item(1, deser.function)
    deser.success(DfmActor(lua:, state: initial, router:, context:))
  }
  use actor <- result.try(
    deser.run_multi(lua, res, deserializer) |> result.map_error(SchemaError),
  )
  Ok(actor)
}

pub fn init(priv: String, user_dir: String) -> #(Lua, lib.Context) {
  let lua = glua.new()
  let #(lua, util, context) = lib.util_lib(lua)
  let assert Ok(lua) = glua.set(lua, ["package", "loaded", "lib.util"], util)
  let lua = sandbox_script(lua, priv, user_dir)
  let assert Ok(lua) = sandbox(lua)
  #(lua, context)
}

fn sandbox_script(lua: Lua, priv: String, user_dir: String) -> Lua {
  let script = filepath.join(priv, "sandbox.lua")
  let assert Ok(#(lua, [func])) = glua.eval_file(lua, script)
  let assert Ok(func) = deser.run(lua, func, deser.function)
  let lib_dir = filepath.join(priv, "dfm_library")
  let assert Ok(#(lua, _)) =
    glua.call_function(lua, func, [glua.string(user_dir), glua.string(lib_dir)])
  lua
}

fn sandbox(lua: Lua) -> Result(Lua, glua.LuaError) {
  let keys = [
    ["collectgarbage"],
    ["dofile"],
    ["loadfile"],
    ["loadstring"],
    ["debug", "getmetatable"],
    ["debug", "getuservalue"],
    ["debug", "setmetatable"],
    ["debug", "setuservalue"],
    ["io", "flush"],
    ["io", "write"],
    ["os", "execute"],
    ["os", "exit"],
    ["os", "getenv"],
    ["os", "remove"],
    ["os", "rename"],
    ["os", "tmpname"],
  ]
  list.try_fold(keys, lua, glua.sandbox)
}
