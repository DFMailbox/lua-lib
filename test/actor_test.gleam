import dfm_brewery
import gleam/dict
import json_value

pub fn default_actor_test() {
  let state = json_value.Object(dict.new())
  let assert Ok(actor) =
    dfm_brewery.initialize_actor("./test/actor/default", state)
  let assert Ok(#(decision, new_state)) =
    dfm_brewery.route_message(
      actor,
      dfm_brewery.MailboxMessage(
        data: "hello world",
        timestamp: 42,
        from: 1,
        to_plot_id: 2,
        to_mailbox_id: "main",
      ),
    )
  assert state == new_state
  assert decision
    == dfm_brewery.RouteDecision(
      json_value.Object(
        dict.from_list([
          #("type", json_value.String("success")),
        ]),
      ),
      send: [dfm_brewery.DirectMessage("hello world", "main")],
    )
}
