require "bytecode"
require "dynarec"
require "vm"

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
	end]]
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
	local a = 6
	local b = 4
	local c = 2
	local m = (a+b+c)/3
	print(m)
	--[[local i = 1
	while i < 8 do
		print(i)
		i = i+1
	end]]
	--print("hai")
	--while ret_true() do
	--[[while true do
		print("RET TRUE!")
	end]]
end)
local bc = bytecode.load(sbc)

bytecode.dump(bc)
print("dynamic recomp below")

local dyncode = table.concat(
dynarec.compile(bc)
,"\n")

print(dyncode)
loadstring(dyncode)()
loadstring(sbc)()
vm.run(bc)
