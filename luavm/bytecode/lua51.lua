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
	
	-- bytecode loading
	
	function impl.loadHeader(bc)
		local header = {version = 0x51}
		
		local fmtver = bc:byte(6)
		header.fmtver = fmtver
		debug("Format Version: %02X", fmtver)
		
		local types = bc:sub(7, 12)
		debug("Types: "..types:gsub(".", function(c) return string.format("%02X ", c:byte()) end))
		
		local bigEndian = types:byte(1) ~= 1
		header.bigEndian = bigEndian
		debug("Big Endian: %s", tostring(bigEndian))
		
		local integer = types:byte(2)
		header.integer = integer
		debug("Integer Size: %d bytes", integer)
		
		local size_t = types:byte(3)
		header.size_t = size_t
		debug("Size_T Size: %d bytes", size_t)
		
		local instruction = types:byte(4)
		header.instruction = instruction
		debug("Instruction Size: %d bytes", instruction)
		
		--integral or numerical number stuff
		do
			local integralNumbers = types:byte(6) ~= 0
			local size = types:byte(5)
			header.number_integral = integralNumbers
			header.number = size
			debug("Numerical Format: %d bytes <%s>", size, integralNumbers and "integral" or "floating")
		end
		
		return header
	end
	
	function impl.load(bc)
		debug("Lua 5.1 Bytecode Loader")
		
		local idx = 13
		local integer, size_t, number
		local bigEndian
		local binarytypes = bytecode.binarytypes
		
		local function u1()
			idx = idx+1
			return binarytypes.decode.u1(bc, idx-1, bigEndian)
		end
		
		local function u2()
			idx = idx+2
			return binarytypes.decode.u2(bc, idx-2, bigEndian)
		end
		
		local function u4()
			idx = idx+4
			return binarytypes.decode.u4(bc, idx-4, bigEndian)
		end
		
		local function u8()
			idx = idx+8
			return binarytypes.decode.u8(bc, idx-8, bigEndian)
		end
		
		local function float()
			idx = idx+4
			return binarytypes.decode.float(bc, idx-4, bigEndian)
		end
		
		local function double()
			idx = idx+8
			return binarytypes.decode.double(bc, idx-8, bigEndian)
		end
		
		local function ub(n)
			idx = idx+n
			return bc:sub(idx-n,idx-1)
		end
		
		local function us()
			local size = size_t()
			--print(size)
			return ub(size):sub(1,-2)
		end
		
		local integralSizes = {
			[1] = u1,
			[2] = u2,
			[4] = u4,
			[8] = u8
		}
		
		local numericSizes = {
			[4] = float,
			[8] = double
		}
		
		local header = impl.loadHeader(bc)
		
		assert(header.fmtver == 0 or header.fmtver == 255, "unknown format version: "..header.fmtver)
		bigEndian = header.bigEndian
		integer = assert(integralSizes[header.integer], "unsupported integer size: "..header.integer)
		size_t = assert(integralSizes[header.size_t], "unsupported size_t size: "..header.size_t)
		assert(header.instruction == 4, "unsupported instruction size: "..header.instruction)
		
		--integral or numerical number stuff
		do
			local integralNumbers = header.number_integral
			local size = header.number
			number = assert(integralNumbers and integralSizes[size] or numericSizes[size], "unsupported number size: "..(integralNumbers and "integral" or "floating").." "..size)
		end
		
		local function chunk()
			local function instructionList()
				local instructions = {}
				local count = integer()
				for i=1, count do
					instructions[i-1] = u4()
				end
				return instructions
			end
			
			local function constantList()
				local constants = {}
				local c = integer()
				for i=1, c do
					local type = u1()
					if type == 0 then
						constants[i-1] = nil
					elseif type == 1 then
						constants[i-1] = u1() > 0
					elseif type == 3 then
						constants[i-1] = number()
					elseif type == 4 then
						constants[i-1] = us()
					else
						error("Type: "..type)
					end
					debug("Constant %d: %s %s", i-1, tostring(constants[i-1]), type)
				end
				return constants
			end
			
			local function functionPrototypeList()
				local functionPrototypes = {}
				for i=1, integer() do
					functionPrototypes[i-1] = chunk()
				end
				return functionPrototypes
			end
			
			local function sourceLineList()
				local sourceLines = {}
				for i=1, integer() do
					sourceLines[i-1] = integer()
				end
				return sourceLines
			end
			
			local function localList()
				local locals = {}
				for i=1, integer() do
					locals[i-1] = {
						name = us(),
						startpc = integer(),
						endpc = integer()
					}
				end
				return locals
			end
			
			local function upvalueList()
				local upvalues = {}
				for i=1, integer() do
					upvalues[i-1] = us()
				end
				return upvalues
			end
			
			--extract an lua chunk into a table--
			local c = {header = header}
			c.name = us()
			c.lineDefined = integer()
			c.lastLineDefined = integer()
			c.nupval = u1()
			c.nparam = u1()
			c.isvararg = u1()
			c.maxStack = u1()
			c.instructions = instructionList()
			c.constants = constantList()
			c.functionPrototypes = functionPrototypeList()
			c.sourceLines = sourceLineList()
			c.locals = localList()
			c.upvalues = upvalueList()
			return c
		end
		
		return chunk()
	end
	
	function impl.save(chunk)
		local header = chunk.header
		local bc = {"\27Lua", string.char(header.version, 0)}
		
		bc[#bc+1] = string.char(
			header.bigEndian and 0 or 1,
			header.integer,
			header.size_t,
			header.instruction,
			header.number,
			header.number_integral and 1 or 0
		)
		
		local integer, size_t, number
		local bigEndian = header.bigEndian
		local binarytypes = bytecode.binarytypes
		
		local function u1(value)
			bc[#bc+1] = string.char(value)
		end
		
		local function u2(value)
			bc[#bc+1] = binarytypes.encode.u2(value, bigEndian)
		end
		
		local function u4(value)
			bc[#bc+1] = binarytypes.encode.u4(value, bigEndian)
		end
		
		local function u8(value)
			bc[#bc+1] = binarytypes.encode.u8(value, bigEndian)
		end
		
		local function float(value)
			bc[#bc+1] = binarytypes.encode.float(value, bigEndian)
		end
		
		local function double(value)
			bc[#bc+1] = binarytypes.encode.double(value, bigEndian)
		end
		
		local function us(str)
			size_t(#str+1)
			bc[#bc+1] = str
			bc[#bc+1] = string.char(0)
		end
		
		local function len(t)
			local n = 0
			for i, v in pairs(t) do n = n+1 end
			return n
		end
		
		local integralSizes = {
			[1] = u1,
			[2] = u2,
			[4] = u4,
			[8] = u8
		}
		
		local numericSizes = {
			[4] = float,
			[8] = double
		}
		
		assert(header.fmtver == 0 or header.fmtver == 255, "unknown format version: "..header.fmtver)
		bigEndian = header.bigEndian
		integer = assert(integralSizes[header.integer], "unsupported integer size: "..header.integer)
		size_t = assert(integralSizes[header.size_t], "unsupported size_t size: "..header.size_t)
		assert(header.instruction == 4, "unsupported instruction size: "..header.instruction)
		
		--integral or numerical number stuff
		do
			local integralNumbers = header.number_integral
			local size = header.number
			number = assert(integralNumbers and integralSizes[size] or numericSizes[size], "unsupported number size: "..(integralNumbers and "integral" or "floating").." "..size)
		end
		
		local function dumpChunk(chunk)
			us(chunk.name)
			integer(chunk.lineDefined)
			integer(chunk.lastLineDefined)
			u1(chunk.nupval)
			u1(chunk.nparam)
			u1(chunk.isvararg)
			u1(chunk.maxStack)
			
			local lenInstructions = len(chunk.instructions)
			integer(lenInstructions)
			for i=0, lenInstructions-1 do
				u4(chunk.instructions[i])
			end
			
			local lenConstants = len(chunk.constants)
			integer(lenConstants)
			for i=0, lenConstants-1 do
				local v = chunk.constants[i]
				local t = type(v)
				u1(t == "nil" and 0 or t == "boolean" and 1 or t == "number" and 3 or t == "string" and 4 or error("Unknown constant type."))
				if t == "boolean" then
					u1(v and 1 or 0)
				elseif t == "number" then
					double(v)
				elseif t == "string" then
					us(v)
				end
			end
			
			local lenFunctionPrototypes = len(chunk.functionPrototypes)
			integer(lenFunctionPrototypes)
			for i=0, lenFunctionPrototypes-1 do
				writeChunk(chunk.functionPrototypes[i])
			end
			
			local lenSourceLines = len(chunk.sourceLines)
			integer(lenSourceLines)
			for i=0, lenSourceLines-1 do
				integer(chunk.sourceLines[i])
			end
			
			local lenLocals = len(chunk.locals)
			integer(lenLocals)
			for i=0, lenLocals-1 do
				local l = chunk.locals[i]
				us(l.name)
				integer(l.startpc)
				integer(l.endpc)
			end
			
			local lenUpvalues = len(chunk.upvalues)
			integer(lenUpvalues)
			for i=0, lenUpvalues-1 do
				us(chunk.upvalues[i])
			end
		end
		
		dumpChunk(chunk)
		return table.concat(bc)
	end
	
	function impl.new(header)
		return {
			header = header,
			lineDefined = 0,
			isvararg = 2,
			sourceLines = {},
			nparam = 0,
			lastLineDefined = 0,
			maxStack = 2,
			upvalues = {},
			instructions = {[0]=impl.defaultReturn},
			locals = {},
			functionPrototypes = {},
			nupval = 0,
			name = "",
			constants = {}
		}
	end
	
	return impl
end
