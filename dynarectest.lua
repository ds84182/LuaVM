require "luavm.bytecode"
require "luavm.dynarec"
require "luavm.vm51"

function ret_true()
	return true
end

local sbc = string.dump(function(...)
	--local a = b and 5 or 6
	--[[local a
	if b then
		a = 5
		b = 8
	elseif not a then
		a = 6
	elseif c then
		a = 3
	else
		a = 9
	end
	print(a,b)]]
	--[[local a
	if b then
		a = 5
		if not a then
			a = 6
		end
	end]]
	--[[local a
	while one do
		a = 6
	end]]
	--[[local a = 6
	local b = 4
	local c = 2
	local m = (a+b+c)/3
	print(m)
	while not m do
	
	end]]
	--[[local i = 1
	while i < 8 do
		print(i)
		i = i+1
	end]]
	--print("hai")
	--[[while ret_true() do
		--print("RET TRUE!")
		while true do
			local i = 1
			while i < 8 do
				if i%2 == 0 then
					print(i, "is even")
				else
					print(i, "is odd")
				end
				i = i+1
			end
		end
	end]]
	--[[for i=1, 10 do
		print(i)
	end]]
	for i, v in pairs(table) do
		print(i,v)
	end
end)
local bc = bytecode.load(sbc)

bytecode.dump(bc)
print("dynamic recomp below")

local dyncode = table.concat(
dynarec.compile(bc)
,"\n")

print(dyncode)
--loadstring(dyncode)()
--loadstring(sbc)()
--vm.run(bc)
