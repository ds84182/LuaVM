function getTest(name)
	local func,args,ret = dofile("vm_accuracy_test/"..name)
	return func,args,ret
end

function match(currentRet,ret)
	for i, v in pairs(currentRet) do
		if type(v) == type(ret[i]) and v ~= ret[i] then
			if type(v) == "table" then
				local s = match(v,ret[i])
				if not s then return false end
			else
				return false
			end
		end
	end
	
	for i, v in pairs(ret) do
		if type(v) == type(currentRet[i]) and v ~= currentRet[i] then
			if type(v) == "table" then
				local s = match(currentRet[i],v)
				if not s then return false end
			else
				return false
			end
		end
	end
	
	return true
end

function iterateTests()
	local lfs = require "lfs"
	return lfs.dir("vm_accuracy_test")
end
