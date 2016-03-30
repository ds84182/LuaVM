require "vm_accuracy_test_common"
local bytecode = require "luavm.bytecode"
local lua = require "luavm.vm".native()

for test in iterateTests() do
	if test:sub(-4,-1) == ".lua" then
		local f,a,r = getTest(test)
		local cr = {lua.run(bytecode.load(string.dump(f)),a)}
		assert(match(cr,r), test.." failed")
		print(test.." suceeded")
	end
end
