return function(bytecode)
	local impl = {}
	
	local debug = bytecode.printDebug
	local bit = bytecode.bit
	
	-- instruction definitions
	
	local instructionNames = {
		[0]="MOVE","LOADK","LOADKX","LOADBOOL","LOADNIL",
		"GETUPVAL","GETTABUP","GETTABLE",
		"SETTABUP","SETUPVAL","SETTABLE","NEWTABLE",
		"SELF","ADD","SUB","MUL","DIV","MOD","POW","UNM","NOT","LEN","CONCAT",
		"JMP","EQ","LT","LE","TEST","TESTSET","CALL","TAILCALL","RETURN",
		"FORLOOP","FORPREP","TFORCALL","TFORLOOP","SETLIST","CLOSURE","VARARG","EXTRAARG"
	}

	local iABC = 0
	local iABx = 1
	local iAsBx = 2
	local iA = 3
	local iAx = 4

	local instructionFormats = {
		[0]=iABC,iABx,iA,iABC,iABC,
		iABC,iABC,iABC,
		iABC,iABC,iABC,iABC,
		iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iAsBx,iABC,iAsBx,iABC,iABx,iABC,iAx
	}
	
	local ins = {}
	for i, v in pairs(instructionNames) do ins[v] = i end
	
	impl.instructionNames = instructionNames
	impl.instructions = ins
	impl.defaultReturn = 8388638

	-- instruction constants
	
	local MOVE = 0
	local LOADK = 1
	local LOADKX = 2
	local LOADBOOL = 3
	local LOADNIL = 4
	local GETUPVAL = 5
	local GETTABUP = 6
	local GETTABLE = 7
	local SETTABUP = 8
	local SETUPVAL = 9
	local SETTABLE = 10
	local NEWTABLE = 11
	local SELF = 12
	local ADD = 13
	local SUB = 14
	local MUL = 15
	local DIV = 16
	local MOD = 17
	local POW = 18
	local UNM = 19
	local NOT = 20
	local LEN = 21
	local CONCAT = 22
	local JMP = 23
	local EQ = 24
	local LT = 25
	local LE = 26
	local TEST = 27
	local TESTSET = 28
	local CALL = 29
	local TAILCALL = 30
	local RETURN = 31
	local FORLOOP = 32
	local FORPREP = 33
	local TFORCALL = 34
	local TFORLOOP = 35
	local SETLIST = 36
	local CLOSURE = 37
	local VARARG = 38
	local EXTRAARG = 39
	
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
	
	return impl
end