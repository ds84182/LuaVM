require "luavm.bytecode"

local code = "local x = 0 repeat print(x) x = x+1 until x > 100"
local lines = {}
for line in code:gmatch("[^\n]*") do
	lines[#lines+1] = line
end

local d = string.dump((loadstring or load)(code))
local bc = bytecode.load(d)

bytecode.dump(bc)

local nd = bytecode.save(bc)
print(nd == d)
print(#nd, #d)

--io.open("hai.luac","wb"):write(d)
io.open("hai.new.luac","wb"):write(nd)
