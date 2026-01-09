local res = require("lib.response")
local decide = require("lib.decision")
local send = require("lib.send")
local util = require("lib.util")

if util.version ~= "0.1.0" then
	error("Unexpected library version")
end

---@type Router
local router = function(msg, state)
	local mailboxes = {
		main = function()
			return decide(res.success(), { send(msg.data, "main") })
		end,
		chat = function()
			if msg.from ~= 4242 then
				return decide(res.whitelist_error())
			end
			return decide(res.success())
		end,
	}
	local handler
	if msg.to_mailbox then
		local got = mailboxes[msg.to_mailbox]
		if got then
			handler = got
		else
			return decide(res.mailbox_not_found_error({ "main", "chat" })), state
		end
	else
		handler = mailboxes.main
	end
	return handler(), state
end
return router
