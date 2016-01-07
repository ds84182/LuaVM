require "vm_accuracy_test_common"
local vmversion = _VERSION:gsub("%D","")
require "luavm.bytecode"
require("luavm.vm"..vmversion)
local lua = vm["lua"..vmversion]

for test in iterateTests() do
	if test:sub(-4,-1) == ".lua" then
		local f,a,r = getTest(test)
		local cr = {lua.run(bytecode.load(string.dump(f)),a)}
		assert(match(cr,r), test.." failed")
		print(test.." suceeded")
	end
end
