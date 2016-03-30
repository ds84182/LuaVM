-- Decoder: Takes Lua bytecode and returns a version independent immediate representation --

-- For example:
-- LOADK R1, K0 ["hello"] ->
-- {op = "set", src = {{"constant", 0}}, dest = {{"register", 1}}}

-- Decoders have a context. A decoder context will keep track of  things related to loops.

local pkgname = ...

local decoder = {}

function decoder.get(version)
	return require(pkgname..version)(decoder)
end

function decoder.native()
	local major, minor = _VERSION:match("Lua (%d)%.(%d)")

	return decoder.get(major..minor)
end

return decoder
