local bytecode = require "luavm.bytecode"
require "luavm.decompiler"

local function func()
	--print("Hello!")
	--local five = getfive()
	--local isfive = five == 5
	--[[if isfive and five == 5 then
		print("It equals five!")
	end]]
	
	--[[local a = 6
	if a == 6 then
		print("a == 6")
	elseif a == 5 then
		print("a == 5")
	else
		print("a ~= 6")
	end
	
	while a > 0 do
		print(a)
		a = a-1
		if a == 3 then
			break
		end
	end]]
	
	--[[for i=1, 10 do
		print(i*8)
	end]]
	
	--io.write("test\n")
	
	--multiplication tables
	for i=1, 12 do
		for j=1, 12 do
			io.write((i*j).." ")
		end
		io.write("\n")
	end
	
	--[[for i, v in pairs(_G) do
		print(i, v)
	end]]
end

local bc = bytecode.load(string.dump(func))
bytecode.dump(bc)
local syntaxrep = decompiler.decompile(bc)

local source = decompiler.constructSyntax(syntaxrep,"pretty")

print(source)

--func()
--loadstring(source)()
