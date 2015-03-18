require "luavm.bytecode"

function _HOOK()
	print("Hook")
end

function addHook(func)
	local bc = bytecode.load(string.dump(func))
	bytecode.dump(bc)
	
	local tempReg = bc.maxStack
	bc.maxStack = bc.maxStack+1
	local hookConstant = bytecode.patcher.addConstant(bc, "_HOOK")
	
	local get = bytecode.encode(bytecode.instructions.GETGLOBAL, tempReg, hookConstant)
	local call = bytecode.encode(bytecode.instructions.CALL, tempReg, 1, 1)
	
	local function tryAddHookAt(pc)
		bytecode.patcher.insert(bc,pc,get)
		bytecode.patcher.insert(bc,pc+1,call)
	end
	
	local pc = 0
	local rpc = 0
	local ninst = #bc.instructions
	while rpc < ninst do
		local s,e = pcall(tryAddHookAt,pc)
		pc = pc+3
		rpc = rpc+1
	end
	
	--patch all JMP 0 -1--
	--this fixes a problem where "while true do end" could not be patched--
	local ngg = 0
	while ngg do
		ngg = bytecode.patcher.find(bc, ngg, bytecode.instructions.JMP)
		if ngg then
			local _,a,b,c = bytecode.decode(bc.instructions[ngg])
			if b == -1 then
				bytecode.patcher.insert(bc,ngg,get)
				bytecode.patcher.insert(bc,ngg+1,call)
				bytecode.patcher.replace(bc, ngg+2, bytecode.encode(bytecode.instructions.JMP, 0, -2, 0))
				ngg = ngg+2
			end
		end
	end
	
	bytecode.dump(bc)
	return assert(loadstring(bytecode.save(bc), "=changed", "bt"))
end

addHook(function()
	local a,b,c = 1,2,3
	print(a,b,c)
	while true do
		print("HI")
		break
	end
end)()
