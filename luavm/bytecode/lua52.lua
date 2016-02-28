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
	local iAx = 4

	local instructionFormats = {
		[0]=iABC,iABx,iABC,iABC,iABC,
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
		
		if format == iABC then
			return bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b,0x1FF),23), bit.blshift(bit.band(c,0x1FF),14))
		elseif format == iABx then
			return bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b,0x3FFFF),14))
		elseif format == iAsBx then
			return bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b+131071,0x3FFFF),14))
		elseif format == iAx then
			return bit.bor(inst,bit.blshift(a,6))
		else
			error("unknown opcode "..inst)
		end
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
		elseif format == iAx then
			return opcode, bit.brshift(inst,6)
		else
			error("unknown opcode "..opcode)
		end
	end
	
	-- bytecode loading
	
	function impl.loadHeader(bc)
		local header = {version = 0x52}
		
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
		debug("Lua 5.2 Bytecode Loader")
		
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
		
		assert(ub(6) == "\25\147\r\n\26\n", "header has invalid tail")
		
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
			
			local function upvalueDefinitionList()
				local upvalues = {}
				for i=1, integer() do
					upvalues[i-1] = {instack=u1(),idx=u1()}
					debug("upvalue %d instack=%d idx=%d", i-1, upvalues[i-1].instack, upvalues[i-1].idx)
				end
				return upvalues
			end
			
			--extract an lua chunk into a table--
			local c = {header = header}
			
			c.lineDefined = integer()
			c.lastLineDefined = integer()
			c.nparam = u1()
			c.isvararg = u1()
			c.maxStack = u1()
			c.instructions = instructionList()
			c.constants = constantList()
			c.functionPrototypes = functionPrototypeList()
			c.upvalues = upvalueDefinitionList()
			c.name = us()
			c.sourceLines = sourceLineList()
			c.locals = localList()
			c.upvaluesDebug = upvalueList()
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
		
		bc[#bc+1] = "\25\147\r\n\26\n"
		
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
			integer(chunk.lineDefined)
			integer(chunk.lastLineDefined)
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
			
			local lenUpvalueDefs = len(chunk.upvalues)
			integer(lenUpvalueDefs)
			for i=0, lenUpvalueDefs-1 do
				u1(chunk.upvalues[i].instack and 1 or 0)
				u1(chunk.upvalues[i].idx)
			end
			
			us(chunk.name)
			
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
			
			local lenUpvaluesDebug = len(chunk.upvaluesDebug)
			integer(lenUpvaluesDebug)
			for i=0, lenUpvaluesDebug-1 do
				us(chunk.upvaluesDebug[i])
			end
		end
		
		dumpChunk(chunk)
		return table.concat(bc)
	end
	
	--TODO: impl.new
	
	return impl
end