return function(bytecode)
	local impl = {}
	
	local debug = bytecode.printDebug
	local bit = bytecode.bit
	
	-- instruction definitions
	
	local instructionNames = {
		[0]="MOVE","LOADK","LOADBOOL","LOADNIL",
		"GETUPVAL","GETGLOBAL","GETTABLE",
		"SETGLOBAL","SETUPVAL","SETTABLE","NEWTABLE",
		"SELF","ADD","SUB","MUL","DIV","MOD","POW","UNM","NOT","LEN","CONCAT",
		"JMP","EQ","LT","LE","TEST","TESTSET","CALL","TAILCALL","RETURN",
		"FORLOOP","FORPREP","TFORLOOP","SETLIST","CLOSE","CLOSURE","VARARG"
	}
	
	local iABC = 0
	local iABx = 1
	local iAsBx = 2

	local instructionFormats = {
		[0]=iABC,iABx,iABC,iABC,
		iABC,iABx,iABC,
		iABx,iABC,iABC,iABC,
		iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iAsBx,iABC,iABC,iABC,iABx,iABC
	}

	local ins = {}
	for i, v in pairs(instructionNames) do ins[v] = i end

	impl.instructionNames = instructionNames
	impl.instructions = ins
	impl.defaultReturn = 8388638 --Default return instruction, this is the extra return found at the end of instruction streams

	-- instruction constants
	
	local MOVE = 0
	local LOADK = 1
	local LOADBOOL = 2
	local LOADNIL = 3
	local GETUPVAL = 4
	local GETGLOBAL = 5
	local GETTABLE = 6
	local SETGLOBAL = 7
	local SETUPVAL = 8
	local SETTABLE = 9
	local NEWTABLE = 10
	local SELF = 11
	local ADD = 12
	local SUB = 13
	local MUL = 14
	local DIV = 15
	local MOD = 16
	local POW = 17
	local UNM = 18
	local NOT = 19
	local LEN = 20
	local CONCAT = 21
	local JMP = 22
	local EQ = 23
	local LT = 24
	local LE = 25
	local TEST = 26
	local TESTSET = 27
	local CALL = 28
	local TAILCALL = 29
	local RETURN = 30
	local FORLOOP = 31
	local FORPREP = 32
	local TFORLOOP = 33
	local SETLIST = 34
	local CLOSE = 35
	local CLOSURE = 36
	local VARARG = 37
	
	-- instruction encoding and decoding

	function impl.encode(inst,a,b,c)
		inst = type(inst) == "string" and ins[inst] or inst
		local format = instructionFormats[inst]
		return
			format == iABC and
			bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b,0x1FF),23), bit.blshift(bit.band(c,0x1FF),14)) or
			format == iABx and
			bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b,0x3FFFF),14)) or
			bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b+131071,0x3FFFF),14))
	end

	function impl.decode(inst)
		local opcode = bit.band(inst,0x3F)
		local format = instructionFormats[opcode]
		if format == iABC then
			return opcode, bit.band(bit.brshift(inst,6),0xFF), bit.band(bit.brshift(inst,23),0x1FF), bit.band(bit.brshift(inst,14),0x1FF)
		elseif format == iABx then
			return opcode, bit.band(bit.brshift(inst,6),0xFF), bit.band(bit.brshift(inst,14),0x3FFFF)
		elseif format == iAsBx then
			local sBx = bit.band(bit.brshift(inst,14),0x3FFFF)-131071
			return opcode, bit.band(bit.brshift(inst,6),0xFF), sBx
		else
			error(opcode.." "..format)
		end
	end
	
	-- bytecode patching extras
	
	impl.patcher = {}

	local function patchJumpsAndAdd(bc, pc, op)
		for i=0, #bc.instructions do
			local o,a,b,c = impl.decode(bc.instructions[i])
			if o == LOADBOOL then
				if c ~= 0 then
					if i+1 == pc then
						error("TODO: Patch LOADBOOL")
					end
				end
			elseif o == JMP then
				if (i < pc and i+b+1 > pc) then
					b = b+1 --since this gets shifted forward...
				elseif (i > pc and i+b+1 <= pc) then
					b = b-1 --since this gets shifted backward...
				end
			elseif o == TEST then
				if i+1 == pc then
					error("TODO: Patch TEST")
				end
			elseif o == TESTSET then
				if i+1 == pc then
					error("TODO: Patch TESTSET")
				end
			elseif o == FORLOOP then
				if (i < pc and i+b+1 > pc) then
					b = b+1 --since this gets shifted forward...
				elseif (i > pc and i+b+1 <= pc) then
					b = b-1 --since this gets shifted backward...
				end
			elseif o == FORPREP then
				if (i < pc and i+b+1 > pc) then
					b = b+1 --since this gets shifted forward...
				elseif (i > pc and i+b+1 <= pc) then
					b = b-1 --since this gets shifted backward...
				end
			elseif o == TFORPREP then
				if i+1 == pc then
					error("TODO: Patch TFORPREP")
				end
			end
			bc.instructions[i] = impl.encode(o,a,b,c)
			print(i,bc.instructions[i])
		end
	
		for i=#bc.instructions, pc, -1 do
			bc.instructions[i+1] = bc.instructions[i]
			bc.sourceLines[i+1] = bc.sourceLines[i]
		end
		bc.instructions[pc] = op
	end
	
	-- Insert a single instruction at a specific program counter index
	function impl.patcher.insert(bc, pc, inst)
		--insert commands, fix jump targets--
		patchJumpsAndAdd(bc, pc, inst)
	end
	
	-- Replaces an instruction at a program counter index with another instruction
	function impl.patcher.replace(bc, pc, inst)
		bc.instructions[pc] = inst
	end
	
	-- Attempts to find an instruction after a specific program counter index
	function impl.patcher.find(bc, pc, o)
		if type(o) == "string" then
			o = ins[o]
		end
		
		for i=pc+1, #bc.instructions do
			local no = impl.decode(bc.instructions[i])
			if no == o then
				return i
			end
		end
	end

	function impl.patcher.addConstant(bc, const)
		-- If the constant already exists, just return the id of that constant
		for i, v in pairs(bc.constants) do
			if v == const then
				return i
			end
		end
		
		bc.constants[#bc.constants+1] = const
		return #bc.constants
	end
	
	return impl
end
