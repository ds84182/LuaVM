require "luavm.bytecode"
require "luavm.vm51"

local bc = bytecode.load(string.dump(function()
	local r = math.random()
	if r < 0.5 then
		return 1, 2, 3
	else
		return 6, 7, 8
	end
end))

bytecode.dump(bc)

local c = 0
for i=1, 3 do
	c = bytecode.lua51.patcher.find(bc, c, bytecode.instructions.LOADK)
end

bytecode.lua51.patcher.insert(bc, c+1, bytecode.encode("LOADK", 4, bytecode.patcher.addConstant(bc, 4)))
bytecode.lua51.patcher.insert(bc, c+2, bytecode.encode("LOADK", 5, bytecode.patcher.addConstant(bc, 5)))
bc.maxStack = bc.maxStack+2
bytecode.lua51.patcher.replace(bc, c+3, bytecode.encode("RETURN", 1, 6, 0))

bytecode.dump(bc)

print(assert(loadstring(bytecode.save(bc)))())
