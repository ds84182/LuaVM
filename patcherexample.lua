require "luavm.bytecode"

function stalkUpvalues(func)
	local bc = bytecode.load(string.dump(func))
	
	local globals = setmetatable({},{__index=function(_,i)
		if type(i) == "string" and i:sub(1,10) == "__UPVALUE_" then
			return select(2,debug.getupvalue(func,i:sub(11)))
		else
			return _G[i]
		end
	end,__newindex=function(_,i,v)
		if i:sub(1,10) == "__UPVALUE_" then
			debug.setupvalue(func,i:sub(11),v)
		else
			_G[i] = v
		end
	end})
	
	--patch all GETUPVAL to GETGLOBAL--
	local ngg = 0
	while ngg do
		ngg = bytecode.patcher.find(bc, ngg, bytecode.instructions.GETUPVAL)
		if ngg then
			local _,a,b,c = bytecode.decode(bc.instructions[ngg])
			local const = bytecode.patcher.addConstant(bc, "__UPVALUE_"..(b+1))
			bytecode.patcher.replace(bc, ngg, bytecode.encode(bytecode.instructions.GETGLOBAL, a, const, 0))
		end
	end
	
	--patch all SETUPVAL to SETGLOBAL--
	local ngg = 0
	while ngg do
		ngg = bytecode.patcher.find(bc, ngg, bytecode.instructions.SETUPVAL)
		if ngg then
			local _,a,b,c = bytecode.decode(bc.instructions[ngg])
			local const = bytecode.patcher.addConstant(bc, "__UPVALUE_"..(b+1))
			bytecode.patcher.replace(bc, ngg, bytecode.encode(bytecode.instructions.SETGLOBAL, a, const, 0))
		end
	end
	
	bytecode.dump(bc)
	return setfenv(assert(loadstring(bytecode.save(bc), "=changed", "bt")), globals)
end

local a,b,c = 1,2,3
stalkUpvalues(function()
	print(a,b,c)
	a,b,c = 5,6,7
end)()

print(a,b,c)
