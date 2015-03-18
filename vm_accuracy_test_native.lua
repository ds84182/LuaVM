require "vm_accuracy_test_common"

for test in iterateTests() do
	if test:sub(-4,-1) == ".lua" then
		local f,a,r = getTest(test)
		local cr = {f(unpack(a))}
		assert(match(cr,r), test.." failed")
		print(test.." suceeded")
	end
end
