local function assert_safe_modname(name)
	if type(name) ~= "string" then
		error("module name must be a string", 3)
	end

	local n = #name
	if n == 0 then
		error("invalid module name", 3)
	end

	-- Disallow leading/trailing dot
	if name:byte(1) == 46 or name:byte(n) == 46 then -- 46 == '.'
		error("invalid module name", 3)
	end

	local prev_dot = false

	for i = 1, n do
		local b = name:byte(i)

		-- Disallow NUL and obvious path / scheme separators
		if b == 0 or b == 47 or b == 92 or b == 58 then -- \0, '/', '\', ':'
			error("invalid module name", 3)
		end

		if b == 46 then -- '.'
			-- Disallow empty segments / consecutive dots
			if prev_dot then
				error("invalid module name", 3)
			end
			prev_dot = true
		else
			prev_dot = false

			-- Allow only ASCII letters, digits, underscore
			local is_digit = (b >= 48 and b <= 57)
			local is_upper = (b >= 65 and b <= 90)
			local is_lower = (b >= 97 and b <= 122)
			local is_underscore = (b == 95)

			if not (is_digit or is_upper or is_lower or is_underscore) then
				error("invalid module name", 3)
			end
		end
	end

	return name
end
-- m eprint
-- m print
-- m require
-- m package = {
-- m   config
-- m   preload
-- m   searchers = {
-- m     [1] = <function:function: luerl_lib_package:preload_searcher>,
-- m     [2] = <function:function: luerl_lib_package:lua_searcher>,
-- m   },
-- m   searchpath
-- m },
local loadfile = _G.loadfile

return function(usr_root, lib_root)
	do
		local DIRSEP = package.config:sub(1, 1)

		local list = {
			usr_root .. DIRSEP .. "?.lua",
			usr_root .. DIRSEP .. "?" .. DIRSEP .. "init.lua",
			lib_root .. DIRSEP .. "?.lua",
			lib_root .. DIRSEP .. "?" .. DIRSEP .. "init.lua",
		}
		package.path = table.concat(list, ";")

		-- Module name validator

		local preload_searcher = package.searchers[1] -- the preload searcher

		local function lua_file_searcher(modname)
			assert_safe_modname(modname)

			local filename, err = package.searchpath(modname, package.path)
			if not filename then
				return "\n\t" .. err
			end

			local chunk, loaderr = loadfile(filename, "t", _ENV)
			if not chunk then
				error(loaderr, 2)
			end
			return chunk, filename
		end

		package.searchers = { preload_searcher, lua_file_searcher }

		local real_require = require
		function require(name)
			return real_require(name)
		end

		local real_package = package
		package = setmetatable({}, {
			__index = real_package,
			__newindex = function()
				error("package is read-only", 2)
			end,
		})
	end
end
