require "bytecode"
require "vm"

function pass(...)
	return ...
end

print(vm.run(bytecode.load(string.dump(function(...)
	print(...)
	local r,e = 4,4
	local a, b, c = pass(1,2,3)
	print(a,b,c)
	print(unpack({4,6,2,4}))
	local function t()
		r = 5
		e = 6
	end
	t()
	print(r,e)
	local i = 1
	while true do
		local m = math.random(1,100)
		print("iter "..i,m)
		if m < 15 then
			break
		end
		i = i+1
	end
	return false and 1 or 0
end)),{"h","i",3,4,5}))

local testbc = string.dump(function() return "Hello" end)
local testbcl = bytecode.load(testbc)
local testbco = bytecode.save(testbcl)
assert(testbc == testbco,"Bytecode save test failed, INCONSISTENT!")
print(vm.run(testbcl))
print(loadstring(testbc)())
print(loadstring(testbco)())

loadfile("hello.lua")()
vm.run(bytecode.load(string.dump(loadfile("hello.lua"))))

local opscalled = 0
vm.run(
	bytecode.load(string.dump(function() while true do end end)),
	nil,
	nil,
	nil,
	function() opscalled = opscalled+1 if opscalled > 480000 then error("Timeout.",0) end end)
