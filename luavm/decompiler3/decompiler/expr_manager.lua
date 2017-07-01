--[[
Expression Manager: Manages expressions.
]]

return function(decompiler)

local exprmgr = {}

decompiler.exprmgr = exprmgr

function exprmgr.findWriteBefore(block, reg, pc)
	for i=pc-1, 0, -1 do
		local instr = block.decoded[i]
		local details = decompiler.instr.getRegisterDetails(instr)
		if details.write[reg] then
			-- TODO: Inline checks, like multiple usage and etc
			return i
		end
	end
	return nil
end

function exprmgr.tryVisitReg(block, reg, pc)
	local wpc = exprmgr.findWriteBefore(block, reg, pc)

	if wpc then
		return exprmgr.visit(block, wpc)
	else
		return {"local", reg = reg}
	end
end

-- TODO: This might be the wrong way to do this... we should have a different system for doing this.

--[[
The main problem with this system was that we iteratively generate expressions based off what we see at an earlier expression.

This is stupid.

Instead, we should generate each expression part in a linked list structure
with parent child relations. Then just collapse expressions into other expressions.

Also the structure would look like the structure of the resulting source code.
]]

function exprmgr.visit(block, pc)
	-- Visit the expression at pc in the given block (block relative pc)
	local instr = block.decoded[pc]
	local typ = instr[1]

	if typ == "condop" then
		local subtyp = instr[2]

		if subtyp == "test" then
			return {
				"condop", "test",
				invert = instr.invert,
				target = exprmgr.tryVisitReg(block, instr.target, pc)
			}
		else
			return {
				"condop", subtyp,
				invert = instr.invert,
				lhs = exprmgr.tryVisitReg(block, instr.lhs, pc),
				rhs = exprmgr.tryVisitReg(block, instr.rhs, pc)
			}
		end
	elseif typ == "binop" then
		return {
			"binop", instr[2],
			lhs = exprmgr.tryVisitReg(block, instr.lhs, pc),
			rhs = exprmgr.tryVisitReg(block, instr.rhs, pc)
		}
	elseif typ == "unop" then
		return {
			"unop", instr[2],
			rhs = exprmgr.tryVisitReg(block, instr.rhs, pc)
		}
	elseif typ == "getglobal" then
		return {"getglobal", index = {"constant", kst = instr.index}}
	elseif typ == "loadk" then
		return {"constant", kst = instr.kst}
	elseif typ == "move" then
		return {"local", reg = instr.src}
	elseif typ == "gettable" then
		return {
			"gettable",
			table = exprmgr.tryVisitReg(block, instr.table, pc),
			index = exprmgr.tryVisitReg(block, instr.index, pc)
		}
	elseif typ == "call" or typ == "tailcall" then
		local args = {}
		local self = false

		for i=instr.base, instr.base+instr.narg do
			local expr = exprmgr.tryVisitReg(block, i, pc)
			if expr[1] == "self" then
				self = true
			end
			args[#args+1] = expr
		end

		local func = table.remove(args, 1)

		if self then
			-- Remove the first argument from the function
			-- Otherwise the rendered code is invalid
			table.remove(args, 1)
		end

		return {typ, func = func, args = args}
	elseif typ == "self" then
		return {
			"self",
			object = exprmgr.tryVisitReg(block, instr.object, pc),
			method = exprmgr.tryVisitReg(block, instr.method, pc),
		}
	elseif typ == "closure" then
		return {
			"closure",
			proto = instr.proto,
			upvalues = instr.upvalues
		}
	elseif typ == "return" then
		local rets = {}
		for i=instr.base, instr.base+instr.count-1 do
			rets[#rets+1] = exprmgr.tryVisitReg(block, i, pc)
		end
		return {"return", rets = rets}
	end
end

end
